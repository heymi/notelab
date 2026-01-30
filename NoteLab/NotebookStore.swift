import Combine

import SwiftUI
import SwiftData

final class NotebookStore: ObservableObject {
    @Published var notebooks: [Notebook]
    @Published var whiteboard: Note
    @Published private var previewImageCache: [UUID: [Data]] = [:]
    @Published private var previewItemCache: [UUID: [NotebookPreviewItem]] = [:]

    private var linkBlocks: [UUID: [LinkedNoteBlock]] = [:]
    private var documents: [UUID: NoteDocument] = [:]
    private var modelContext: ModelContext?
    private var ownerId: UUID?
    private var pendingSaveTask: Task<Void, Never>?
    private var previewImageLoading: Set<UUID> = []

    private let whiteboardId = UUID(uuidString: "E5E00B5A-0A95-4F8E-8F6A-0E1C1D7F3B55")!
    private let whiteboardContentKey = "whiteboard.content"
    private let whiteboardContentRTFKey = "whiteboard.content.rtf"
    private let whiteboardTitleKey = "whiteboard.title"
    private let linkBlocksKey = "note.link.blocks"

    init(notebooks: [Notebook] = []) {
        self.notebooks = notebooks
        let savedRTF = UserDefaults.standard.data(forKey: whiteboardContentRTFKey)
        let savedContent = UserDefaults.standard.string(forKey: whiteboardContentKey) ?? ""
        let savedTitle = UserDefaults.standard.string(forKey: whiteboardTitleKey) ?? "白板"
        let whiteboardContent = RichTextCodec.plainText(from: savedRTF) ?? savedContent
        self.whiteboard = Note(
            id: whiteboardId,
            title: savedTitle,
            summary: "",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: Date(),
            updatedAt: Date(),
            contentRTF: savedRTF,
            content: whiteboardContent
        )
        self.whiteboard.updateMetrics()
        loadLinkBlocks()
    }

    func configure(ownerId: UUID, context: ModelContext) {
        self.ownerId = ownerId
        self.modelContext = context
        loadFromLocalCache()
    }

    func resetForSignOut() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        notebooks = []
        documents.removeAll()
        linkBlocks.removeAll()
        previewItemCache.removeAll()
        ownerId = nil
        modelContext = nil
    }

    func loadFromLocalCache() {
        guard let ownerId, let modelContext else { return }
        // #region agent log
        DebugReporter.log(
            hypothesisId: "H3",
            location: "NotebookStore.swift:loadFromLocalCache",
            message: "loadFromLocalCache enter",
            data: ["ownerIdSuffix": String(ownerId.uuidString.suffix(6))]
        )
        // #endregion

        do {
            let predicate = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.deletedAt == nil
            }
            let notebooksFetch = FetchDescriptor<LocalNotebook>(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\.isPinned, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse)
                ]
            )
            let localNotebooks = try modelContext.fetch(notebooksFetch)
            // #region agent log
            DebugReporter.log(
                hypothesisId: "H3",
                location: "NotebookStore.swift:loadFromLocalCache",
                message: "loadFromLocalCache fetched",
                data: ["count": localNotebooks.count]
            )
            // #endregion

            let newNotebooks = localNotebooks.map { local in
                let color = NotebookColor(rawValue: local.colorRaw) ?? .lime
                let notes = (local.notes)
                    .filter { $0.deletedAt == nil }
                    .sorted {
                        if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                        return $0.createdAt > $1.createdAt
                    }
                    .map { $0.asNote() }

                return Notebook(
                    id: local.id,
                    title: local.title,
                    color: color,
                    iconName: local.iconName,
                    createdAt: local.createdAt,
                    notes: notes,
                    isPinned: local.isPinned,
                    notebookDescription: local.notebookDescription
                )
            }
            
            // Differential update to preserve identity and avoid full UI rebuild
            for (index, newNotebook) in newNotebooks.enumerated() {
                if let existingIndex = notebooks.firstIndex(where: { $0.id == newNotebook.id }) {
                    if notebooks[existingIndex] != newNotebook {
                        notebooks[existingIndex] = newNotebook
                    }
                } else {
                    if index < notebooks.count {
                        notebooks.insert(newNotebook, at: index)
                    } else {
                        notebooks.append(newNotebook)
                    }
                }
            }
            
            // Remove deleted notebooks
            notebooks.removeAll { nb in !newNotebooks.contains(where: { $0.id == nb.id }) }
            
            // Ensure order matches
            if notebooks != newNotebooks {
                // If simple updates didn't result in correct order/content, fallback to full replace
                // This handles complex reordering efficiently
                self.notebooks = newNotebooks
            }

            let validIds = Set(newNotebooks.map { $0.id })
            previewImageCache = previewImageCache.filter { validIds.contains($0.key) }
            previewImageLoading = previewImageLoading.filter { validIds.contains($0) }
            previewItemCache = previewItemCache.filter { validIds.contains($0.key) }
            refreshPreviewCaches(for: newNotebooks)

        } catch {
            print("NotebookStore: loadFromLocalCache failed: \(error.localizedDescription)")
            // #region agent log
            DebugReporter.log(
                hypothesisId: "H4",
                location: "NotebookStore.swift:loadFromLocalCache",
                message: "loadFromLocalCache failed",
                data: ["error": error.localizedDescription]
            )
            // #endregion
        }
    }

    func document(for noteId: UUID, fallbackText: String) -> NoteDocument {
        if let doc = documents[noteId] {
            return doc
        }
        let doc = NoteDocument.fromMarkdown(fallbackText)
        documents[noteId] = doc
        return doc
    }

    func updateDocument(noteId: UUID, document: NoteDocument) {
        documents[noteId] = document
    }

    func noteBinding(noteId: UUID) -> Binding<Note>? {
        Binding<Note>(
            get: {
                for notebook in self.notebooks {
                    if let note = notebook.notes.first(where: { $0.id == noteId }) {
                        return note
                    }
                }
                return Note(
                    id: noteId,
                    title: "未找到笔记",
                    summary: "",
                    paragraphCount: 0,
                    bulletCount: 0,
                    hasAdditionalContext: false,
                    createdAt: Date(),
                    updatedAt: Date(),
                    contentRTF: nil,
                    content: ""
                )
            },
            set: { newValue in
                self.applyLocalUpdate(note: newValue)
            }
        )
    }

    func noteMetadata(for noteId: UUID) -> (note: Note, notebookDescription: String?)? {
        for notebook in notebooks {
            if let note = notebook.notes.first(where: { $0.id == noteId }) {
                return (note, notebook.notebookDescription)
            }
        }
        return nil
    }

    func addNote(to notebookId: UUID) -> UUID? {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookId }) else {
            return nil
        }

        let newNote = Note(
            id: UUID(),
            title: "新笔记",
            summary: "",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: Date(),
            updatedAt: Date(),
            contentRTF: nil,
            content: ""
        )
        notebooks[index].notes.insert(newNote, at: 0)
        sortNotes(in: index)

        if let ownerId, let modelContext {
            upsertLocalNote(ownerId: ownerId, notebookId: notebookId, note: newNote, context: modelContext)
        }

        schedulePreviewItemsUpdate(notebook: notebooks[index])

        return newNote.id
    }

    func addNote(to notebookId: UUID, title: String, content: String) -> UUID? {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookId }) else {
            return nil
        }

        var newNote = Note(
            id: UUID(),
            title: title,
            summary: "",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: Date(),
            updatedAt: Date(),
            contentRTF: nil,
            content: content
        )
        newNote.updateMetrics()
        notebooks[index].notes.insert(newNote, at: 0)
        sortNotes(in: index)

        if let ownerId, let modelContext {
            upsertLocalNote(ownerId: ownerId, notebookId: notebookId, note: newNote, context: modelContext)
        }

        schedulePreviewItemsUpdate(notebook: notebooks[index])

        return newNote.id
    }

    func addNotebook(title: String, color: NotebookColor, iconName: String) -> UUID? {
        guard let ownerId, let modelContext else { return nil }
        let id = UUID()
        let now = Date()

        let local = LocalNotebook(
            id: id,
            ownerId: ownerId,
            title: title,
            colorRaw: color.rawValue,
            iconName: iconName,
            createdAt: now,
            remoteUpdatedAt: now,
            deletedAt: nil,
            isDirty: true,
            isPinned: false,
            notebookDescription: "",
            notes: []
        )
        modelContext.insert(local)
        scheduleSave()

        notebooks.insert(
            Notebook(id: id, title: title, color: color, iconName: iconName, createdAt: now, notes: []),
            at: 0
        )
        return id
    }

    func updateNotebook(id: UUID, title: String? = nil, color: NotebookColor? = nil, description: String? = nil) {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        
        // 更新内存中的数据
        if let title = title {
            notebooks[index].title = title
        }
        if let color = color {
            notebooks[index].color = color
        }
        if let description = description {
            notebooks[index].notebookDescription = description
        }
        
        // 更新本地存储
        guard let ownerId, let modelContext else { return }
        do {
            let predicate = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.id == id
            }
            let fetch = FetchDescriptor<LocalNotebook>(predicate: predicate)
            if let local = try modelContext.fetch(fetch).first {
                if let title = title {
                    local.title = title
                }
                if let color = color {
                    local.colorRaw = color.rawValue
                }
                if let description = description {
                    local.notebookDescription = description
                }
                local.isDirty = true
                scheduleSave()
            }
        } catch {
            // ignore
        }
    }

    func deleteNotebook(id: UUID) {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        notebooks.remove(at: index)
        
        guard let ownerId, let modelContext else { return }
        do {
            let predicate = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.id == id
            }
            let fetch = FetchDescriptor<LocalNotebook>(predicate: predicate)
            if let local = try modelContext.fetch(fetch).first {
                let now = Date()
                local.deletedAt = now
                local.isDirty = true
                // Soft-delete all notes as well (so sync can apply it).
                for note in local.notes {
                    note.deletedAt = now
                    note.isDirty = true
                }
                scheduleSave()
            }
        } catch {
            // ignore
        }
    }

    // MARK: - Note Management

    func notebookId(for noteId: UUID) -> UUID? {
        for notebook in notebooks {
            if notebook.notes.contains(where: { $0.id == noteId }) {
                return notebook.id
            }
        }
        return nil
    }

    func moveNote(noteId: UUID, to targetNotebookId: UUID) {
        guard let sourceIndex = notebooks.firstIndex(where: { $0.notes.contains(where: { $0.id == noteId }) }),
              let noteIndex = notebooks[sourceIndex].notes.firstIndex(where: { $0.id == noteId }),
              let targetIndex = notebooks.firstIndex(where: { $0.id == targetNotebookId }) else {
            return
        }

        if sourceIndex == targetIndex {
            return
        }

        let note = notebooks[sourceIndex].notes.remove(at: noteIndex)
        notebooks[targetIndex].notes.insert(note, at: 0)
        sortNotes(in: targetIndex)
        schedulePreviewItemsUpdate(notebook: notebooks[sourceIndex])
        schedulePreviewItemsUpdate(notebook: notebooks[targetIndex])

        guard let ownerId, let modelContext else { return }
        let id = noteId
        do {
            let notePredicate = #Predicate<LocalNote> { n in
                n.ownerId == ownerId && n.id == id
            }
            let noteFetch = FetchDescriptor<LocalNote>(predicate: notePredicate)
            guard let localNote = try modelContext.fetch(noteFetch).first else { return }

            let notebookPredicate = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.id == targetNotebookId
            }
            let notebookFetch = FetchDescriptor<LocalNotebook>(predicate: notebookPredicate)
            if let localNotebook = try modelContext.fetch(notebookFetch).first {
                localNote.notebook = localNotebook
                localNote.isDirty = true
                scheduleSave()
            }
        } catch {
            // ignore
        }
    }

    func deleteNote(noteId: UUID, from notebookId: UUID) {
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookId }),
              let noteIndex = notebooks[notebookIndex].notes.firstIndex(where: { $0.id == noteId }) else {
            return
        }
        notebooks[notebookIndex].notes.remove(at: noteIndex)
        documents.removeValue(forKey: noteId)
        linkBlocks.removeValue(forKey: noteId)
        schedulePreviewItemsUpdate(notebook: notebooks[notebookIndex])

        guard let ownerId, let modelContext else { return }
        let id = noteId
        do {
            let predicate = #Predicate<LocalNote> { n in
                n.ownerId == ownerId && n.id == id
            }
            let fetch = FetchDescriptor<LocalNote>(predicate: predicate)
            if let local = try modelContext.fetch(fetch).first {
                local.deletedAt = Date()
                local.isDirty = true
                scheduleSave()
            }
        } catch {
            // ignore
        }
    }

    func toggleNotePinned(noteId: UUID, in notebookId: UUID) {
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookId }),
              let noteIndex = notebooks[notebookIndex].notes.firstIndex(where: { $0.id == noteId }) else {
            return
        }
        notebooks[notebookIndex].notes[noteIndex].isPinned.toggle()
        sortNotes(in: notebookIndex)

        guard let ownerId, let modelContext else { return }
        let id = noteId
        do {
            let predicate = #Predicate<LocalNote> { n in
                n.ownerId == ownerId && n.id == id
            }
            let fetch = FetchDescriptor<LocalNote>(predicate: predicate)
            if let local = try modelContext.fetch(fetch).first {
                local.isPinned.toggle()
                scheduleSave()
            }
        } catch {
            // ignore
        }
    }

    private func sortNotes(in notebookIndex: Int) {
        notebooks[notebookIndex].notes.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    // MARK: - Notebook Management

    func toggleNotebookPinned(notebookId: UUID) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookId }) else {
            return
        }
        notebooks[index].isPinned.toggle()
        sortNotebooks()

        guard let ownerId, let modelContext else { return }
        let id = notebookId
        do {
            let predicate = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.id == id
            }
            let fetch = FetchDescriptor<LocalNotebook>(predicate: predicate)
            if let local = try modelContext.fetch(fetch).first {
                local.isPinned.toggle()
                scheduleSave()
            }
        } catch {
            // ignore
        }
    }

    private func sortNotebooks() {
        notebooks.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func persistWhiteboard() {
        UserDefaults.standard.set(whiteboard.title, forKey: whiteboardTitleKey)
        UserDefaults.standard.set(whiteboard.content, forKey: whiteboardContentKey)
        if let data = whiteboard.contentRTF {
            UserDefaults.standard.set(data, forKey: whiteboardContentRTFKey)
        } else {
            UserDefaults.standard.removeObject(forKey: whiteboardContentRTFKey)
        }
    }

    func linkBlocks(for noteId: UUID) -> [LinkedNoteBlock] {
        linkBlocks[noteId] ?? []
    }

    func addLinkBlock(_ block: LinkedNoteBlock, to noteId: UUID) {
        var blocks = linkBlocks[noteId] ?? []
        blocks.append(block)
        linkBlocks[noteId] = blocks
        persistLinkBlocks()
    }

    func updateLinkBlocks(for noteId: UUID, _ transform: ([LinkedNoteBlock]) -> [LinkedNoteBlock]) {
        let blocks = linkBlocks[noteId] ?? []
        linkBlocks[noteId] = transform(blocks)
        persistLinkBlocks()
    }

    private func persistLinkBlocks() {
        let payload = linkBlocks.map { key, value in
            LinkBlocksPayload(noteId: key.uuidString, blocks: value)
        }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: linkBlocksKey)
        }
    }

    private func loadLinkBlocks() {
        guard let data = UserDefaults.standard.data(forKey: linkBlocksKey),
              let payload = try? JSONDecoder().decode([LinkBlocksPayload].self, from: data) else {
            return
        }
        var map: [UUID: [LinkedNoteBlock]] = [:]
        for item in payload {
            if let id = UUID(uuidString: item.noteId) {
                map[id] = item.blocks
            }
        }
        linkBlocks = map
    }

    func collectOpenTodos() -> [LocalTodoItem] {
        var results: [LocalTodoItem] = []

        func appendTodos(from note: Note, notebookId: UUID, notebookTitle: String, isWhiteboard: Bool) {
            let lines = note.content.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            for (idx, line) in lines.enumerated() {
                let text = String(line)
                guard let item = parseChecklistLine(text), !item.isChecked else { continue }
                let id = "\(note.id.uuidString):\(idx)"
                results.append(
                    LocalTodoItem(
                        id: id,
                        title: item.title,
                        noteId: note.id,
                        noteTitle: note.title,
                        notebookId: notebookId,
                        notebookTitle: notebookTitle,
                        lineIndex: idx,
                        isWhiteboard: isWhiteboard
                    )
                )
            }
        }

        for notebook in notebooks {
            for note in notebook.notes {
                appendTodos(from: note, notebookId: notebook.id, notebookTitle: notebook.title, isWhiteboard: false)
            }
        }

        appendTodos(from: whiteboard, notebookId: whiteboard.id, notebookTitle: whiteboard.title, isWhiteboard: true)
        return results
    }

    func collectPlanTasks() -> [PlanTaskRequest] {
        var results: [PlanTaskRequest] = []
        func appendTasks(from note: Note, notebookId: UUID, notebookTitle: String) {
            let lines = note.content.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            for (idx, line) in lines.enumerated() {
                let text = String(line)
                guard let item = parseChecklistLine(text), !item.isChecked else { continue }
                let taskId = "\(note.id.uuidString):\(idx)"
                let task = PlanTaskRequest(
                    id: taskId,
                    text: item.title,
                    priority: "unknown",
                    source: PlanTaskSource(
                        noteTitle: note.title,
                        notebookTitle: notebookTitle,
                        noteId: note.id.uuidString,
                        notebookId: notebookId.uuidString
                    ),
                    sourceAnchor: PlanTaskAnchor(paragraphIndex: idx)
                )
                results.append(task)
            }
        }

        for notebook in notebooks {
            for note in notebook.notes {
                appendTasks(from: note, notebookId: notebook.id, notebookTitle: notebook.title)
            }
        }

        appendTasks(from: whiteboard, notebookId: whiteboard.id, notebookTitle: whiteboard.title)
        return results
    }

    /// 获取笔记本中所有笔记的图片附件数据（用于封面预览）
    func previewImages(for notebookId: UUID, limit: Int = 4) -> [Data] {
        guard let notebook = notebooks.first(where: { $0.id == notebookId }) else {
            return []
        }
        
        var images: [Data] = []

        let orderedNotes = Self.orderedNotesForCoverPreview(notes: notebook.notes)

        for note in orderedNotes {
            // Use in-memory document if available; otherwise parse from stored markdown.
            let document = documents[note.id] ?? NoteDocument.fromMarkdown(note.content)
            for block in document.blocks {
                if block.kind == .attachment,
                   let attachment = block.attachment,
                   attachment.type == .image {
                    if let data = attachment.data {
                        images.append(data)
                    } else if let cached = AttachmentCache.load(attachmentId: attachment.id, fileName: attachment.fileName) {
                        images.append(cached)
                    }
                    if images.count >= limit { return images }
                }
            }
        }
        
        return images
    }

    func previewImagesCached(for notebookId: UUID) -> [Data] {
        previewImageCache[notebookId] ?? []
    }

    func previewItemsCached(for notebookId: UUID) -> [NotebookPreviewItem] {
        previewItemCache[notebookId] ?? []
    }

    func loadPreviewImagesIfNeeded(notebookId: UUID, limit: Int = 2) async {
        guard previewImageCache[notebookId] == nil else { return }
        guard !previewImageLoading.contains(notebookId) else { return }
        guard let notebook = notebooks.first(where: { $0.id == notebookId }) else { return }
        previewImageLoading.insert(notebookId)
        let notes = notebook.notes

        let images = await Task.detached(priority: .utility) {
            Self.previewImagesFromNotes(notes: notes, limit: limit)
        }.value

        await MainActor.run {
            self.previewImageCache[notebookId] = images
            self.previewImageLoading.remove(notebookId)
        }
    }

    private static func previewImagesFromNotes(notes: [Note], limit: Int) -> [Data] {
        guard limit > 0 else { return [] }
        var images: [Data] = []
        let sortedNotes = orderedNotesForCoverPreview(notes: notes)

        for note in sortedNotes {
            let document = NoteDocument.fromMarkdown(note.content)
            for block in document.blocks {
                if block.kind == .attachment,
                   let attachment = block.attachment,
                   attachment.type == .image {
                    if let data = attachment.data {
                        images.append(data)
                    } else if let cached = AttachmentCache.load(attachmentId: attachment.id, fileName: attachment.fileName) {
                        images.append(cached)
                    }
                    if images.count >= limit { return images }
                }
            }
        }
        return images
    }

    private func refreshPreviewCaches(for notebooks: [Notebook]) {
        for notebook in notebooks {
            schedulePreviewItemsUpdate(notebook: notebook)
        }
    }

    private func schedulePreviewItemsUpdate(notebook: Notebook) {
        Task.detached(priority: .utility) { [weak self] in
            let items = Self.previewItemsFromNotebook(notebook)
            await MainActor.run {
                self?.previewItemCache[notebook.id] = items
            }
        }
    }

    private static func previewItemsFromNotebook(_ notebook: Notebook) -> [NotebookPreviewItem] {
        if let pinnedNote = notebook.notes
            .filter({ $0.isPinned })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            return previewItemsFromNote(pinnedNote)
        }

        guard let note = notebook.notes.max(by: { $0.createdAt < $1.createdAt }) else {
            return []
        }
        return previewItemsFromNote(note)
    }

    private static func orderedNotesForCoverPreview(notes: [Note]) -> [Note] {
        let pinnedNotes = notes
            .filter { $0.isPinned }
            .sorted { $0.updatedAt > $1.updatedAt }
        let unpinnedNotes = notes
            .filter { !$0.isPinned }
            .sorted { $0.createdAt > $1.createdAt }
        return pinnedNotes + unpinnedNotes
    }

    private static func previewItemsFromNote(_ note: Note, maxItems: Int = 8) -> [NotebookPreviewItem] {
        let document = NoteDocument.fromMarkdown(note.content)
        var results: [NotebookPreviewItem] = []
        var numberedIndex = 0
        var isInNumberedSequence = false

        for block in document.blocks {
            if block.kind == .attachment {
                guard let attachment = block.attachment, attachment.type == .image else {
                    continue
                }
                if let data = attachment.data {
                    results.append(.image(data))
                } else if let cached = AttachmentCache.load(attachmentId: attachment.id, fileName: attachment.fileName) {
                    results.append(.image(cached))
                }
                if results.count >= maxItems { break }
                continue
            }

            let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if block.kind != .table && trimmed.isEmpty {
                continue
            }

            var numberIndex: Int?
            if block.kind == .numbered {
                numberedIndex = isInNumberedSequence ? numberedIndex + 1 : 1
                isInNumberedSequence = true
                numberIndex = numberedIndex
            } else {
                isInNumberedSequence = false
                numberedIndex = 0
            }

            results.append(.block(block: block, numberIndex: numberIndex))
            if results.count >= maxItems {
                break
            }
        }

        return results
    }
    
    func recentNoteDigests(limit: Int) -> [NoteDigest] {
        var allNotes: [(note: Note, notebookTitle: String)] = []
        for notebook in notebooks {
            for note in notebook.notes {
                allNotes.append((note, notebook.title))
            }
        }

        let sorted = allNotes.sorted { $0.note.createdAt > $1.note.createdAt }
        let slice = sorted.prefix(limit)
        return slice.map { buildDigest(note: $0.note, notebookTitle: $0.notebookTitle) }
    }

    func recentNoteDigests(limit: Int, budget: NoteDigestBudget) -> [NoteDigest] {
        var allNotes: [(note: Note, notebookTitle: String)] = []
        for notebook in notebooks {
            for note in notebook.notes {
                allNotes.append((note, notebook.title))
            }
        }
        let sorted = allNotes.sorted { $0.note.createdAt > $1.note.createdAt }
        let slice = Array(sorted.prefix(limit))
        return NoteDigestBuilder.buildRecentDigests(notes: slice, budget: budget)
    }

    func randomOldNoteSnippets(olderThanDays: Int, limit: Int) -> [MemorySnippet] {
        guard limit > 0 else { return [] }
        var allNotes: [(note: Note, notebookTitle: String)] = []
        for notebook in notebooks {
            for note in notebook.notes {
                allNotes.append((note, notebook.title))
            }
        }

        func buildSnippets(from notes: [(note: Note, notebookTitle: String)]) -> [MemorySnippet] {
            let shuffled = notes.shuffled()
            var imageSnippets: [MemorySnippet] = []
            var textSnippets: [MemorySnippet] = []
            
            for item in shuffled {
                // Optimization: stop if we have enough candidates
                if imageSnippets.count >= limit && textSnippets.count >= limit { break }
                
                var imageData: Data?
                let document = documents[item.note.id] ?? NoteDocument.fromMarkdown(item.note.content)
                for block in document.blocks {
                    if block.kind == .attachment,
                       let attachment = block.attachment,
                       attachment.type == .image {
                        if let data = attachment.data {
                            imageData = data
                            break
                        } else if let cached = AttachmentCache.load(attachmentId: attachment.id, fileName: attachment.fileName) {
                            imageData = cached
                            break
                        }
                    }
                }
                
                let cleaned = sanitizeContent(item.note.content)
                let excerpt = cleaned.split(whereSeparator: \.isNewline).prefix(3).joined(separator: " ")
                
                if let data = imageData {
                    imageSnippets.append(MemorySnippet(
                        id: UUID(),
                        noteId: item.note.id,
                        noteTitle: item.note.title,
                        notebookTitle: item.notebookTitle,
                        excerpt: String(excerpt.prefix(160)),
                        imageData: data,
                        createdAt: item.note.createdAt
                    ))
                } else if !excerpt.isEmpty {
                    textSnippets.append(MemorySnippet(
                        id: UUID(),
                        noteId: item.note.id,
                        noteTitle: item.note.title,
                        notebookTitle: item.notebookTitle,
                        excerpt: String(excerpt.prefix(160)),
                        imageData: nil,
                        createdAt: item.note.createdAt
                    ))
                }
            }
            
            return Array((imageSnippets + textSnippets).prefix(limit))
        }

        let fallbackDays = [olderThanDays, 3, 1, 0]
        for days in fallbackDays {
            let cutoff: Date
            if days == 0 {
                cutoff = Calendar.current.startOfDay(for: Date())
            } else {
                cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            }
            let filtered = allNotes.filter { $0.note.createdAt < cutoff }
            let snippets = buildSnippets(from: filtered)
            if !snippets.isEmpty {
                return snippets
            }
        }

        return []
    }

    func findMessyNotes(limit: Int) -> [MessyNoteCandidate] {
        guard limit > 0 else { return [] }
        var candidates: [MessyNoteCandidate] = []
        for notebook in notebooks {
            for note in notebook.notes {
                if candidates.count >= limit { return candidates }
                if let reason = messyReason(for: note) {
                    candidates.append(
                        MessyNoteCandidate(
                            id: UUID(),
                            noteId: note.id,
                            noteTitle: note.title,
                            notebookTitle: notebook.title,
                            reason: reason
                        )
                    )
                }
            }
        }
        return candidates
    }

    func findNoteConnections(limit: Int, budget: NoteDigestBudget) -> [NoteConnection] {
        guard limit > 0 else { return [] }
        let digests = recentNoteDigests(limit: budget.maxNotes, budget: budget)
        var connections: [NoteConnection] = []

        for i in 0..<digests.count {
            for j in (i + 1)..<digests.count {
                if connections.count >= limit { return connections }
                let a = digests[i]
                let b = digests[j]
                let keywordsA = Set(a.headings + a.bullets)
                let keywordsB = Set(b.headings + b.bullets)
                let overlap = keywordsA.intersection(keywordsB).filter { !$0.isEmpty }
                if overlap.count >= 2 {
                    let reason = "关键词重合：" + overlap.prefix(2).joined(separator: "、")
                    if let noteIdA = UUID(uuidString: a.noteId),
                       let noteIdB = UUID(uuidString: b.noteId) {
                        connections.append(
                            NoteConnection(
                                id: UUID(),
                                sourceNoteId: noteIdA,
                                targetNoteId: noteIdB,
                                sourceTitle: a.noteTitle,
                                targetTitle: b.noteTitle,
                                reason: reason
                            )
                        )
                    }
                }
            }
        }
        return connections
    }

    func countNotesCreated(after date: Date?) -> Int {
        guard let date else { return notebooks.reduce(0) { $0 + $1.notes.count } }
        var count = 0
        for notebook in notebooks {
            for note in notebook.notes where note.createdAt > date {
                count += 1
            }
        }
        return count
    }

    private func buildDigest(note: Note, notebookTitle: String) -> NoteDigest {
        let cleaned = sanitizeContent(note.content)
        let lines = cleaned.split(whereSeparator: { $0.isNewline }).map { String($0) }

        var headings: [String] = []
        var bullets: [String] = []
        var paragraphs: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                if !title.isEmpty {
                    headings.append(String(title.prefix(80)))
                }
                continue
            }
            if trimmed.hasPrefix("- [ ] ") {
                bullets.append(String(trimmed.dropFirst(6).prefix(120)))
                continue
            }
            if trimmed.hasPrefix("- ") {
                bullets.append(String(trimmed.dropFirst(2).prefix(120)))
                continue
            }
            paragraphs.append(trimmed)
        }

        let cappedHeadings = Array(headings.prefix(8))
        let cappedBullets = Array(bullets.prefix(12))
        let cappedParagraphs = Array(paragraphs.prefix(4)).map { String($0.prefix(120)) }
        let snippet = cappedParagraphs.joined(separator: " ")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let createdAt = formatter.string(from: note.createdAt)

        return NoteDigest(
            noteId: note.id.uuidString,
            noteTitle: note.title,
            notebookTitle: notebookTitle,
            createdAt: createdAt,
            headings: cappedHeadings,
            bullets: cappedBullets,
            snippet: snippet
        )
    }

    private func sanitizeContent(_ content: String) -> String {
        let stripped = stripFencedCodeBlocks(in: content)
        let lines = stripped.split(whereSeparator: \.isNewline)
        var results: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                continue
            }
            results.append(String(trimmed))
        }
        return results.joined(separator: "\n")
    }

    private func messyReason(for note: Note) -> String? {
        let doc = documents[note.id] ?? NoteDocument.fromMarkdown(note.content)
        let headings = doc.blocks.filter { $0.kind == .heading }.count
        let bullets = doc.blocks.filter { $0.kind == .bullet || $0.kind == .todo || $0.kind == .numbered }.count
        let paragraphs = doc.blocks.filter { $0.kind == .paragraph }.count
        let contentLength = note.content.trimmingCharacters(in: .whitespacesAndNewlines).count

        if contentLength < 240 { return nil }
        if headings == 0 && bullets == 0 && paragraphs >= 4 {
            return "段落较多且缺少标题/列表结构"
        }
        if headings == 0 && contentLength > 600 {
            return "内容偏长但缺少标题层级"
        }
        if bullets == 0 && paragraphs >= 6 {
            return "缺少列表拆分，阅读成本较高"
        }
        return nil
    }

    private func stripFencedCodeBlocks(in content: String) -> String {
        let lines = content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var output: [String] = []
        var insideCode = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.hasPrefix("```") {
                insideCode.toggle()
                if !insideCode {
                    output.append("[代码块省略]")
                }
                continue
            }
            if insideCode { continue }
            output.append(String(line))
        }
        return output.joined(separator: "\n")
    }

    private func parseChecklistLine(_ line: String) -> (title: String, isChecked: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") {
            return (String(trimmed.dropFirst(6)), false)
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return (String(trimmed.dropFirst(6)), true)
        }
        return nil
    }

    func completeTodo(_ item: LocalTodoItem) {
        if item.isWhiteboard {
            let updated = updateChecklistLine(in: whiteboard.content, lineIndex: item.lineIndex)
            whiteboard.content = updated
            whiteboard.contentRTF = RichTextCodec.encodeRTF(from: AttributedString(updated))
            whiteboard.updateMetrics()
            persistWhiteboard()
            updateDocumentTodoIfNeeded(noteId: whiteboard.id, lineIndex: item.lineIndex)
            return
        }

        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == item.notebookId }) else { return }
        guard let noteIndex = notebooks[notebookIndex].notes.firstIndex(where: { $0.id == item.noteId }) else { return }
        var note = notebooks[notebookIndex].notes[noteIndex]
        let updated = updateChecklistLine(in: note.content, lineIndex: item.lineIndex)
        note.content = updated
        note.updateMetrics()
        notebooks[notebookIndex].notes[noteIndex] = note
        updateDocumentTodoIfNeeded(noteId: note.id, lineIndex: item.lineIndex)
        applyLocalUpdate(note: note)
    }

    private func updateChecklistLine(in content: String, lineIndex: Int) -> String {
        var lines = content.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        guard lineIndex >= 0, lineIndex < lines.count else { return content }
        lines[lineIndex] = markChecklistComplete(lines[lineIndex])
        return lines.joined(separator: "\n")
    }

    private func markChecklistComplete(_ line: String) -> String {
        if let range = line.range(of: "- [ ] ") {
            return line.replacingCharacters(in: range, with: "- [x] ")
        }
        if let range = line.range(of: "- [X] ") {
            return line.replacingCharacters(in: range, with: "- [x] ")
        }
        return line
    }

    private func updateDocumentTodoIfNeeded(noteId: UUID, lineIndex: Int) {
        guard var document = documents[noteId] else { return }
        var currentLine = 0
        for idx in document.blocks.indices {
            let lines = document.blocks[idx].plainText.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            let count = lines.count
            if lineIndex >= currentLine && lineIndex < currentLine + count {
                if document.blocks[idx].kind == .todo {
                    document.blocks[idx].isChecked = true
                    documents[noteId] = document
                }
                return
            }
            currentLine += count
            if idx < document.blocks.count - 1 {
                currentLine += 1
            }
        }
    }

    private func applyLocalUpdate(note: Note) {
        var updatedNote = note
        updatedNote.updatedAt = Date()
        // Update in-memory immediately for UI.
        for notebookIndex in notebooks.indices {
            if let noteIndex = notebooks[notebookIndex].notes.firstIndex(where: { $0.id == updatedNote.id }) {
                notebooks[notebookIndex].notes[noteIndex] = updatedNote
                schedulePreviewItemsUpdate(notebook: notebooks[notebookIndex])
                break
            }
        }

        guard let ownerId, let modelContext else { return }
        let noteId = updatedNote.id

        // Write-through to SwiftData (debounced save).
        do {
            let predicate = #Predicate<LocalNote> { n in
                n.ownerId == ownerId && n.id == noteId
            }
            let fetch = FetchDescriptor<LocalNote>(predicate: predicate)
            if let local = try modelContext.fetch(fetch).first {
                local.title = updatedNote.title
                local.summary = updatedNote.summary
                local.paragraphCount = updatedNote.paragraphCount
                local.bulletCount = updatedNote.bulletCount
                local.hasAdditionalContext = updatedNote.hasAdditionalContext
                local.content = updatedNote.content
                local.contentRTF = updatedNote.contentRTF
                local.isPinned = updatedNote.isPinned
                local.isDirty = true
                local.remoteUpdatedAt = updatedNote.updatedAt
                scheduleSave()
            }
        } catch {
            // ignore
        }
    }

    private func upsertLocalNote(ownerId: UUID, notebookId: UUID, note: Note, context: ModelContext) {
        do {
            let noteId = note.id
            let nbPred = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.id == notebookId
            }
            let nbFetch = FetchDescriptor<LocalNotebook>(predicate: nbPred)
            guard let localNotebook = try context.fetch(nbFetch).first else { return }

            let notePred = #Predicate<LocalNote> { n in
                n.ownerId == ownerId && n.id == noteId
            }
            let noteFetch = FetchDescriptor<LocalNote>(predicate: notePred)
            if let existing = try context.fetch(noteFetch).first {
                existing.title = note.title
                existing.content = note.content
                existing.contentRTF = note.contentRTF
                existing.summary = note.summary
                existing.paragraphCount = note.paragraphCount
                existing.bulletCount = note.bulletCount
                existing.hasAdditionalContext = note.hasAdditionalContext
                existing.isPinned = note.isPinned
                existing.isDirty = true
                existing.notebook = localNotebook
                existing.remoteUpdatedAt = Date()
            } else {
                let local = LocalNote(
                    id: note.id,
                    ownerId: ownerId,
                    title: note.title,
                    summary: note.summary,
                    paragraphCount: note.paragraphCount,
                    bulletCount: note.bulletCount,
                    hasAdditionalContext: note.hasAdditionalContext,
                    createdAt: note.createdAt,
                    remoteUpdatedAt: Date(),
                    version: 1,
                    deletedAt: nil,
                    contentRTF: note.contentRTF,
                    content: note.content,
                    isPinned: note.isPinned,
                    isDirty: true,
                    conflictParentId: nil,
                    notebook: localNotebook
                )
                context.insert(local)
                // Note: SwiftData automatically manages inverse relationships
            }
            scheduleSave()
        } catch {
            // ignore
        }
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        guard let modelContext else { return }
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            try? modelContext.save()
        }
    }
}

private struct LinkBlocksPayload: Codable {
    let noteId: String
    let blocks: [LinkedNoteBlock]
}

private extension LocalNote {
    func asNote() -> Note {
        Note(
            id: id,
            title: title,
            summary: summary,
            paragraphCount: paragraphCount,
            bulletCount: bulletCount,
            hasAdditionalContext: hasAdditionalContext,
            createdAt: createdAt,
            updatedAt: remoteUpdatedAt,
            contentRTF: contentRTF,
            content: content,
            isPinned: isPinned
        )
    }
}

struct NotebookPreviewItem: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case image(Data)
        case block(block: Block, numberIndex: Int?)
    }

    static func image(_ data: Data) -> NotebookPreviewItem {
        NotebookPreviewItem(kind: .image(data))
    }

    static func block(block: Block, numberIndex: Int?) -> NotebookPreviewItem {
        NotebookPreviewItem(kind: .block(block: block, numberIndex: numberIndex))
    }
}
