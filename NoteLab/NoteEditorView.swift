#if os(iOS)
import SwiftUI
import Combine
import SwiftData
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiClient: AIClient
    @EnvironmentObject private var aiCenter: AIProcessingCenter
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthManager

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
    @State private var whiteboardLinkDrag: CGSize = .zero
    @AppStorage("whiteboard.link.offset.x") private var whiteboardLinkOffsetX: Double = 0
    @AppStorage("whiteboard.link.offset.y") private var whiteboardLinkOffsetY: Double = 0
    @State private var whiteboardLinkSize: CGSize = .zero
    @State private var isDraggingWhiteboardLink = false
    @StateObject private var titleFocusBridge = TitleFocusBridge()
    @State private var exitMultiSelectToken: UUID = UUID()

    var body: some View {
        editorScaffold
            .onAppear { loadDocumentIfNeeded() }
            .onChange(of: note.id) { _, _ in loadDocumentIfNeeded() }
            .onChange(of: aiCenter.lastAppliedNoteId) { _, newValue in
                if newValue == note.id {
                    loadDocumentIfNeeded()
                }
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

    private var mainEditor: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let contentTopInset = max(0, safeTop - 44)
            let topInset = contentTopInset + 52
            let toolbarTopInset = max(0, safeTop - 56)

            Group {
                if AppConfig.useWebEditor {
                    TipTapEditorView(
                        markdown: $note.content,
                        selectedText: $selectedText,
                        selectedRange: $selectedRange,
                        pendingCommand: $pendingTipTapCommand,
                        title: isWhiteboard ? "" : note.title,
                        showsTitle: !isWhiteboard,
                        topInset: topInset,
                        bottomInset: 24,
                        onMarkdownChange: { markdown in
                            let doc = NoteDocument.fromMarkdown(markdown)
                            document = doc
                            syncNoteFromDocument(doc)
                        },
                        onTitleChange: { newTitle in
                            guard !isWhiteboard else { return }
                            note.title = newTitle
                        }
                    )
                } else {
                    BlockEditorRepresentable(
                        document: $document,
                        selectedText: $selectedText,
                        selectedRange: $selectedRange,
                        selectedBlockIds: $selectedBlockIds,
                        pendingCommand: $pendingCommand,
                        exitMultiSelectToken: $exitMultiSelectToken,
                        title: $note.title,
                        titleFocusBridge: titleFocusBridge,
                        linkBlocks: linkBlocks,
                        sentHighlightBlockIds: sentHighlightBlockIds,
                        isWhiteboard: isWhiteboard,
                        topInset: topInset,
                        bottomInset: 24,
                        onOpenNote: { router.push(.note($0)) },
                        onDocumentChange: { doc in
                            document = doc
                            syncNoteFromDocument(doc)
                        },
                        modelContext: modelContext,
                        ownerId: auth.userId,
                        noteId: note.id
                    )
                }
            }
            .background(Theme.background)
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
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { hideKeyboard() }
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = undoToast {
            UndoToastView(message: toast.message, actionTitle: toast.actionTitle) {
                restoreUndoSnapshot()
                undoToast = nil
            }
            .padding(.top, 66)
        } else if let toast = sendToast {
            SendToastView(text: toast.message) {
                router.push(.note(toast.noteId))
                sendToast = nil
            }
            .padding(.top, 66)
        }
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
                if let newId = store.addNote(to: notebookId, title: title, content: sendDraftText) {
                    insertLinkBlock(noteId: newId, notebookId: notebookId, title: title)
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
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }

    private func notePlainTextForExport() -> String {
        let text = document.flattenPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        let fallback = NoteDocument.fromMarkdown(note.content).flattenPlainText()
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prepareShare() {
        let title = noteTitleForExport()
        let body = notePlainTextForExport()
        let content = body.isEmpty ? title : "\(title)\n\n\(body)"
        shareItems = [content]
        showShareSheet = true
    }

    private func exportPDF() {
        Task {
            await exportPDFAsync()
        }
    }

    @MainActor
    private func exportPDFAsync() async {
        let title = noteTitleForExport()
        let items = await buildPDFItems(title: title, document: document)
        guard let data = renderPDFData(items: items, pageSize: selectedPDFSize) else {
            exportErrorMessage = "无法生成 PDF，请稍后再试。"
            showExportError = true
            return
        }

        let safeName = sanitizeFileName(title.isEmpty ? "Note" : title)
        let fileName = "\(safeName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            exportPDFURL = url
            showPDFPreview = true
        } catch {
            exportErrorMessage = "保存 PDF 失败，请稍后再试。"
            showExportError = true
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = name.components(separatedBy: invalid)
        let cleaned = components.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Note-\(note.id.uuidString.prefix(6))"
        }
        return cleaned
    }

    private enum PDFItem {
        case text(NSAttributedString)
        case image(UIImage)
    }

    @MainActor
    private func buildPDFItems(title: String, document: NoteDocument) async -> [PDFItem] {
        var items: [PDFItem] = []

        let titleText = parseMarkdownText(
            title,
            font: .systemFont(ofSize: 24, weight: .bold),
            alignment: .center,
            lineSpacing: 6,
            trailingNewlines: "\n\n"
        )
        items.append(.text(titleText))

        for (index, block) in document.blocks.enumerated() {
            let nextBlock = index + 1 < document.blocks.count ? document.blocks[index + 1] : nil
            let isNextParagraph = nextBlock?.kind == .paragraph || nextBlock?.kind == .bullet || nextBlock?.kind == .numbered || nextBlock?.kind == .todo

            switch block.kind {
            case .heading:
                let level = max(1, min(block.level ?? 1, 6))
                let fontSize: CGFloat = level == 1 ? 20 : level == 2 ? 18 : 16
                let trailingNewlines = isNextParagraph ? "\n" : "\n\n"
                let headingText = parseMarkdownText(
                    block.text,
                    font: .systemFont(ofSize: fontSize, weight: .semibold),
                    lineSpacing: 4,
                    trailingNewlines: trailingNewlines
                )
                items.append(.text(headingText))
            case .paragraph:
                if !block.text.isEmpty {
                    let bodyText = parseMarkdownText(
                        block.text,
                        font: .systemFont(ofSize: 14),
                        lineSpacing: 5,
                        trailingNewlines: "\n"
                    )
                    items.append(.text(bodyText))
                }
            case .bullet:
                let bulletText = "• " + block.text
                let bodyText = parseMarkdownText(
                    bulletText,
                    font: .systemFont(ofSize: 14),
                    lineSpacing: 5,
                    trailingNewlines: "\n"
                )
                items.append(.text(bodyText))
            case .numbered:
                let numberedText = "1. " + block.text
                let bodyText = parseMarkdownText(
                    numberedText,
                    font: .systemFont(ofSize: 14),
                    lineSpacing: 5,
                    trailingNewlines: "\n"
                )
                items.append(.text(bodyText))
            case .todo:
                let checked = block.isChecked ?? false
                let todoPrefix = checked ? "☑ " : "☐ "
                let todoText = todoPrefix + block.text
                let bodyText = parseMarkdownText(
                    todoText,
                    font: .systemFont(ofSize: 14),
                    color: checked ? .secondaryLabel : .label,
                    lineSpacing: 5,
                    trailingNewlines: "\n"
                )
                items.append(.text(bodyText))
            case .quote:
                let quoteText = parseMarkdownText(
                    block.text,
                    font: .italicSystemFont(ofSize: 14),
                    color: .secondaryLabel,
                    lineSpacing: 5,
                    trailingNewlines: "\n"
                )
                items.append(.text(quoteText))
            case .code:
                let codeText = NSMutableAttributedString()
                let codeFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                let codeStyle = NSMutableParagraphStyle()
                codeStyle.lineSpacing = 3
                let codeAttributes: [NSAttributedString.Key: Any] = [
                    .font: codeFont,
                    .foregroundColor: UIColor.label,
                    .backgroundColor: UIColor.systemGray6,
                    .paragraphStyle: codeStyle
                ]
                codeText.append(NSAttributedString(string: block.text + "\n\n", attributes: codeAttributes))
                items.append(.text(codeText))
            case .table:
                let tableText = block.table?.plainText ?? ""
                if !tableText.isEmpty {
                    let bodyText = parseMarkdownText(
                        tableText,
                        font: .systemFont(ofSize: 14),
                        lineSpacing: 5,
                        trailingNewlines: "\n\n"
                    )
                    items.append(.text(bodyText))
                }
            case .attachment:
                if let attachment = block.attachment, attachment.type == .image {
                    if let image = await loadImageAttachment(attachment) {
                        items.append(.image(image))
                    } else {
                        let fallbackText = parseMarkdownText(
                            "[图片未加载: \(attachment.fileName)]",
                            font: .systemFont(ofSize: 12),
                            color: .secondaryLabel,
                            lineSpacing: 5,
                            trailingNewlines: "\n"
                        )
                        items.append(.text(fallbackText))
                    }
                }
            }
        }
        return items
    }

    private func parseMarkdownText(_ text: String, font: UIFont, color: UIColor = .label, alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0, trailingNewlines: String = "\n") -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineSpacing = lineSpacing

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        typealias PatternHandler = (NSMutableAttributedString, NSTextCheckingResult, UIFont, UIColor, NSMutableParagraphStyle) -> Void

        let patterns: [(pattern: String, handler: PatternHandler)] = [
            ("\\*\\*(.*?)\\*\\*", { attrStr, match, baseFont, textColor, paraStyle in
                let fullRange = match.range
                let contentRange = match.range(at: 1)
                guard let range = Range(contentRange, in: attrStr.string) else { return }
                let content = String(attrStr.string[range])
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold)
                let boldFont = descriptor.map { UIFont(descriptor: $0, size: baseFont.pointSize) } ?? baseFont
                let boldAttributes: [NSAttributedString.Key: Any] = [
                    .font: boldFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paraStyle
                ]
                let replacement = NSAttributedString(string: content, attributes: boldAttributes)
                attrStr.replaceCharacters(in: fullRange, with: replacement)
            }),
            ("(?<!\\*)\\*([^\\*]+)\\*(?!\\*)", { attrStr, match, baseFont, textColor, paraStyle in
                let fullRange = match.range
                let contentRange = match.range(at: 1)
                guard let range = Range(contentRange, in: attrStr.string) else { return }
                let content = String(attrStr.string[range])
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
                let italicFont = descriptor.map { UIFont(descriptor: $0, size: baseFont.pointSize) } ?? baseFont
                let italicAttributes: [NSAttributedString.Key: Any] = [
                    .font: italicFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paraStyle
                ]
                let replacement = NSAttributedString(string: content, attributes: italicAttributes)
                attrStr.replaceCharacters(in: fullRange, with: replacement)
            }),
            ("`([^`]+)`", { attrStr, match, baseFont, textColor, paraStyle in
                let fullRange = match.range
                let contentRange = match.range(at: 1)
                guard let range = Range(contentRange, in: attrStr.string) else { return }
                let content = String(attrStr.string[range])
                let monoFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
                let codeAttributes: [NSAttributedString.Key: Any] = [
                    .font: monoFont,
                    .foregroundColor: UIColor.systemRed,
                    .backgroundColor: UIColor.systemGray6,
                    .paragraphStyle: paraStyle
                ]
                let replacement = NSAttributedString(string: content, attributes: codeAttributes)
                attrStr.replaceCharacters(in: fullRange, with: replacement)
            }),
            ("==(\\w+):([^=]+)==", { attrStr, match, baseFont, textColor, paraStyle in
                let fullRange = match.range
                let colorKeyRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                guard let colorKeyRng = Range(colorKeyRange, in: attrStr.string),
                      let contentRng = Range(contentRange, in: attrStr.string) else { return }
                let colorKey = String(attrStr.string[colorKeyRng])
                let content = String(attrStr.string[contentRng])
                let bgColor: UIColor
                switch colorKey {
                case "yellow": bgColor = UIColor.systemYellow.withAlphaComponent(0.4)
                case "green": bgColor = UIColor.systemGreen.withAlphaComponent(0.4)
                case "blue": bgColor = UIColor.systemBlue.withAlphaComponent(0.3)
                case "pink": bgColor = UIColor.systemPink.withAlphaComponent(0.4)
                case "orange": bgColor = UIColor.systemOrange.withAlphaComponent(0.4)
                case "purple": bgColor = UIColor.systemPurple.withAlphaComponent(0.4)
                default: bgColor = UIColor.systemYellow.withAlphaComponent(0.4)
                }
                let highlightAttributes: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: textColor,
                    .backgroundColor: bgColor,
                    .paragraphStyle: paraStyle
                ]
                let replacement = NSAttributedString(string: content, attributes: highlightAttributes)
                attrStr.replaceCharacters(in: fullRange, with: replacement)
            })
        ]

        for (pattern, handler) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
            for match in matches.reversed() {
                handler(attributedString, match, font, color, paragraphStyle)
            }
        }

        if !trailingNewlines.isEmpty {
            attributedString.append(NSAttributedString(string: trailingNewlines, attributes: baseAttributes))
        }

        return attributedString
    }

    @MainActor
    private func loadImageAttachment(_ attachment: AttachmentModel) async -> UIImage? {
        if let data = attachment.data, let image = UIImage(data: data) {
            return image
        }
        let attachmentId = attachment.id
        let fileName = attachment.fileName
        if let cached = AttachmentStorage.shared.loadFromCache(attachmentId: attachmentId, fileName: fileName),
           let image = UIImage(data: cached) {
            return image
        }
        if let storagePath = attachment.storagePath, !storagePath.isEmpty {
            if let data = try? await AttachmentStorage.shared.loadAttachmentData(
                attachmentId: attachmentId,
                storagePath: storagePath,
                fileName: fileName
            ),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    private func renderPDFData(items: [PDFItem], pageSize: PDFPageSize) -> Data? {
        let pageRect = pageSize.pageRect
        let margin: CGFloat = pageSize.margin
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let contentWidth = pageRect.width - margin * 2
        let contentHeight = pageRect.height - margin * 2

        return renderer.pdfData { context in
            var currentY: CGFloat = 0

            func beginPage() {
                context.beginPage()
                currentY = 0
            }

            beginPage()

            for item in items {
                switch item {
                case .image(let image):
                    let imageSize = image.size
                    let maxWidth = contentWidth
                    let maxHeight = contentHeight
                    let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1)
                    let targetSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                    if currentY + targetSize.height > contentHeight {
                        beginPage()
                    }
                    let rect = CGRect(x: margin, y: margin + currentY, width: targetSize.width, height: targetSize.height)
                    image.draw(in: rect)
                    currentY += targetSize.height + 12
                case .text(let text):
                    let boundingSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
                    let textRect = text.boundingRect(with: boundingSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    let textHeight = ceil(textRect.height)
                    if currentY + textHeight > contentHeight {
                        beginPage()
                    }
                    let drawRect = CGRect(x: margin, y: margin + currentY, width: contentWidth, height: textHeight)
                    text.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    currentY += textHeight + 12
                }
            }
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
        if let title = snapshot.title, !title.isEmpty, !isWhiteboard {
            note.title = title
        }
        let doc = NoteDocument.fromMarkdown(snapshot.content)
        document = doc
        syncNoteFromDocument(doc)
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
    }

    private func loadDocumentIfNeeded() {
        document = store.document(for: note.id, fallbackText: note.content)
        undoSnapshot = NoteUndoSnapshotStore.load(noteId: note.id)
        selectedText = ""
        selectedRange = NSRange(location: 0, length: 0)
        selectedBlockIds = []
        sendDraftText = ""
        sendDraftBlockIds = []
    }

    private func syncNoteFromDocument(_ doc: NoteDocument) {
        note.content = doc.flattenMarkdown()
        note.updateMetrics()
        if note.id == store.whiteboard.id {
            store.persistWhiteboard()
        }
        store.updateDocument(noteId: note.id, document: doc)
    }

    private func appendPlainText(_ text: String) {
        let current = document.flattenMarkdown()
        let updated = current.hasSuffix("\n") || text.hasPrefix("\n") ? current + text : current + "\n" + text
        let newDoc = NoteDocument.fromMarkdown(updated)
        document = newDoc
        syncNoteFromDocument(newDoc)
    }

    private func insertImageAttachment(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            logger.error("Failed to convert image to JPEG data")
            return
        }

        let attachmentId = UUID()
        let fileName = "\(attachmentId.uuidString).jpg"

        insertAttachmentData(data: data, attachmentId: attachmentId, fileName: fileName, type: .image)
    }

    private func insertDocumentAttachment(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            logger.error("Failed to read document data")
            return
        }

        let attachmentId = UUID()
        let fileName = url.lastPathComponent
        let type: AttachmentType = fileName.lowercased().hasSuffix(".pdf") ? .pdf : .image

        insertAttachmentData(data: data, attachmentId: attachmentId, fileName: fileName, type: type)
    }

    private func insertAttachmentData(data: Data, attachmentId: UUID, fileName: String, type: AttachmentType) {
        if !AppConfig.useWebEditor {
            pendingCommand = EditorCommandRequest(command: .insertAttachment(data: data, type: type, fileName: fileName))
            return
        }

        guard let ownerId = auth.userId else {
            logger.error("No owner ID available for attachment upload")
            return
        }

        AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName)

        let ext = (fileName as NSString).pathExtension
        let storageName = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
        let storagePath = "\(ownerId.uuidString)/\(storageName)"

        let markdown = "\n![Attachment](\(storagePath))\n"
        appendPlainText(markdown)
        Haptics.shared.play(.success)

        Task { @MainActor in
            do {
                let mimeType = AttachmentStorage.mimeType(for: fileName)
                let localAttachment = try await AttachmentStorage.shared.saveNewAttachment(
                    data: data,
                    attachmentId: attachmentId,
                    ownerId: ownerId,
                    noteId: note.id,
                    fileName: fileName,
                    mimeType: mimeType,
                    context: modelContext
                )
                try? modelContext.save()

                await AttachmentStorage.shared.uploadAndUpsertMetadata(
                    attachment: localAttachment,
                    context: modelContext
                )
                logger.info("Attachment uploaded successfully: \(attachmentId)")
            } catch {
                logger.error("Failed to upload attachment: \(error.localizedDescription)")
            }
        }
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

    private var editorTopBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                toolbarButton(systemName: "chevron.left") {
                    onClose?() ?? dismiss()
                }
                Spacer(minLength: 0)
                toolbarButton(systemName: "textformat") {
                    showFormatMenu = true
                }
                toolbarButton(systemName: "paperclip") {
                    showAttachmentPicker = true
                }
                toolbarButton(systemName: "checkmark.circle") {
                    sendFormatCommand(.todo, tipTap: .taskList)
                }
                toolbarButton(systemName: "paperplane") {
                    triggerSend()
                }
                toolbarButton(systemName: "sparkles") {
                    showAIAction = true
                }
                toolbarButton(systemName: "ellipsis") {
                    showMoreMenu = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .shadow(color: Theme.softShadow, radius: 14, x: 0, y: 8)
        }
    }

    private var linkBlocks: [LinkedNoteBlock] {
        store.linkBlocks(for: note.id)
    }

    private var currentNotebookId: UUID? {
        store.notebookId(for: note.id)
    }

    private func currentNotebookContext() -> String? {
        store.noteMetadata(for: note.id)?.notebookDescription
    }

    private func triggerAutoOrganize() {
        aiCenter.startAutoOrganize(
            noteId: note.id,
            title: note.title,
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
            title: note.title,
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
    let noteId: UUID
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
        let types: [UTType] = [.pdf, .image, .data]
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
        NavigationView {
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
                ScrollView(showsIndicators: false) {
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
            .cornerRadius(12)
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
                    .cornerRadius(16)
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
                    .cornerRadius(16)
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
        .presentationDetents([.height(isWhiteboard ? 360 : 300)])
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
            .cornerRadius(12)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#endif