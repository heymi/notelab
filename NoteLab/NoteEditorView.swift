#if os(iOS)
import SwiftUI
import Combine
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif
import QuickLook
import CoreText

struct NoteEditorView: View {
    @Binding var note: Note
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var aiClient: AIClient
    @EnvironmentObject private var aiCenter: AIProcessingCenter
    @EnvironmentObject private var voiceCoordinator: VoiceNoteCoordinator
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    private let logger = Logger(subsystem: "NoteLab", category: "NoteEditor")

    var isWhiteboard: Bool = false
    var onClose: (() -> Void)? = nil

    @State private var showAIAction = false
    @State private var selectedText: String = ""
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var selectedBlockIds: [UUID] = []
    @State private var document: NoteDocument = NoteDocument.fromPlainText("")
    @State private var macEditorText: String = ""
    @State private var showSendSheet = false
    @State private var showMoreMenu = false
    #if os(iOS)
    @State private var showMoveSheet = false
    @State private var showShareSheet = false
    @State private var showPDFSizeSheet = false
    @State private var showPDFPreview = false
    @State private var shareItems: [Any] = []
    @State private var exportPDFURL: URL?
    @State private var selectedPDFSize: PDFPageSize = .a4
    @State private var showMoveUnavailableAlert = false
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    #endif
    @State private var sendToast: SendToast?
    @State private var undoToast: UndoToast?
    @State private var undoSnapshot: NoteUndoSnapshot?
    @State private var sendDraftText: String = ""
    @State private var sendDraftBlockIds: [UUID] = []
    @State private var showSelectionAlert = false
    @State private var showFormatMenu = false
    @State private var pendingCommand: EditorCommandRequest?
    @State private var pendingTipTapCommand: TipTapCommand?
    @State private var showAttachmentPicker = false
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var showWhiteboardLinks = false
    @State private var showClearWhiteboardConfirm = false
    @State private var flushNextDocumentChange = false
    @State private var detailPresentationMode: NoteDetailPresentationMode = .reading
    @State private var bodyFocusToken = UUID()
    @State private var whiteboardLinkDrag: CGSize = .zero
    @AppStorage("whiteboard.link.offset.x") private var whiteboardLinkOffsetX: Double = 0
    @AppStorage("whiteboard.link.offset.y") private var whiteboardLinkOffsetY: Double = 0
    @State private var whiteboardLinkSize: CGSize = .zero
    @State private var isDraggingWhiteboardLink = false
    @State private var voiceNoteRecord: VoiceNoteRecord?
    @StateObject private var titleFocusBridge = TitleFocusBridge()
    @State private var exitMultiSelectToken: UUID = UUID()

    var body: some View {
        editorScaffold
            .onAppear {
                loadDocumentIfNeeded()
                applyInitialPresentationMode()
                refreshVoiceNoteRecord()
            }
            .onDisappear { store.flushPendingNotePersistence(noteId: note.id) }
            .onChange(of: note.id) { oldValue, _ in
                store.flushPendingNotePersistence(noteId: oldValue)
                loadDocumentIfNeeded()
                applyInitialPresentationMode()
                refreshVoiceNoteRecord()
            }
            .onChange(of: aiCenter.lastAppliedNoteId) { _, newValue in
                if newValue == note.id {
                    loadDocumentIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceNoteDidUpdate)) { notification in
                guard let updatedNoteId = notification.object as? UUID, updatedNoteId == note.id else { return }
                loadDocumentIfNeeded()
                refreshVoiceNoteRecord()
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceNoteRetryRequested)) { notification in
                guard let recordId = notification.object as? UUID,
                      let record = voiceNoteRecord,
                      record.id == recordId else { return }
                voiceCoordinator.retry(recordId: record.id, profileId: record.profileId, store: store, aiClient: aiClient)
            }
            .sheet(isPresented: $showAIAction) {
                AIMenuSheet(
                    isPresented: $showAIAction,
                    hasUndo: hasUndoSnapshot,
                    onAutoOrganize: { triggerAutoOrganize() },
                    onExtractTodos: { triggerExtractTodosCommand() },
                    onRewrite: { mode in triggerRewriteCommand(mode: mode) },
                    onUndo: { restoreUndoSnapshot() }
                )
            }
            .sheet(isPresented: $showSendSheet) { sendSheet }
            .sheet(isPresented: $showMoreMenu) {
                MoreMenuSheet(
                    isWhiteboard: isWhiteboard,
                    canMoveNote: canMoveNote,
                    onMove: {
                        if canMoveNote {
                            showMoveSheet = true
                        } else {
                            showMoveUnavailableAlert = true
                        }
                    },
                    onShare: { prepareShare() },
                    onCopyMarkdown: { copyMarkdownToPasteboard() },
                    onExport: { showPDFSizeSheet = true },
                    onClear: { showClearWhiteboardConfirm = true }
                )
            }
            .sheet(isPresented: $showPDFSizeSheet) {
                PDFSizeSelectionSheet(
                    selectedSize: $selectedPDFSize,
                    onExport: {
                        showPDFSizeSheet = false
                        exportPDF()
                    }
                )
            }
            .sheet(isPresented: $showMoveSheet) {
                MoveNoteSheet(
                    notebooks: store.notebooks,
                    currentNotebookId: currentNotebookId,
                    onMove: { targetId in
                        store.moveNote(noteId: note.id, to: targetId)
                    }
                )
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showPDFPreview) {
                if let url = exportPDFURL {
                    PDFPreviewSheet(url: url)
                } else {
                    Text("无法预览")
                }
            }
            .alert("无法移动笔记", isPresented: $showMoveUnavailableAlert) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("当前笔记不在笔记本中，或没有可用的目标笔记本。")
            }
            .alert("导出失败", isPresented: $showExportError) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(exportErrorMessage)
            }
            .onChange(of: sendToast) { _, newValue in dismissToastAfterDelay(newValue) }
            .onChange(of: undoToast) { _, newValue in dismissUndoToastAfterDelay(newValue) }
            .alert("请先选中内容", isPresented: $showSelectionAlert) {
                Button("知道了", role: .cancel) {}
            }
            .confirmationDialog("清空白板内容", isPresented: $showClearWhiteboardConfirm) {
                Button("清空", role: .destructive) { clearWhiteboard() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showFormatMenu) {
                FormatMenuSheet { command, tipTap in
                    sendFormatCommand(command, tipTap: tipTap)
                    showFormatMenu = false
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showAttachmentPicker) {
                AttachmentMenuSheet(
                    onPhoto: { showImagePicker = true },
                    onFile: { showDocumentPicker = true }
                )
                .presentationDetents([.height(220)])
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView { image in
                    insertImageAttachment(image)
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView { url in
                    insertDocumentAttachment(url)
                }
            }
    }

    private func sendFormatCommand(_ native: EditorCommand?, tipTap: TipTapCommand) {
        #if os(iOS)
        if AppConfig.useWebEditor {
            pendingTipTapCommand = tipTap
        } else if let native {
            pendingCommand = EditorCommandRequest(command: native)
        }
        #else
        if let native {
            pendingCommand = EditorCommandRequest(command: native)
        }
        #endif
    }

    private var editorScaffold: some View {
        mainEditor
    }

    private var editorDetailBackground: some View {
        ZStack(alignment: .top) {
            if let style = currentNotebookBackground.generatedStyle(for: colorScheme) {
                LinearGradient(
                    colors: [Color(hex: style.washHex), Color(hex: style.baseHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Theme.editorBackground
                LinearGradient(
                    colors: [
                        Theme.editorTopWash.opacity(0.65),
                        Theme.editorTopWash.opacity(0.22),
                        Theme.editorBackground.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 230)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }

    private var mainEditor: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let contentTopInset = max(0, safeTop - 44)
            let topInset = contentTopInset + 58
            let toolbarTopInset = max(0, safeTop - 56)
            let bottomInset: CGFloat = 130

            Group {
                if AppConfig.useWebEditor {
                    TipTapEditorView(
                        markdown: $note.content,
                        selectedText: $selectedText,
                        selectedRange: $selectedRange,
                        pendingCommand: $pendingTipTapCommand,
                        title: "",
                        showsTitle: false,
                        topInset: topInset,
                        bottomInset: bottomInset,
                        onMarkdownChange: { markdown in
                            let doc = NoteDocument.fromMarkdown(markdown)
                            document = doc
                            syncNoteFromDocument(doc)
                        },
                        onTitleChange: { _ in }
                    )
                } else {
                    BlockEditorRepresentable(
                        document: $document,
                        selectedText: $selectedText,
                        selectedRange: $selectedRange,
                        selectedBlockIds: $selectedBlockIds,
                        pendingCommand: $pendingCommand,
                        exitMultiSelectToken: $exitMultiSelectToken,
                        bodyFocusToken: $bodyFocusToken,
                        title: $note.title,
                        titleFocusBridge: titleFocusBridge,
                        headerMetadata: headerMetadata,
                        linkBlocks: linkBlocks,
                        presentationMode: detailPresentationMode,
                        sentHighlightBlockIds: sentHighlightBlockIds,
                        isWhiteboard: isWhiteboard,
                        background: isWhiteboard ? .default : currentNotebookBackground,
                        topInset: topInset,
                        bottomInset: bottomInset,
                        onOpenNote: { router.push(.note($0)) },
                        onDocumentChange: { doc in
                            document = doc
                            syncNoteFromDocument(doc)
                            if flushNextDocumentChange {
                                flushNextDocumentChange = false
                                store.flushPendingNotePersistence(noteId: note.id)
                            }
                        },
                        ownerId: activeProfileId,
                        noteId: note.id
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(editorDetailBackground)
            .background(InteractivePopGestureEnabler())
            .overlay(alignment: .top) {
                editorTopBar
                    .padding(.horizontal, 18)
                    .padding(.top, toolbarTopInset + 2)
                    .padding(.bottom, 6)
            }
            .overlay(alignment: .top) {
                toastOverlay
                    .padding(.top, toolbarTopInset + 2)
            }
            .overlay {
                if isWhiteboard && !linkBlocks.isEmpty {
                    whiteboardLinkFloater(topInset: toolbarTopInset)
                }
            }
            .overlay(alignment: .bottom) {
                if !detailPresentationMode.isEditing {
                    editorBottomBar
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if detailPresentationMode.isEditing {
                    editorBottomBar
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, 0)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        EditorToastOverlay(
            undoToast: $undoToast,
            sendToast: $sendToast,
            onUndo: { restoreUndoSnapshot() },
            onSend: { router.push(.note($0)) }
        )
        .padding(.top, 66)
    }

    private func triggerSend() {
        if selectedText.isEmpty {
            Haptics.shared.play(.warning)
            showSelectionAlert = true
        } else {
            sendDraftText = selectedText
            sendDraftBlockIds = selectedBlockIds
            showSendSheet = true
        }
    }

    private var sendSheet: some View {
        SendSelectionView(
            isPresented: $showSendSheet,
            selectedText: sendDraftText,
            onSend: { notebookId, title in
                let linkTitle = NoteTitleDeriver.title(fromMarkdown: sendDraftText, fallback: title)
                if let newId = store.addNote(to: notebookId, title: title, content: sendDraftText) {
                    insertLinkBlock(noteId: newId, notebookId: notebookId, title: linkTitle)
                    sendToast = SendToast(noteId: newId, message: "已发送到笔记本")
                    exitMultiSelectToken = UUID()
                    Haptics.shared.play(.success)
                }
                sendDraftText = ""
                sendDraftBlockIds = []
            }
        )
    }

    private func noteTitleForExport() -> String {
        let derived = NoteTitleDeriver.title(from: document, fallback: note.title)
        let trimmed = derived.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }

    private func prepareShare() {
        let title = noteTitleForExport()
        shareItems = [NoteShareBuilder.plainText(title: title, document: document, fallbackMarkdown: note.content)]
        showShareSheet = true
    }

    private func copyMarkdownToPasteboard() {
        let title = noteTitleForExport()
        let markdown = NoteShareBuilder.markdown(title: title, document: document, fallbackMarkdown: note.content)
        guard !markdown.isEmpty else { return }
        UIPasteboard.general.string = markdown
        sendToast = SendToast(noteId: nil, message: "已复制 Markdown")
        Haptics.shared.play(.success)
    }

    private func exportPDF() {
        Task {
            await exportPDFAsync()
        }
    }

    @MainActor
    private func exportPDFAsync() async {
        let title = noteTitleForExport()
        do {
            exportPDFURL = try await NotePDFExporter.export(
                title: title,
                document: document,
                pageSize: selectedPDFSize,
                noteId: note.id
            )
            showPDFPreview = true
        } catch {
            exportErrorMessage = (error as? NotePDFExportError) == .renderFailed
                ? "无法生成 PDF，请稍后再试。"
                : "保存 PDF 失败，请稍后再试。"
            showExportError = true
        }
    }

    private var hasUndoSnapshot: Bool {
        undoSnapshot != nil
    }

    private func dismissToastAfterDelay(_ newValue: SendToast?) {
        guard let toast = newValue else { return }
        let currentId = toast.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if sendToast?.id == currentId { sendToast = nil }
        }
    }

    private func dismissUndoToastAfterDelay(_ newValue: UndoToast?) {
        guard let toast = newValue else { return }
        let currentId = toast.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            if undoToast?.id == currentId { undoToast = nil }
        }
    }

    private func restoreUndoSnapshot() {
        guard let snapshot = undoSnapshot else { return }
        let doc = NoteDocument.fromMarkdown(snapshot.content)
        document = doc
        syncNoteFromDocument(doc)
        store.flushPendingNotePersistence(noteId: note.id)
        undoSnapshot = nil
        NoteUndoSnapshotStore.clear(noteId: note.id)
        Haptics.shared.play(.success)
    }

    private func insertLinkBlock(noteId: UUID, notebookId: UUID, title: String) {
        selectedText = ""
        let block = LinkedNoteBlock(
            id: UUID(),
            noteId: noteId,
            notebookId: notebookId,
            title: title,
            sourceRangeLocation: nil,
            sourceRangeLength: nil,
            sourceBlockIds: sendDraftBlockIds.isEmpty ? nil : sendDraftBlockIds
        )
        store.addLinkBlock(block, to: self.note.id)
        selectedRange = NSRange(location: 0, length: 0)
        selectedBlockIds = []
    }

    private func whiteboardLinkFloater(topInset: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.clear
                whiteboardLinkOverlay
                    .readSize { whiteboardLinkSize = $0 }
                    .padding(.top, topInset + 70)
                    .padding(.trailing, 12)
                    .offset(currentWhiteboardOffset(container: proxy.size, insets: proxy.safeAreaInsets))
                    .opacity(isDraggingWhiteboardLink ? 0.8 : 1)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                whiteboardLinkDrag = value.translation
                                if !isDraggingWhiteboardLink {
                                    isDraggingWhiteboardLink = true
                                }
                            }
                            .onEnded { value in
                                let raw = CGSize(width: whiteboardLinkOffsetX + value.translation.width,
                                                height: whiteboardLinkOffsetY + value.translation.height)
                                let clamped = WhiteboardLinkSnapper.clamp(offset: raw, container: proxy.size, insets: proxy.safeAreaInsets, overlaySize: whiteboardLinkSize)
                                let snapped = WhiteboardLinkSnapper.snap(offset: clamped, container: proxy.size, insets: proxy.safeAreaInsets, overlaySize: whiteboardLinkSize)
                                whiteboardLinkDrag = .zero
                                withAnimation(.interpolatingSpring(stiffness: 360, damping: 30)) {
                                    whiteboardLinkOffsetX = snapped.width
                                    whiteboardLinkOffsetY = snapped.height
                                }
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isDraggingWhiteboardLink = false
                                }
                            }
                    )
            }
        }
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        detailPresentationMode = .reading
    }

    private func enterEditingMode(focusBody: Bool = true) {
        detailPresentationMode = .editing
        if focusBody {
            bodyFocusToken = UUID()
        }
    }

    private func applyInitialPresentationMode() {
        let mode = initialPresentationMode
        detailPresentationMode = mode
        if mode.isEditing {
            bodyFocusToken = UUID()
        }
    }

    private var initialPresentationMode: NoteDetailPresentationMode {
        isWhiteboard || !hasHeaderBodyContent ? .editing : .reading
    }

    private func loadDocumentIfNeeded() {
        let loadedDocument = store.document(for: note.id, fallbackText: note.content)
        document = loadedDocument
        syncDerivedTitle(from: loadedDocument)
        undoSnapshot = NoteUndoSnapshotStore.load(noteId: note.id)
        selectedText = ""
        selectedRange = NSRange(location: 0, length: 0)
        selectedBlockIds = []
        sendDraftText = ""
        sendDraftBlockIds = []
    }

    private func syncNoteFromDocument(_ doc: NoteDocument) {
        let markdown = doc.flattenMarkdown()
        let contentChanged = markdown != note.content
        note.content = markdown
        syncDerivedTitle(from: doc)
        if contentChanged && !isWhiteboard {
            note.summary = ""
            AISummaryRegistry.clear(noteId: note.id)
        }
        note.updateMetrics()
        if note.id == store.whiteboard.id {
            store.persistWhiteboard()
        }
        store.updateDocument(noteId: note.id, document: doc)
    }

    private func syncDerivedTitle(from doc: NoteDocument) {
        guard !isWhiteboard else { return }
        let generatedSummary = AISummaryRegistry.isGenerated(noteId: note.id, summary: note.summary) ? note.summary : nil
        note.title = NoteTitleDeriver.title(from: doc, fallback: "", ignoringGeneratedSummary: generatedSummary)
    }

    private func appendPlainText(_ text: String) {
        let current = document.flattenMarkdown()
        let updated = current.hasSuffix("\n") || text.hasPrefix("\n") ? current + text : current + "\n" + text
        let newDoc = NoteDocument.fromMarkdown(updated)
        document = newDoc
        syncNoteFromDocument(newDoc)
    }

    private func insertImageAttachment(_ image: UIImage) {
        guard let payload = NoteAttachmentInserter.imagePayload(from: image) else {
            logger.error("Failed to convert image to JPEG data")
            return
        }
        insertAttachmentPayload(payload)
    }

    private func insertDocumentAttachment(_ url: URL) {
        guard let payload = NoteAttachmentInserter.documentPayload(from: url) else {
            logger.error("Failed to read document data")
            return
        }
        insertAttachmentPayload(payload)
    }

    private func insertAttachmentPayload(_ payload: NoteAttachmentPayload) {
        if !AppConfig.useWebEditor {
            flushNextDocumentChange = true
            pendingCommand = EditorCommandRequest(command: NoteAttachmentInserter.nativeCommand(for: payload))
            return
        }

        guard let ownerId = activeProfileId else {
            logger.error("No owner ID available for attachment upload")
            return
        }

        appendPlainText(NoteAttachmentInserter.webMarkdown(for: payload, ownerId: ownerId))
        store.flushPendingNotePersistence(noteId: note.id)
        Haptics.shared.play(.success)

        Task { @MainActor in
            do {
                try await NoteAttachmentInserter.upload(payload: payload, ownerId: ownerId, noteId: note.id)
                logger.info("Attachment uploaded successfully: \(payload.attachmentId)")
            } catch {
                logger.error("Failed to upload attachment: \(error.localizedDescription)")
            }
        }
    }

    private var activeProfileId: UUID? {
        store.currentProfileId ?? auth.userId
    }

    private func clearWhiteboard() {
        guard isWhiteboard else { return }
        Haptics.shared.play(.warning)
        let cleared = NoteDocument.fromPlainText("")
        document = cleared
        note.contentRTF = nil
        selectedText = ""
        selectedRange = NSRange(location: 0, length: 0)
        selectedBlockIds = []
        sendDraftText = ""
        sendDraftBlockIds = []
        showWhiteboardLinks = false
        syncNoteFromDocument(cleared)
        store.updateLinkBlocks(for: note.id) { _ in [] }
    }

    private func toolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleClose() {
        store.flushPendingNotePersistence(noteId: note.id)
        onClose?()
        if !router.path.isEmpty {
            router.pop()
        } else {
            dismiss()
        }
    }

    private var editorTopBar: some View {
        HStack(spacing: 8) {
            toolbarButton(systemName: "chevron.left") {
                handleClose()
            }
            Spacer(minLength: 0)
            toolbarButton(systemName: "textformat") {
                enterEditingMode(focusBody: false)
                showFormatMenu = true
            }
            toolbarButton(systemName: "paperclip") {
                enterEditingMode(focusBody: false)
                showAttachmentPicker = true
            }
            toolbarButton(systemName: "sparkles") {
                showAIAction = true
            }
            toolbarButton(systemName: "paperplane") {
                triggerSend()
            }
            toolbarButton(systemName: "ellipsis") {
                showMoreMenu = true
            }
        }
        .foregroundStyle(editorInk)
    }

    private var editorBottomBar: some View {
        editorBottomBarContent
    }

    private var presentationModeBinding: Binding<NoteDetailPresentationMode> {
        Binding(
            get: { detailPresentationMode },
            set: { mode in
                mode.isEditing ? enterEditingMode() : hideKeyboard()
            }
        )
    }

    @ViewBuilder
    private var editorBottomBarContent: some View {
        Picker("", selection: presentationModeBinding) {
            Text("阅读").tag(NoteDetailPresentationMode.reading)
            Text("编辑").tag(NoteDetailPresentationMode.editing)
        }
        .pickerStyle(.segmented)
    }

    private var linkBlocks: [LinkedNoteBlock] {
        store.linkBlocks(for: note.id)
    }

    private var headerMetadata: NoteEditorHeaderMetadata {
        let todoCount = document.blocks.filter { $0.kind == .todo && ($0.isChecked ?? false) == false }.count
        let visibleText = document.blocks
            .filter { $0.kind != .attachment && $0.kind != .table }
            .map(\.text)
            .joined(separator: " ")
        let readingMinutes = max(1, Int(ceil(Double(visibleText.count) / 420.0)))
        let summary = note.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return NoteEditorHeaderMetadata(
            updatedAt: note.updatedAt,
            summary: summary,
            readingMinutes: readingMinutes,
            todoCount: todoCount,
            notebookLabel: "本地优先",
            preview: headerContentPreview,
            hasBodyContent: hasHeaderBodyContent,
            voiceNote: voiceNoteRecord
        )
    }

    private func refreshVoiceNoteRecord() {
        voiceNoteRecord = voiceCoordinator.record(for: note.id)
    }

    private var hasHeaderBodyContent: Bool {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return document.blocks.enumerated().contains { index, block in
            if block.kind == .attachment || block.kind == .table {
                return true
            }
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            if index == 0 && NoteTitleDeriver.cleanedTitleLine(text) == title {
                return false
            }
            return true
        }
    }

    private var headerContentPreview: NoteEditorHeaderMetadata.Preview? {
        let summary = note.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AISummaryRegistry.isGenerated(noteId: note.id, summary: summary) else { return nil }
        let displaySummary = AISummaryText.normalized(summary)
        return NoteEditorHeaderMetadata.Preview(
            title: "AI 摘要",
            detail: "已分析",
            style: .excerpt,
            items: [displaySummary]
        )
    }

    private var currentNotebookId: UUID? {
        store.notebookId(for: note.id)
    }

    private var currentNotebookBackground: NotebookBackground {
        isWhiteboard ? .default : store.notebookBackground(for: note.id)
    }

    private var editorUsesLightForeground: Bool {
        currentNotebookBackground.usesLightForeground(isDarkMode: colorScheme == .dark)
    }

    private var editorInk: Color {
        currentNotebookBackground.generatedStyle(for: colorScheme) == nil ? Theme.ink : currentNotebookBackground.swiftUIInk(for: colorScheme).opacity(0.92)
    }

    private var editorSecondaryInk: Color {
        currentNotebookBackground.generatedStyle(for: colorScheme) == nil ? Theme.secondaryInk : currentNotebookBackground.swiftUISecondaryInk(for: colorScheme).opacity(0.88)
    }

    private func currentNotebookContext() -> String? {
        store.noteMetadata(for: note.id)?.notebookDescription
    }

    private func triggerAutoOrganize() {
        aiCenter.startAutoOrganize(
            noteId: note.id,
            title: noteTitleForExport(),
            content: note.content,
            notebookContext: currentNotebookContext(),
            aiClient: aiClient,
            store: store
        )
    }

    private func triggerExtractTodosCommand() {
        aiCenter.startExtractTodosInsertTop(
            noteId: note.id,
            content: note.content,
            aiClient: aiClient,
            store: store
        )
    }

    private func triggerRewriteCommand(mode: AIRewriteMode) {
        aiCenter.startRewrite(
            noteId: note.id,
            title: noteTitleForExport(),
            content: note.content,
            notebookContext: currentNotebookContext(),
            mode: mode,
            aiClient: aiClient,
            store: store
        )
    }

    private var canMoveNote: Bool {
        !isWhiteboard && currentNotebookId != nil && store.notebooks.count > 1
    }

    private var sentHighlightBlockIds: Set<UUID> {
        guard isWhiteboard else { return [] }
        let ids = linkBlocks.compactMap { $0.sourceBlockIds }.flatMap { $0 }
        return Set(ids)
    }

    private var visibleWhiteboardBlocks: [LinkedNoteBlock] {
        let orderedBlocks = linkBlocks.reversed()
        if showWhiteboardLinks {
            return Array(orderedBlocks)
        }
        return Array(orderedBlocks.prefix(3))
    }

    private func currentWhiteboardOffset(container: CGSize, insets: EdgeInsets) -> CGSize {
        let raw = CGSize(width: whiteboardLinkOffsetX + whiteboardLinkDrag.width,
                        height: whiteboardLinkOffsetY + whiteboardLinkDrag.height)
        return WhiteboardLinkSnapper.clamp(offset: raw, container: container, insets: insets, overlaySize: whiteboardLinkSize)
    }

    private var whiteboardLinkOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showWhiteboardLinks.toggle() } }) {
                HStack(spacing: 6) {
                    Text("引用")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk)
                    Image(systemName: showWhiteboardLinks ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(visibleWhiteboardBlocks) { block in
                Button(action: { router.push(.note(block.noteId)) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                        Text(block.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        removeLinkBlock(block)
                    } label: {
                        Text("移除引用")
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: 220)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 10, x: 0, y: 6)
    }

    private func removeLinkBlock(_ block: LinkedNoteBlock) {
        store.updateLinkBlocks(for: note.id) { blocks in
            blocks.filter { $0.id != block.id }
        }
    }
}

private struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let actionTitle: String
}

private struct UndoToastView: View {
    let message: String
    let actionTitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(actionTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85), in: Capsule())
        }
    }
}

private struct SendToast: Identifiable, Equatable {
    let id = UUID()
    let noteId: UUID?
    let message: String
}

private struct SendToastView: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text(text)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85), in: Capsule())
        }
    }
}

private struct EditorToastOverlay: View {
    @Binding var undoToast: UndoToast?
    @Binding var sendToast: SendToast?
    let onUndo: () -> Void
    let onSend: (UUID) -> Void

    var body: some View {
        if let toast = undoToast {
            UndoToastView(message: toast.message, actionTitle: toast.actionTitle) {
                onUndo()
                undoToast = nil
            }
        } else if let toast = sendToast {
            SendToastView(text: toast.message) {
                if let noteId = toast.noteId {
                    onSend(noteId)
                }
                sendToast = nil
            }
        }
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

import PhotosUI

struct ImagePickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView

        init(parent: ImagePickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let result = results.first else { return }
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                    if let image = image as? UIImage {
                        DispatchQueue.main.async {
                            self?.parent.onImagePicked(image)
                        }
                    }
                }
            }
        }
    }
}

import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    let onDocumentPicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.pdf, .image, .movie, .mpeg4Movie, .quickTimeMovie, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.dismiss()
            if let url = urls.first {
                parent.onDocumentPicked(url)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

struct PDFPreviewSheet: View {
    let url: URL
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .navigationTitle("PDF 预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [url])
        }
    }
}

enum PDFPageSize: String, CaseIterable, Identifiable {
    case a4 = "A4"
    case ratio4x3 = "4:3"
    case phone = "手机"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .a4: return "A4 (标准打印)"
        case .ratio4x3: return "4:3 (演示文稿)"
        case .phone: return "手机 (竖屏阅读)"
        }
    }

    var description: String {
        switch self {
        case .a4: return "595 × 842 pt"
        case .ratio4x3: return "800 × 600 pt"
        case .phone: return "390 × 844 pt"
        }
    }

    var pageRect: CGRect {
        switch self {
        case .a4: return CGRect(x: 0, y: 0, width: 595, height: 842)
        case .ratio4x3: return CGRect(x: 0, y: 0, width: 800, height: 600)
        case .phone: return CGRect(x: 0, y: 0, width: 390, height: 844)
        }
    }

    var margin: CGFloat {
        switch self {
        case .a4: return 36
        case .ratio4x3: return 40
        case .phone: return 24
        }
    }
}

struct PDFSizeSelectionSheet: View {
    @Binding var selectedSize: PDFPageSize
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            Text("选择 PDF 尺寸")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)

            VStack(spacing: 12) {
                ForEach(PDFPageSize.allCases) { size in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedSize = size
                            Haptics.shared.play(.selection)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(size.displayName)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                Text(size.description)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                            Spacer()
                            if selectedSize == size {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedSize == size ? Theme.cardBackground : Theme.cardBackground.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedSize == size ? Theme.ink : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Haptics.shared.play(.success)
                    onExport()
                } label: {
                    Text("导出")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(380)])
    }
}

struct MoveNoteSheet: View {
    let notebooks: [Notebook]
    let currentNotebookId: UUID?
    let onMove: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedNotebookId: UUID?

    private var availableNotebooks: [Notebook] {
        notebooks.filter { $0.id != currentNotebookId }
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            Text("移动到笔记本")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)

            if availableNotebooks.isEmpty {
                Text("没有可用的目标笔记本")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.top, 10)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(availableNotebooks) { notebook in
                            NotebookSelectionCell(
                                notebook: notebook,
                                isSelected: selectedNotebookId == notebook.id,
                                action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedNotebookId = notebook.id
                                        Haptics.shared.play(.selection)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))

                Button("移动") {
                    move()
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .disabled(selectedNotebookId == nil)
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            if selectedNotebookId == nil {
                selectedNotebookId = availableNotebooks.first?.id
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func move() {
        guard let target = selectedNotebookId else { return }
        Haptics.shared.play(.success)
        onMove(target)
        dismiss()
    }
}

struct FormatMenuSheet: View {
    let onSelect: (EditorCommand?, TipTapCommand) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            Text("格式")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("样式")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                            FormatButton(title: "加粗", icon: "bold", action: { onSelect(.bold, .bold) })
                            FormatButton(title: "斜体", icon: "italic", action: { onSelect(.italic, .italic) })
                            FormatButton(title: "代码", icon: "chevron.left.forwardslash.chevron.right", action: { onSelect(.inlineCode, .code) })
                            FormatButton(title: "删除线", icon: "strikethrough", action: { onSelect(nil, .strike) })
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("段落")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            FormatButton(title: "正文", icon: "doc.text", action: { onSelect(.paragraph, .clearFormat) })
                            FormatButton(title: "标题 1", icon: "textformat.size.larger", action: { onSelect(.heading(level: 1), .heading1) })
                            FormatButton(title: "标题 2", icon: "textformat.size", action: { onSelect(.heading(level: 2), .heading2) })
                            FormatButton(title: "标题 3", icon: "textformat.size.smaller", action: { onSelect(.heading(level: 3), .heading3) })
                            FormatButton(title: "引用", icon: "text.quote", action: { onSelect(.quote, .blockquote) })
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("字号")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        HStack(spacing: 12) {
                            FormatButton(title: "增大", icon: "plus.magnifyingglass", action: { onSelect(.increaseFontSize, .clearFormat) })
                            FormatButton(title: "减小", icon: "minus.magnifyingglass", action: { onSelect(.decreaseFontSize, .clearFormat) })
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("列表")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            FormatButton(title: "待办", icon: "checkmark.circle", action: { onSelect(.todo, .taskList) })
                            FormatButton(title: "项目符号", icon: "list.bullet", action: { onSelect(.bullet, .bulletList) })
                            FormatButton(title: "编号", icon: "list.number", action: { onSelect(.numbered, .orderedList) })
                            FormatButton(title: "代码块", icon: "curlybraces", action: { onSelect(.code, .codeBlock) })
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("插入")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                            FormatButton(title: "分割线", icon: "divide", action: { onSelect(nil, .horizontalRule) })
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(Color.systemBackgroundAdaptive)
    }
}

struct FormatButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct AttachmentMenuSheet: View {
    let onPhoto: () -> Void
    let onFile: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            Text("插入附件")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            HStack(spacing: 20) {
                Button(action: {
                    dismiss()
                    onPhoto()
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                        Text("图片")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Theme.cardBackground)
                    .clipShape(.rect(cornerRadius: 16))
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: {
                    dismiss()
                    onFile()
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)
                        Text("文件")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Theme.cardBackground)
                    .clipShape(.rect(cornerRadius: 16))
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .background(Color.systemBackgroundAdaptive)
    }
}

struct MoreMenuSheet: View {
    let isWhiteboard: Bool
    let canMoveNote: Bool
    let onMove: () -> Void
    let onShare: () -> Void
    let onCopyMarkdown: () -> Void
    let onExport: () -> Void
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            Text("更多操作")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            VStack(spacing: 12) {
                if canMoveNote {
                    MenuButton(title: "移动笔记", icon: "folder", color: .primary) {
                        dismiss()
                        onMove()
                    }
                }

                MenuButton(title: "分享", icon: "square.and.arrow.up", color: .primary) {
                    dismiss()
                    onShare()
                }

                MenuButton(title: "复制为 Markdown", icon: "doc.on.clipboard", color: .primary) {
                    dismiss()
                    onCopyMarkdown()
                }

                MenuButton(title: "导出 PDF", icon: "doc.text", color: .primary) {
                    dismiss()
                    onExport()
                }

                if isWhiteboard {
                    MenuButton(title: "清空内容", icon: "trash", color: .red) {
                        dismiss()
                        onClear()
                    }
                }

                MenuButton(title: "取消", icon: "xmark", color: .secondary) {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.systemBackgroundAdaptive)
        .presentationDetents([.height(isWhiteboard ? 420 : 360)])
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .foregroundStyle(color)
            .padding(16)
            .background(Theme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#endif
