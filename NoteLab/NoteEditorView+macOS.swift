import SwiftUI
import Combine
import SwiftData
import Foundation
import os
import UniformTypeIdentifiers

#if os(macOS)
import AppKit

struct NoteEditorView: View {
    @Binding var note: Note
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthManager
    
    var isWhiteboard: Bool = false
    var onClose: (() -> Void)? = nil
    
    // State
    @State private var document: NoteDocument = NoteDocument.fromPlainText("")
    @State private var selectedText: String = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var selectedBlockIds: [UUID] = []
    @State private var pendingCommand: EditorCommandRequest?
    @State private var exitMultiSelectToken: UUID = UUID()
    @StateObject private var titleFocusBridge = TitleFocusBridge()
    
    // AI State
    @State private var showAIAction = false
    @State private var showAISheet = false
    @State private var aiMode: AIMode?
    @State private var aiLoading = false
    @State private var formattedMarkdown: String = ""
    @State private var extractedTasks: [AITaskSuggestion] = []
    @State private var aiError: String?
    @State private var aiAttachmentTokens: [AttachmentToken] = []
    
    // Send State
    @State private var showSendSheet = false
    @State private var sendDraftText: String = ""
    @State private var sendDraftBlockIds: [UUID] = []
    @State private var showSelectionAlert = false
    
    // More actions
    @State private var showMoreMenu = false
    @State private var showMoveSheet = false
    @State private var showFormatMenu = false
    
    // Undo
    @State private var undoSnapshot: NoteUndoSnapshot?
    
    // Whiteboard
    @State private var showWhiteboardLinks = false
    @State private var showClearWhiteboardConfirm = false
    
    var body: some View {
        editorContent
            .background(Theme.background)
            .toolbar { toolbarContent }
            .onAppear { loadDocumentIfNeeded() }
            .onChange(of: note.id) { _, _ in loadDocumentIfNeeded() }
            .confirmationDialog("询问 AI", isPresented: $showAIAction) {
                Button("整理笔记") { runFormat() }
                Button("提取待办") { runExtractTasks() }
                if hasUndoSnapshot { Button("撤销上次替换") { restoreUndoSnapshot() } }
                Button("发送选中内容") { triggerSend() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showAISheet) { aiResultSheet }
            .sheet(isPresented: $showSendSheet) { sendSheet }
            .sheet(isPresented: $showMoveSheet) { moveSheet }
            .sheet(isPresented: $showFormatMenu) { formatMenuSheet }
            .alert("请先选中内容", isPresented: $showSelectionAlert) {
                Button("知道了", role: .cancel) {}
            }
            .confirmationDialog("清空白板内容", isPresented: $showClearWhiteboardConfirm) {
                Button("清空", role: .destructive) { clearWhiteboard() }
                Button("取消", role: .cancel) {}
            }
            // Keyboard shortcuts (using hidden buttons)
            .background {
                Group {
                    Button("") { pendingCommand = EditorCommandRequest(command: .bold) }
                        .keyboardShortcut("b", modifiers: .command)
                    Button("") { pendingCommand = EditorCommandRequest(command: .italic) }
                        .keyboardShortcut("i", modifiers: .command)
                    Button("") { pendingCommand = EditorCommandRequest(command: .inlineCode) }
                        .keyboardShortcut("e", modifiers: .command)
                    Button("") { showFormatMenu = true }
                        .keyboardShortcut("/", modifiers: .command)
                    Button("") { showAIAction = true }
                        .keyboardShortcut("j", modifiers: .command)
                    Button("") { pendingCommand = EditorCommandRequest(command: .requestAttachment) }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                }
                .opacity(0)
            }
    }
    
    // MARK: - Editor Content
    
    @ViewBuilder
    private var editorContent: some View {
        BlockEditorRepresentableMac(
            document: $document,
            selectedText: $selectedText,
            selectedRange: $selectedRange,
            selectedBlockIds: $selectedBlockIds,
            pendingCommand: $pendingCommand,
            exitMultiSelectToken: $exitMultiSelectToken,
            title: $note.title,
            titleFocusBridge: titleFocusBridge,
            linkBlocks: store.linkBlocks(for: note.id),
            sentHighlightBlockIds: sentHighlightBlockIds,
            isWhiteboard: isWhiteboard,
            onOpenNote: { noteId in
                router.path.append(AppRoute.note(noteId))
            },
            onDocumentChange: { newDoc in
                document = newDoc
                note.content = newDoc.flattenMarkdown()
                note.updateMetrics()
                store.updateDocument(noteId: note.id, document: newDoc)
            },
            modelContext: modelContext,
            ownerId: auth.userId,
            noteId: note.id
        )
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Format menu
            Button {
                showFormatMenu = true
            } label: {
                Image(systemName: "textformat")
            }
            .help("格式化")
            
            // Attachment
            Button {
                pendingCommand = EditorCommandRequest(command: .requestAttachment)
            } label: {
                Image(systemName: "paperclip")
            }
            .help("插入附件")
            
            // AI actions
            Button {
                showAIAction = true
            } label: {
                Image(systemName: "sparkles")
            }
            .help("AI 功能")
            
            // More menu
            Menu {
                if canMoveNote {
                    Button("移动笔记") { showMoveSheet = true }
                }
                Button("分享") { shareContent() }
                Button("导出 PDF") { exportPDF() }
                Divider()
                if isWhiteboard {
                    Button("清空白板", role: .destructive) { showClearWhiteboardConfirm = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("更多操作")
        }
    }
    
    // MARK: - Sheets
    
    @ViewBuilder
    private var aiResultSheet: some View {
        VStack(spacing: 16) {
            Text(aiMode == .format ? "整理结果" : "提取的待办")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            
            if aiLoading {
                ProgressView()
                    .padding()
            } else if let error = aiError {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
            } else if aiMode == .format {
                ScrollView {
                    Text(formattedMarkdown)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 300)
                
                HStack(spacing: 12) {
                    Button("取消") { showAISheet = false }
                    Button("应用") {
                        saveUndoSnapshot()
                    let restored = AttachmentPreserver.restoreAndEnsure(markdown: formattedMarkdown, tokens: aiAttachmentTokens)
                    document = NoteDocument.fromMarkdown(restored)
                    note.content = restored
                        note.updateMetrics()
                        store.updateDocument(noteId: note.id, document: document)
                        showAISheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(extractedTasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.text)
                            .font(.system(size: 14, weight: .medium))
                        if let dueDate = task.normalizedDueDate {
                            Text("截止: \(dueDate)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 300)
                
                Button("关闭") { showAISheet = false }
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
    
    @ViewBuilder
    private var sendSheet: some View {
        SendSelectionSheetMac(
            selectedText: sendDraftText,
            onSend: { notebookId, title in
                if let newId = store.addNote(to: notebookId, title: title, content: sendDraftText) {
                    insertLinkBlock(noteId: newId, notebookId: notebookId, title: title)
                }
                sendDraftText = ""
            }
        )
    }
    
    @ViewBuilder
    private var moveSheet: some View {
        MoveNoteSheetMac(
            notebooks: store.notebooks,
            currentNotebookId: currentNotebookId,
            onMove: { targetId in
                store.moveNote(noteId: note.id, to: targetId)
            }
        )
    }
    
    @ViewBuilder
    private var formatMenuSheet: some View {
        FormatMenuSheetMac(onSelect: { command in
            if let cmd = command {
                pendingCommand = EditorCommandRequest(command: cmd)
            }
            showFormatMenu = false
        })
    }
    
    // MARK: - Helper Properties
    
    private var hasUndoSnapshot: Bool {
        undoSnapshot != nil
    }
    
    private var canMoveNote: Bool {
        !isWhiteboard && store.notebooks.count > 1
    }
    
    private var currentNotebookId: UUID? {
        store.notebookId(for: note.id)
    }
    
    private var sentHighlightBlockIds: Set<UUID> {
        Set(store.linkBlocks(for: note.id).compactMap { $0.sourceBlockIds }.flatMap { $0 })
    }
    
    // MARK: - Actions
    
    private func loadDocumentIfNeeded() {
        let currentDoc = store.document(for: note.id, fallbackText: note.content)
        if document != currentDoc {
            document = currentDoc
        }
    }
    
    private func triggerSend() {
        if selectedText.isEmpty {
            // Use full content if nothing selected
            sendDraftText = note.content
            sendDraftBlockIds = document.blocks.map { $0.id }
        } else {
            sendDraftText = selectedText
            sendDraftBlockIds = selectedBlockIds
        }
        
        if sendDraftText.isEmpty {
            showSelectionAlert = true
            return
        }
        showSendSheet = true
    }
    
    private func runFormat() {
        aiMode = .format
        aiLoading = true
        aiError = nil
        showAISheet = true
        
        Task {
            do {
                let tokens = AttachmentPreserver.extractTokens(from: document)
                aiAttachmentTokens = tokens
                let tokenizedContent = AttachmentPreserver.tokenize(content: note.content, tokens: tokens)
                let notebookContext = currentNotebookId.flatMap { id in
                    store.notebooks.first(where: { $0.id == id })?.notebookDescription
                }
                let payload = try await aiClient.noteInsight(text: tokenizedContent, title: note.title, notebookContext: notebookContext, protectedAttachmentTokens: tokens.map { $0.token })
                formattedMarkdown = AttachmentPreserver.restoreAndEnsure(markdown: payload.formattedMarkdown, tokens: tokens)
                aiLoading = false
            } catch {
                aiError = error.localizedDescription
                aiLoading = false
            }
        }
    }
    
    private func runExtractTasks() {
        aiMode = .tasks
        aiLoading = true
        aiError = nil
        showAISheet = true
        
        Task {
            do {
                let tasks = try await aiClient.extractTasks(text: note.content)
                extractedTasks = tasks
                aiLoading = false
            } catch {
                aiError = error.localizedDescription
                aiLoading = false
            }
        }
    }
    
    private func saveUndoSnapshot() {
        undoSnapshot = NoteUndoSnapshot(title: note.title, content: note.content, createdAt: Date())
    }
    
    private func restoreUndoSnapshot() {
        guard let snapshot = undoSnapshot else { return }
        note.title = snapshot.title ?? note.title
        note.content = snapshot.content
        document = NoteDocument.fromMarkdown(snapshot.content)
        store.updateDocument(noteId: note.id, document: document)
        undoSnapshot = nil
    }
    
    private func insertLinkBlock(noteId: UUID, notebookId: UUID, title: String) {
        let block = LinkedNoteBlock(
            id: UUID(),
            noteId: noteId,
            notebookId: notebookId,
            title: title,
            sourceRangeLocation: selectedRange.location,
            sourceRangeLength: selectedRange.length,
            sourceBlockIds: sendDraftBlockIds
        )
        store.addLinkBlock(block, to: note.id)
    }
    
    private func clearWhiteboard() {
        note.content = ""
        note.title = ""
        document = NoteDocument.fromPlainText("")
        store.updateDocument(noteId: note.id, document: document)
    }
    
    // MARK: - Share
    
    private func shareContent() {
        let content = note.content
        guard !content.isEmpty else { return }
        
        let picker = NSSharingServicePicker(items: [content])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
    
    // MARK: - PDF Export
    
    private func exportPDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(note.title.isEmpty ? "笔记" : note.title).pdf"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            generatePDF(to: url)
        }
    }
    
    private func generatePDF(to url: URL) {
        let markdown = note.content
        let pageSize = CGSize(width: 595, height: 842) // A4
        let margin: CGFloat = 50
        
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return }
        
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
        
        // Parse markdown to attributed string
        let font = NSFont.systemFont(ofSize: 14)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: markdown, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        var currentRange = CFRange(location: 0, length: 0)
        let textLength = attributedString.length
        
        while currentRange.location < textLength {
            context.beginPage(mediaBox: &mediaBox)
            
            let textRect = CGRect(
                x: margin,
                y: margin,
                width: pageSize.width - 2 * margin,
                height: pageSize.height - 2 * margin
            )
            
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            
            CTFrameDraw(frame, context)
            
            context.endPage()
            
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange.location += visibleRange.length
            
            if visibleRange.length == 0 { break }
        }
        
        context.closePDF()
        
        do {
            try pdfData.write(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            print("Failed to save PDF: \(error)")
        }
    }
}

// MARK: - AI Mode

private enum AIMode {
    case format
    case tasks
}

// MARK: - Undo Snapshot

private struct NoteUndoSnapshot {
    let title: String?
    let content: String
    let createdAt: Date
}

// MARK: - Send Selection Sheet

private struct SendSelectionSheetMac: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    
    let selectedText: String
    let onSend: (UUID, String) -> Void
    
    @State private var selectedNotebookId: UUID?
    @State private var title: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("发送到笔记本")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            
            TextField("笔记标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
            
            List(store.notebooks, selection: $selectedNotebookId) { notebook in
                HStack {
                    Image(systemName: notebook.iconName)
                        .foregroundStyle(Color.notebook(notebook.color))
                    Text(notebook.title)
                }
            }
            .frame(minHeight: 200)
            
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("发送") {
                    guard let notebookId = selectedNotebookId else { return }
                    let finalTitle = title.isEmpty ? defaultTitle(from: selectedText) : title
                    dismiss()
                    DispatchQueue.main.async {
                        onSend(notebookId, finalTitle)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedNotebookId == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.top, 16)
        .frame(minWidth: 400)
        .onAppear {
            if title.isEmpty {
                title = defaultTitle(from: selectedText)
            }
        }
    }
    
    private func defaultTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "新笔记" }
        return String(trimmed.prefix(20))
    }
}

// MARK: - Move Note Sheet

private struct MoveNoteSheetMac: View {
    @Environment(\.dismiss) private var dismiss
    
    let notebooks: [Notebook]
    let currentNotebookId: UUID?
    let onMove: (UUID) -> Void
    
    @State private var selectedNotebookId: UUID?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("移动笔记")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            
            List(notebooks.filter { $0.id != currentNotebookId }, selection: $selectedNotebookId) { notebook in
                HStack {
                    Image(systemName: notebook.iconName)
                        .foregroundStyle(Color.notebook(notebook.color))
                    Text(notebook.title)
                }
            }
            .frame(minHeight: 200)
            
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("移动") {
                    guard let notebookId = selectedNotebookId else { return }
                    dismiss()
                    DispatchQueue.main.async {
                        onMove(notebookId)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedNotebookId == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.top, 16)
        .frame(minWidth: 400)
    }
}

// MARK: - Format Menu Sheet

private struct FormatMenuSheetMac: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (EditorCommand?) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Text("格式化")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 12)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                FormatButton(title: "正文", icon: "text.alignleft") {
                    onSelect(.paragraph)
                }
                FormatButton(title: "标题1", icon: "textformat.size.larger") {
                    onSelect(.heading(level: 1))
                }
                FormatButton(title: "标题2", icon: "textformat.size") {
                    onSelect(.heading(level: 2))
                }
                FormatButton(title: "标题3", icon: "textformat.size.smaller") {
                    onSelect(.heading(level: 3))
                }
                FormatButton(title: "列表", icon: "list.bullet") {
                    onSelect(.bullet)
                }
                FormatButton(title: "编号", icon: "list.number") {
                    onSelect(.numbered)
                }
                FormatButton(title: "待办", icon: "checklist") {
                    onSelect(.todo)
                }
                FormatButton(title: "引用", icon: "text.quote") {
                    onSelect(.quote)
                }
                FormatButton(title: "代码", icon: "chevron.left.forwardslash.chevron.right") {
                    onSelect(.code)
                }
                FormatButton(title: "表格", icon: "tablecells") {
                    onSelect(.table(rows: 3, cols: 3))
                }
            }
            .padding(.horizontal, 16)
            
            Divider()
                .padding(.vertical, 8)
            
            HStack(spacing: 16) {
                FormatButton(title: "粗体", icon: "bold") {
                    onSelect(.bold)
                }
                FormatButton(title: "斜体", icon: "italic") {
                    onSelect(.italic)
                }
                FormatButton(title: "代码", icon: "curlybraces") {
                    onSelect(.inlineCode)
                }
            }
            .padding(.horizontal, 16)
            
            Button("取消") {
                dismiss()
            }
            .padding(.vertical, 12)
        }
        .frame(minWidth: 320)
    }
}

private struct FormatButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 11))
            }
            .frame(width: 70, height: 50)
        }
        .buttonStyle(.plain)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }
}

#endif
