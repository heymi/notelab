@preconcurrency import CloudKit
import Combine
import Foundation
import os
import SwiftData

protocol CloudSyncing: ObservableObject {
    var isSyncing: Bool { get }
    var lastSyncAt: Date? { get }
    var lastError: String? { get }
    func configure(ownerId: UUID, context: ModelContext)
    func resetForSignOut()
    func syncNow() async
}

final class SyncEngine: ObservableObject, CloudSyncing {
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?

    private var ownerId: UUID?
    private var modelContext: ModelContext?
    private let logger = Logger(subsystem: "NoteLab", category: "CloudKitSync")

    func configure(ownerId: UUID, context: ModelContext) {
        self.ownerId = ownerId
        self.modelContext = context
    }

    func resetForSignOut() {
        ownerId = nil
        modelContext = nil
        isSyncing = false
        lastSyncAt = nil
        lastError = nil
    }

    func syncNow() async {
        guard let ownerId, let modelContext else { return }

        let canSync = await MainActor.run { SubscriptionManager.shared.canUseSync() }
        if !canSync {
            await MainActor.run {
                self.lastError = "云同步为付费功能，请升级订阅"
                NotificationCenter.default.post(name: .showPaywall, object: PaywallTrigger.syncAttempt)
            }
            return
        }

        if await MainActor.run(resultType: Bool.self, body: { self.isSyncing }) { return }
        if Task.isCancelled { return }
        await MainActor.run { self.isSyncing = true }
        defer { Task { @MainActor in self.isSyncing = false } }

        do {
            let status = try await CloudKitSchema.container.accountStatus()
            guard status == .available else {
                await MainActor.run {
                    self.lastError = "当前设备未开启 iCloud，同步已暂停"
                }
                return
            }

            let syncStart = DispatchTime.now()
            try await CloudKitBridge.ensurePrivateZone()
            try await pushDirtyNotebooks(ownerId: ownerId, context: modelContext)
            try await pushDirtyNotes(ownerId: ownerId, context: modelContext)
            try await pushDirtyAttachments(ownerId: ownerId, context: modelContext)
            let nextChangeToken = try await pullRemoteChanges(ownerId: ownerId, context: modelContext)

            let didSave = try await MainActor.run(resultType: Bool.self) {
                if modelContext.hasChanges {
                    try modelContext.save()
                    return true
                }
                return false
            }
            if let nextChangeToken {
                Self.storeChangeToken(nextChangeToken, ownerId: ownerId)
            }
            print(didSave ? "SyncEngine: modelContext saved" : "SyncEngine: modelContext has no changes")
            await MainActor.run {
                self.lastSyncAt = Date()
                self.lastError = nil
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - syncStart.uptimeNanoseconds) / 1_000_000_000
            logger.debug("CloudKit sync finished in \(elapsed, privacy: .public)s")
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - Push

private extension SyncEngine {
    func pushDirtyNotebooks(ownerId: UUID, context: ModelContext) async throws {
        let dirty = try await MainActor.run(resultType: [LocalNotebook].self) {
            let pred = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.isDirty == true
            }
            return try context.fetch(FetchDescriptor<LocalNotebook>(predicate: pred))
        }

        for local in dirty {
            let snapshot = await MainActor.run { NotebookSnapshot(local) }
            let recordID = CloudKitSchema.recordID(type: CloudKitSchema.RecordType.notebook, id: snapshot.id)
            let record = try await CloudKitBridge.fetchRecord(recordID) ?? CKRecord(recordType: CloudKitSchema.RecordType.notebook, recordID: recordID)
            snapshot.apply(to: record, ownerId: ownerId)
            let saved = try await CloudKitBridge.save(record: record)

            await MainActor.run {
                local.remoteUpdatedAt = saved[date: CloudKitSchema.Field.updatedAt] ?? Date()
                local.isDirty = false
            }
        }
    }

    func pushDirtyNotes(ownerId: UUID, context: ModelContext) async throws {
        let dirty = try await MainActor.run(resultType: [LocalNote].self) {
            let pred = #Predicate<LocalNote> { note in
                note.ownerId == ownerId && note.isDirty == true
            }
            return try context.fetch(FetchDescriptor<LocalNote>(predicate: pred))
        }

        for local in dirty {
            guard let notebookId = await MainActor.run(resultType: UUID?.self, body: { local.notebook?.id }) else {
                continue
            }
            let snapshot = await MainActor.run { NoteSnapshot(local: local, notebookId: notebookId) }
            let recordID = CloudKitSchema.recordID(type: CloudKitSchema.RecordType.note, id: snapshot.id)
            let existing = try await CloudKitBridge.fetchRecord(recordID)

            if let existing, existing[int: CloudKitSchema.Field.version] > snapshot.version {
                try await resolveConflict(local: local, serverRecord: existing, snapshot: snapshot, context: context)
                continue
            }

            let record = existing ?? CKRecord(recordType: CloudKitSchema.RecordType.note, recordID: recordID)
            snapshot.apply(to: record, ownerId: ownerId, nextVersion: existing == nil ? snapshot.version : snapshot.version + 1)
            let saved = try await CloudKitBridge.save(record: record)

            await MainActor.run {
                local.remoteUpdatedAt = saved[date: CloudKitSchema.Field.updatedAt] ?? Date()
                local.version = saved[int: CloudKitSchema.Field.version]
                local.isDirty = false
            }
        }
    }

    func pushDirtyAttachments(ownerId: UUID, context: ModelContext) async throws {
        try await AttachmentStorage.shared.uploadPendingAttachments(context: context, ownerId: ownerId)

        let dirtyUploaded = try await MainActor.run(resultType: [LocalAttachment].self) {
            let pred = #Predicate<LocalAttachment> { att in
                att.ownerId == ownerId && att.isDirty == true && att.isUploaded == true
            }
            return try context.fetch(FetchDescriptor<LocalAttachment>(predicate: pred))
        }

        for local in dirtyUploaded {
            let snapshot = await MainActor.run { AttachmentSnapshot(local) }
            let recordID = CloudKitSchema.recordID(type: CloudKitSchema.RecordType.attachment, id: snapshot.id)
            let record = try await CloudKitBridge.fetchRecord(recordID) ?? CKRecord(recordType: CloudKitSchema.RecordType.attachment, recordID: recordID)
            snapshot.apply(to: record, ownerId: ownerId)
            let saved = try await CloudKitBridge.save(record: record)

            await MainActor.run {
                local.remoteUpdatedAt = saved[date: CloudKitSchema.Field.updatedAt] ?? Date()
                local.isDirty = false
            }
        }
    }
}

// MARK: - Pull

private extension SyncEngine {
    func pullRemoteChanges(ownerId: UUID, context: ModelContext) async throws -> CKServerChangeToken? {
        let previousToken = Self.loadChangeToken(ownerId: ownerId)
        let changes = try await CloudKitBridge.zoneChanges(since: previousToken)
        guard changes.changedRecords.isEmpty == false || changes.deletedRecordIDs.isEmpty == false else {
            return changes.serverChangeToken
        }

        let notebooks = changes.changedRecords.filter { $0.recordType == CloudKitSchema.RecordType.notebook }
        let notes = changes.changedRecords.filter { $0.recordType == CloudKitSchema.RecordType.note }
        let attachments = changes.changedRecords.filter { $0.recordType == CloudKitSchema.RecordType.attachment }

        let skippedAttachments = try await MainActor.run(resultType: Bool.self) {
            for record in notebooks {
                upsertLocalNotebook(from: record, ownerId: ownerId, context: context)
            }
            for record in notes {
                upsertLocalNote(from: record, ownerId: ownerId, context: context)
            }

            var skipped = false
            for record in attachments {
                if !upsertLocalAttachment(from: record, ownerId: ownerId, context: context) {
                    skipped = true
                }
            }

            applyHardDeletedRecords(changes.deletedRecordIDs, ownerId: ownerId, context: context)
            return skipped
        }

        if skippedAttachments {
            logger.debug("pullRemoteChanges skipped attachment rows due to missing parent note; change token not advanced")
            return nil
        }

        return changes.serverChangeToken
    }

    func pullNotebooks(ownerId: UUID, context: ModelContext) async throws {
        let watermark = try await MainActor.run { try getWatermark(entity: "notebooks", ownerId: ownerId, context: context) }
        let records = try await CloudKitBridge.records(type: CloudKitSchema.RecordType.notebook, updatedAfter: watermark)
        guard !records.isEmpty else { return }

        try await MainActor.run {
            for record in records {
                upsertLocalNotebook(from: record, ownerId: ownerId, context: context)
            }
            if let maxUpdatedAt = records.compactMap({ $0[date: CloudKitSchema.Field.updatedAt] }).max() {
                try setWatermark(entity: "notebooks", ownerId: ownerId, context: context, date: maxUpdatedAt)
            }
        }
    }

    func pullNotes(ownerId: UUID, context: ModelContext) async throws {
        let watermark = try await MainActor.run { try getWatermark(entity: "notes", ownerId: ownerId, context: context) }
        let records = try await CloudKitBridge.records(type: CloudKitSchema.RecordType.note, updatedAfter: watermark)
        guard !records.isEmpty else { return }

        try await MainActor.run {
            for record in records {
                upsertLocalNote(from: record, ownerId: ownerId, context: context)
            }
            if let maxUpdatedAt = records.compactMap({ $0[date: CloudKitSchema.Field.updatedAt] }).max() {
                try setWatermark(entity: "notes", ownerId: ownerId, context: context, date: maxUpdatedAt)
            }
        }
    }

    func pullAttachments(ownerId: UUID, context: ModelContext) async throws {
        let watermark = try await MainActor.run { try getWatermark(entity: "attachments", ownerId: ownerId, context: context) }
        let records = try await CloudKitBridge.records(type: CloudKitSchema.RecordType.attachment, updatedAfter: watermark)
        guard !records.isEmpty else { return }

        let skipped = try await MainActor.run(resultType: Bool.self) {
            var skipped = false
            for record in records {
                if !upsertLocalAttachment(from: record, ownerId: ownerId, context: context) {
                    skipped = true
                }
            }
            if !skipped, let maxUpdatedAt = records.compactMap({ $0[date: CloudKitSchema.Field.updatedAt] }).max() {
                try setWatermark(entity: "attachments", ownerId: ownerId, context: context, date: maxUpdatedAt)
            }
            return skipped
        }

        if skipped {
            logger.debug("pullAttachments skipped rows due to missing parent note; watermark not advanced")
        }
    }
}

// MARK: - Local upserts

private extension SyncEngine {
    func applyHardDeletedRecords(_ recordIDs: [CKRecord.ID], ownerId: UUID, context: ModelContext) {
        let now = Date()
        for recordID in recordIDs {
            if let id = Self.localId(from: recordID.recordName, type: CloudKitSchema.RecordType.notebook) {
                let pred = #Predicate<LocalNotebook> { nb in
                    nb.ownerId == ownerId && nb.id == id
                }
                if let notebook = try? context.fetch(FetchDescriptor<LocalNotebook>(predicate: pred)).first, notebook.isDirty == false {
                    notebook.deletedAt = notebook.deletedAt ?? now
                }
            } else if let id = Self.localId(from: recordID.recordName, type: CloudKitSchema.RecordType.note) {
                let pred = #Predicate<LocalNote> { note in
                    note.ownerId == ownerId && note.id == id
                }
                if let note = try? context.fetch(FetchDescriptor<LocalNote>(predicate: pred)).first, note.isDirty == false {
                    note.deletedAt = note.deletedAt ?? now
                }
            } else if let id = Self.localId(from: recordID.recordName, type: CloudKitSchema.RecordType.attachment) {
                let pred = #Predicate<LocalAttachment> { att in
                    att.ownerId == ownerId && att.id == id
                }
                if let attachment = try? context.fetch(FetchDescriptor<LocalAttachment>(predicate: pred)).first, attachment.isDirty == false {
                    attachment.deletedAt = attachment.deletedAt ?? now
                }
            }
        }
    }

    func upsertLocalNotebook(from record: CKRecord, ownerId: UUID, context: ModelContext) {
        guard let id = UUID(uuidString: record[string: CloudKitSchema.Field.id] ?? "") else { return }
        let pred = #Predicate<LocalNotebook> { nb in
            nb.ownerId == ownerId && nb.id == id
        }

        do {
            let fetch = FetchDescriptor<LocalNotebook>(predicate: pred)
            if let existing = try context.fetch(fetch).first {
                if existing.isDirty { return }
                existing.title = record[string: CloudKitSchema.Field.title] ?? "未命名笔记本"
                existing.colorRaw = record[string: CloudKitSchema.Field.color] ?? NotebookColor.lime.rawValue
                existing.iconName = record[string: CloudKitSchema.Field.iconName] ?? "book"
                existing.isPinned = record[bool: CloudKitSchema.Field.isPinned]
                existing.notebookDescription = record[string: CloudKitSchema.Field.notebookDescription] ?? ""
                existing.deletedAt = record[date: CloudKitSchema.Field.deletedAt]
                existing.remoteUpdatedAt = record[date: CloudKitSchema.Field.updatedAt] ?? existing.remoteUpdatedAt
                return
            }

            let createdAt = record[date: CloudKitSchema.Field.createdAt] ?? Date()
            let updatedAt = record[date: CloudKitSchema.Field.updatedAt] ?? createdAt
            context.insert(LocalNotebook(
                id: id,
                ownerId: ownerId,
                title: record[string: CloudKitSchema.Field.title] ?? "未命名笔记本",
                colorRaw: record[string: CloudKitSchema.Field.color] ?? NotebookColor.lime.rawValue,
                iconName: record[string: CloudKitSchema.Field.iconName] ?? "book",
                createdAt: createdAt,
                remoteUpdatedAt: updatedAt,
                deletedAt: record[date: CloudKitSchema.Field.deletedAt],
                isDirty: false,
                isPinned: record[bool: CloudKitSchema.Field.isPinned],
                notebookDescription: record[string: CloudKitSchema.Field.notebookDescription] ?? "",
                notes: []
            ))
        } catch {
            print("SyncEngine: failed to upsert notebook \(id): \(error)")
        }
    }

    func upsertLocalNote(from record: CKRecord, ownerId: UUID, context: ModelContext) {
        guard let id = UUID(uuidString: record[string: CloudKitSchema.Field.id] ?? ""),
              let notebookId = UUID(uuidString: record[string: CloudKitSchema.Field.notebookId] ?? "") else {
            return
        }

        do {
            let nbPred = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.id == notebookId
            }
            let notebook = try context.fetch(FetchDescriptor<LocalNotebook>(predicate: nbPred)).first

            let notePred = #Predicate<LocalNote> { note in
                note.ownerId == ownerId && note.id == id
            }
            if let existing = try context.fetch(FetchDescriptor<LocalNote>(predicate: notePred)).first {
                if existing.isDirty { return }
                apply(record: record, to: existing, notebook: notebook)
                return
            }

            let createdAt = record[date: CloudKitSchema.Field.createdAt] ?? Date()
            let updatedAt = record[date: CloudKitSchema.Field.updatedAt] ?? createdAt
            context.insert(LocalNote(
                id: id,
                ownerId: ownerId,
                title: record[string: CloudKitSchema.Field.title] ?? "未命名笔记",
                summary: record[string: CloudKitSchema.Field.summary] ?? "",
                paragraphCount: record[int: CloudKitSchema.Field.paragraphCount],
                bulletCount: record[int: CloudKitSchema.Field.bulletCount],
                hasAdditionalContext: record[bool: CloudKitSchema.Field.hasAdditionalContext],
                createdAt: createdAt,
                remoteUpdatedAt: updatedAt,
                version: max(record[int: CloudKitSchema.Field.version], 1),
                deletedAt: record[date: CloudKitSchema.Field.deletedAt],
                contentRTF: record[data: CloudKitSchema.Field.contentRTF],
                content: record[string: CloudKitSchema.Field.content] ?? "",
                isPinned: record[bool: CloudKitSchema.Field.isPinned],
                isDirty: false,
                conflictParentId: nil,
                notebook: notebook
            ))
        } catch {
            print("SyncEngine: failed to upsert note \(id): \(error)")
        }
    }

    func upsertLocalAttachment(from record: CKRecord, ownerId: UUID, context: ModelContext) -> Bool {
        guard let id = UUID(uuidString: record[string: CloudKitSchema.Field.id] ?? ""),
              let noteId = UUID(uuidString: record[string: CloudKitSchema.Field.noteId] ?? "") else {
            return false
        }

        let notePred = #Predicate<LocalNote> { note in
            note.ownerId == ownerId && note.id == noteId
        }
        guard (try? context.fetch(FetchDescriptor<LocalNote>(predicate: notePred)).first) != nil else {
            return false
        }

        let pred = #Predicate<LocalAttachment> { att in
            att.ownerId == ownerId && att.id == id
        }
        do {
            if let existing = try context.fetch(FetchDescriptor<LocalAttachment>(predicate: pred)).first {
                if existing.isDirty { return false }
                existing.noteId = noteId
                existing.storagePath = record[string: CloudKitSchema.Field.storagePath] ?? existing.storagePath
                existing.fileName = record[string: CloudKitSchema.Field.fileName] ?? existing.fileName
                existing.mimeType = record[string: CloudKitSchema.Field.mimeType] ?? existing.mimeType
                existing.fileSize = record[int64: CloudKitSchema.Field.fileSize]
                existing.deletedAt = record[date: CloudKitSchema.Field.deletedAt]
                existing.remoteUpdatedAt = record[date: CloudKitSchema.Field.updatedAt] ?? existing.remoteUpdatedAt
                existing.isUploaded = true
                return true
            }

            let fileName = record[string: CloudKitSchema.Field.fileName] ?? "attachment"
            let createdAt = record[date: CloudKitSchema.Field.createdAt] ?? Date()
            let updatedAt = record[date: CloudKitSchema.Field.updatedAt] ?? createdAt
            context.insert(LocalAttachment(
                id: id,
                ownerId: ownerId,
                noteId: noteId,
                storagePath: record[string: CloudKitSchema.Field.storagePath] ?? CloudKitSchema.storagePath(ownerId: ownerId, attachmentId: id, fileName: fileName),
                fileName: fileName,
                mimeType: record[string: CloudKitSchema.Field.mimeType] ?? "application/octet-stream",
                fileSize: record[int64: CloudKitSchema.Field.fileSize],
                createdAt: createdAt,
                remoteUpdatedAt: updatedAt,
                deletedAt: record[date: CloudKitSchema.Field.deletedAt],
                localCachePath: nil,
                isDirty: false,
                isUploaded: true
            ))
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Conflict handling

private extension SyncEngine {
    func resolveConflict(local: LocalNote, serverRecord: CKRecord, snapshot: NoteSnapshot, context: ModelContext) async throws {
        try await MainActor.run {
            apply(record: serverRecord, to: local, notebook: local.notebook)
            local.isDirty = false

            let conflictNote = LocalNote(
                id: UUID(),
                ownerId: snapshot.ownerId,
                title: snapshot.title + " (冲突副本 \(Date().formatted(date: .abbreviated, time: .shortened)))",
                summary: snapshot.summary,
                paragraphCount: snapshot.paragraphCount,
                bulletCount: snapshot.bulletCount,
                hasAdditionalContext: snapshot.hasAdditionalContext,
                createdAt: Date(),
                remoteUpdatedAt: Date(),
                version: 1,
                deletedAt: snapshot.deletedAt,
                contentRTF: snapshot.contentRTF,
                content: snapshot.content,
                isPinned: snapshot.isPinned,
                isDirty: true,
                conflictParentId: snapshot.id,
                notebook: local.notebook
            )
            context.insert(conflictNote)
        }
    }

    func apply(record: CKRecord, to note: LocalNote, notebook: LocalNotebook?) {
        note.title = record[string: CloudKitSchema.Field.title] ?? "未命名笔记"
        note.summary = record[string: CloudKitSchema.Field.summary] ?? ""
        note.content = record[string: CloudKitSchema.Field.content] ?? ""
        note.contentRTF = record[data: CloudKitSchema.Field.contentRTF]
        note.paragraphCount = record[int: CloudKitSchema.Field.paragraphCount]
        note.bulletCount = record[int: CloudKitSchema.Field.bulletCount]
        note.hasAdditionalContext = record[bool: CloudKitSchema.Field.hasAdditionalContext]
        note.isPinned = record[bool: CloudKitSchema.Field.isPinned]
        note.deletedAt = record[date: CloudKitSchema.Field.deletedAt]
        note.remoteUpdatedAt = record[date: CloudKitSchema.Field.updatedAt] ?? note.remoteUpdatedAt
        note.version = max(record[int: CloudKitSchema.Field.version], 1)
        note.notebook = notebook
    }
}

// MARK: - Watermarks

private extension SyncEngine {
    static func changeTokenKey(ownerId: UUID) -> String {
        "NoteLab.CloudKit.\(CloudKitSchema.zoneName).changeToken.\(ownerId.uuidString)"
    }

    static func loadChangeToken(ownerId: UUID) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey(ownerId: ownerId)) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    static func storeChangeToken(_ token: CKServerChangeToken, ownerId: UUID) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            return
        }
        UserDefaults.standard.set(data, forKey: changeTokenKey(ownerId: ownerId))
    }

    static func localId(from recordName: String, type: String) -> UUID? {
        let prefix = "\(type)-"
        guard recordName.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(recordName.dropFirst(prefix.count)))
    }

    func getWatermark(entity: String, ownerId: UUID, context: ModelContext) throws -> Date? {
        let key = "\(ownerId.uuidString):\(entity)"
        let pred = #Predicate<SyncMetadata> { meta in
            meta.key == key
        }
        return try context.fetch(FetchDescriptor<SyncMetadata>(predicate: pred)).first?.lastPulledAt
    }

    func setWatermark(entity: String, ownerId: UUID, context: ModelContext, date: Date) throws {
        let key = "\(ownerId.uuidString):\(entity)"
        let pred = #Predicate<SyncMetadata> { meta in
            meta.key == key
        }
        if let existing = try context.fetch(FetchDescriptor<SyncMetadata>(predicate: pred)).first {
            existing.lastPulledAt = date
        } else {
            context.insert(SyncMetadata(ownerId: ownerId, entity: entity, lastPulledAt: date))
        }
    }
}

// MARK: - Snapshots

private struct NotebookSnapshot {
    let id: UUID
    let title: String
    let colorRaw: String
    let iconName: String
    let createdAt: Date
    let deletedAt: Date?
    let isPinned: Bool
    let notebookDescription: String

    init(_ local: LocalNotebook) {
        id = local.id
        title = local.title
        colorRaw = local.colorRaw
        iconName = local.iconName
        createdAt = local.createdAt
        deletedAt = local.deletedAt
        isPinned = local.isPinned
        notebookDescription = local.notebookDescription
    }

    func apply(to record: CKRecord, ownerId: UUID) {
        let now = Date()
        record[string: CloudKitSchema.Field.id] = id.uuidString
        record[string: CloudKitSchema.Field.ownerId] = ownerId.uuidString
        record[string: CloudKitSchema.Field.title] = title
        record[string: CloudKitSchema.Field.color] = colorRaw
        record[string: CloudKitSchema.Field.iconName] = iconName
        record[string: CloudKitSchema.Field.notebookDescription] = notebookDescription
        record[bool: CloudKitSchema.Field.isPinned] = isPinned
        record[date: CloudKitSchema.Field.createdAt] = record[date: CloudKitSchema.Field.createdAt] ?? createdAt
        record[date: CloudKitSchema.Field.updatedAt] = now
        record[date: CloudKitSchema.Field.deletedAt] = deletedAt
    }
}

private struct NoteSnapshot {
    let id: UUID
    let ownerId: UUID
    let notebookId: UUID
    let title: String
    let summary: String
    let paragraphCount: Int
    let bulletCount: Int
    let hasAdditionalContext: Bool
    let createdAt: Date
    let version: Int
    let deletedAt: Date?
    let contentRTF: Data?
    let content: String
    let isPinned: Bool

    init(local: LocalNote, notebookId: UUID) {
        id = local.id
        ownerId = local.ownerId
        self.notebookId = notebookId
        title = local.title
        summary = local.summary
        paragraphCount = local.paragraphCount
        bulletCount = local.bulletCount
        hasAdditionalContext = local.hasAdditionalContext
        createdAt = local.createdAt
        version = local.version
        deletedAt = local.deletedAt
        contentRTF = local.contentRTF
        content = local.content
        isPinned = local.isPinned
    }

    func apply(to record: CKRecord, ownerId: UUID, nextVersion: Int) {
        let now = Date()
        record[string: CloudKitSchema.Field.id] = id.uuidString
        record[string: CloudKitSchema.Field.ownerId] = ownerId.uuidString
        record[string: CloudKitSchema.Field.notebookId] = notebookId.uuidString
        record[string: CloudKitSchema.Field.title] = title
        record[string: CloudKitSchema.Field.summary] = summary
        record[string: CloudKitSchema.Field.content] = content
        record[data: CloudKitSchema.Field.contentRTF] = contentRTF
        record[int: CloudKitSchema.Field.paragraphCount] = paragraphCount
        record[int: CloudKitSchema.Field.bulletCount] = bulletCount
        record[bool: CloudKitSchema.Field.hasAdditionalContext] = hasAdditionalContext
        record[bool: CloudKitSchema.Field.isPinned] = isPinned
        record[int: CloudKitSchema.Field.version] = max(nextVersion, 1)
        record[date: CloudKitSchema.Field.createdAt] = record[date: CloudKitSchema.Field.createdAt] ?? createdAt
        record[date: CloudKitSchema.Field.updatedAt] = now
        record[date: CloudKitSchema.Field.deletedAt] = deletedAt
    }
}

private struct AttachmentSnapshot {
    let id: UUID
    let noteId: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let createdAt: Date
    let deletedAt: Date?

    init(_ local: LocalAttachment) {
        id = local.id
        noteId = local.noteId
        storagePath = local.storagePath
        fileName = local.fileName
        mimeType = local.mimeType
        fileSize = local.fileSize
        createdAt = local.createdAt
        deletedAt = local.deletedAt
    }

    func apply(to record: CKRecord, ownerId: UUID) {
        let now = Date()
        record[string: CloudKitSchema.Field.id] = id.uuidString
        record[string: CloudKitSchema.Field.ownerId] = ownerId.uuidString
        record[string: CloudKitSchema.Field.noteId] = noteId.uuidString
        record[string: CloudKitSchema.Field.storagePath] = storagePath
        record[string: CloudKitSchema.Field.fileName] = fileName
        record[string: CloudKitSchema.Field.mimeType] = mimeType
        record[int64: CloudKitSchema.Field.fileSize] = fileSize
        record[date: CloudKitSchema.Field.createdAt] = record[date: CloudKitSchema.Field.createdAt] ?? createdAt
        record[date: CloudKitSchema.Field.updatedAt] = now
        record[date: CloudKitSchema.Field.deletedAt] = deletedAt
    }
}
