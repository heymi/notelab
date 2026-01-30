import Foundation
#if os(macOS)
import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Block Editor View Controller for macOS

final class BlockEditorViewControllerMac: NSViewController {
    var document: NoteDocument
    var onDocumentChange: ((NoteDocument) -> Void)?
    var onSelectionChange: ((String, NSRange) -> Void)?
    var onSelectedBlockIdsChange: (([UUID]) -> Void)?
    
    // Context for attachment storage
    var modelContext: ModelContext?
    var ownerId: UUID?
    var noteId: UUID?
    
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private var blockViews: [UUID: BlockCellViewMac] = [:]
    private var activeBlockId: UUID?
    private var activeTextSelectionRange: NSRange?
    private var sentHighlightBlockIds: Set<UUID> = []
    
    // Header
    private var headerHostingView: NSHostingView<NoteEditorHeaderView>?
    private var titleFocusBridge: TitleFocusBridge?
    
    init(document: NoteDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true
        self.view = containerView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        setupStackView()
        rebuildBlocks()
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    private func setupStackView() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.distribution = .fill
        
        // Create a flipped document view to have correct top-to-bottom layout
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -16)
        ])
        
        scrollView.documentView = documentView
        
        // Bind document view width to scroll view
        if let documentView = scrollView.documentView {
            documentView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                documentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                documentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor)
            ])
        }
    }
    
    func updateHeader(title: Binding<String>, linkBlocks: [LinkedNoteBlock], isWhiteboard: Bool, focusBridge: TitleFocusBridge, onOpenNote: @escaping (UUID) -> Void) {
        titleFocusBridge = focusBridge
        let headerView = NoteEditorHeaderView(title: title, focusBridge: focusBridge, linkBlocks: linkBlocks, isWhiteboard: isWhiteboard, onOpenNote: onOpenNote)
        
        if let existing = headerHostingView {
            existing.rootView = headerView
        } else {
            let hostingView = NSHostingView(rootView: headerView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            headerHostingView = hostingView
            stackView.insertArrangedSubview(hostingView, at: 0)
            
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 16),
                hostingView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -16)
            ])
        }
    }
    
    func updateDocument(_ newDocument: NoteDocument) {
        document = newDocument
        rebuildBlocks()
    }
    
    func updateSentHighlightBlockIds(_ ids: Set<UUID>) {
        sentHighlightBlockIds = ids
        for (id, view) in blockViews {
            view.setSentHighlight(ids.contains(id))
        }
    }
    
    func apply(command: EditorCommand) {
        guard let activeId = activeBlockId,
              let index = document.blocks.firstIndex(where: { $0.id == activeId }) else {
            // Fall back to first block
            guard !document.blocks.isEmpty else { return }
            applyCommand(command, at: 0)
            return
        }
        applyCommand(command, at: index)
    }
    
    private func applyCommand(_ command: EditorCommand, at index: Int) {
        guard index < document.blocks.count else { return }
        var block = document.blocks[index]
        
        switch command {
        case .paragraph:
            block.kind = .paragraph
        case .heading(let level):
            block.kind = .heading
            block.level = level
        case .bullet:
            block.kind = .bullet
        case .numbered:
            block.kind = .numbered
        case .todo:
            block.kind = .todo
            block.isChecked = false
        case .quote:
            block.kind = .quote
        case .code:
            block.kind = .code
        case .table(let rows, let cols):
            block = Block.table(rows: rows, cols: cols)
        case .requestAttachment:
            presentAttachmentPicker()
            return
        case .insertAttachment(let data, let type, let fileName):
            insertAttachment(data: data, type: type, fileName: fileName)
            return
        case .bold:
            applyInlineFormat(at: index, prefix: "**", suffix: "**")
            return
        case .italic:
            applyInlineFormat(at: index, prefix: "*", suffix: "*")
            return
        case .inlineCode:
            applyInlineFormat(at: index, prefix: "`", suffix: "`")
            return
        case .increaseFontSize:
            let currentOffset = block.fontSizeOffset ?? 0
            block.fontSizeOffset = min(currentOffset + 2, 12)
        case .decreaseFontSize:
            let currentOffset = block.fontSizeOffset ?? 0
            block.fontSizeOffset = max(currentOffset - 2, -8)
        }
        
        document.blocks[index] = block
        onDocumentChange?(document)
        rebuildBlocks()
    }
    
    private func applyInlineFormat(at index: Int, prefix: String, suffix: String) {
        guard let blockView = blockViews[document.blocks[index].id] as? TextBlockCellViewMac,
              let range = activeTextSelectionRange, range.length > 0 else { return }
        blockView.insertInlineFormat(prefix: prefix, suffix: suffix, selectedRange: range)
    }
    
    private func rebuildBlocks() {
        // Remove existing block views (keep header)
        let existingViews = stackView.arrangedSubviews.filter { $0 !== headerHostingView }
        existingViews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        blockViews.removeAll()
        
        // Create new block views
        for (index, block) in document.blocks.enumerated() {
            let blockView: BlockCellViewMac
            
            switch block.kind {
            case .table:
                let tableCell = TableBlockCellViewMac()
                tableCell.delegate = self
                tableCell.configure(with: block.table ?? TableModel(rows: 3, cols: 3), blockId: block.id)
                blockView = tableCell
            case .attachment:
                let attachmentCell = AttachmentBlockCellViewMac()
                attachmentCell.delegate = self
                attachmentCell.configure(with: block)
                blockView = attachmentCell
            default:
                let textCell = TextBlockCellViewMac()
                textCell.delegate = self
                let numberIndex = numberIndexForBlock(at: index)
                textCell.configure(with: block, numberIndex: numberIndex)
                blockView = textCell
            }
            
            blockView.setSentHighlight(sentHighlightBlockIds.contains(block.id))
            blockViews[block.id] = blockView
            stackView.addArrangedSubview(blockView)
            
            // Set width constraint
            NSLayoutConstraint.activate([
                blockView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                blockView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
            ])
        }
        
        view.needsLayout = true
    }
    
    private func numberIndexForBlock(at index: Int) -> Int {
        guard document.blocks[index].kind == .numbered else { return 1 }
        var count = 1
        var i = index - 1
        while i >= 0 {
            if document.blocks[i].kind == .numbered {
                count += 1
                i -= 1
            } else {
                break
            }
        }
        return count
    }
    
    // MARK: - Attachment Handling
    
    private func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf]
        panel.message = "选择图片或文档"
        
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.handleSelectedFile(url)
        }
    }
    
    private func handleSelectedFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let fileName = url.lastPathComponent
        let type: AttachmentType = url.pathExtension.lowercased() == "pdf" ? .pdf : .image
        insertAttachment(data: data, type: type, fileName: fileName)
    }
    
    private func insertAttachment(data: Data, type: AttachmentType, fileName: String) {
        let insertIndex: Int
        if let activeId = activeBlockId,
           let index = document.blocks.firstIndex(where: { $0.id == activeId }) {
            insertIndex = index + 1
        } else {
            insertIndex = document.blocks.count
        }
        
        let attachmentId = UUID()
        let attachmentBlock: Block
        
        if let context = modelContext, let ownerId = ownerId, let noteId = noteId {
            // Save to local cache
            AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName)
            
            // Create LocalAttachment record
            let mimeType = AttachmentStorage.mimeType(for: fileName)
            Task { @MainActor in
                do {
                    let localAttachment = try await AttachmentStorage.shared.saveNewAttachment(
                        data: data,
                        attachmentId: attachmentId,
                        ownerId: ownerId,
                        noteId: noteId,
                        fileName: fileName,
                        mimeType: mimeType,
                        context: context
                    )
                    try? context.save()
                    await AttachmentStorage.shared.uploadAndUpsertMetadata(
                        attachment: localAttachment,
                        context: context
                    )
                } catch {
                    print("Failed to save attachment: \(error)")
                }
            }
            
            let ext = (fileName as NSString).pathExtension
            let storageName = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
            let storagePath = "\(ownerId.uuidString)/\(storageName)"
            attachmentBlock = Block.attachment(type: type, fileName: fileName, storagePath: storagePath, attachmentId: attachmentId)
        } else {
            attachmentBlock = Block.attachment(type: type, fileName: fileName, data: data)
        }
        
        document.blocks.insert(attachmentBlock, at: insertIndex)
        document.blocks.insert(Block.paragraph(""), at: insertIndex + 1)
        onDocumentChange?(document)
        rebuildBlocks()
    }
}

// MARK: - Flipped View for proper top-to-bottom layout

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Base Protocol for Block Cells

protocol BlockCellViewMac: NSView {
    func setSentHighlight(_ highlighted: Bool)
    func setMultiSelected(_ selected: Bool)
}

// MARK: - Text Block Cell Delegate

extension BlockEditorViewControllerMac: TextBlockCellViewMacDelegate {
    func textBlockCellDidChange(_ cell: TextBlockCellViewMac, text: String) {
        guard let index = indexForCell(cell) else { return }
        document.blocks[index].text = text
        onDocumentChange?(document)
    }
    
    func textBlockCellDidRequestNewBlock(_ cell: TextBlockCellViewMac, splitAtLocation location: Int) {
        guard let index = indexForCell(cell) else { return }
        let current = document.blocks[index]
        
        // Exit list on empty block
        if current.text.isEmpty {
            if current.kind == .bullet || current.kind == .numbered || current.kind == .todo || current.kind == .quote {
                document.blocks[index].kind = .paragraph
                onDocumentChange?(document)
                rebuildBlocks()
                return
            }
        }
        
        let fullText = current.text
        let safeLocation = min(max(0, location), fullText.count)
        let prefix = String(fullText.prefix(safeLocation))
        let suffix = String(fullText.dropFirst(safeLocation))
        
        document.blocks[index].text = prefix
        
        let newKind: BlockKind
        if current.kind == .heading {
            newKind = .paragraph
        } else {
            newKind = (current.kind == .bullet || current.kind == .numbered || current.kind == .todo || current.kind == .quote) ? current.kind : .paragraph
        }
        
        let newBlock = Block(id: UUID(), kind: newKind, text: suffix, level: nil, isChecked: false, table: nil, attachment: nil, fontSizeOffset: current.fontSizeOffset)
        document.blocks.insert(newBlock, at: index + 1)
        onDocumentChange?(document)
        rebuildBlocks()
        
        // Focus new block
        DispatchQueue.main.async {
            if let newCell = self.blockViews[newBlock.id] as? TextBlockCellViewMac {
                newCell.beginEditing()
            }
        }
    }
    
    func textBlockCellSelectionDidChange(_ cell: TextBlockCellViewMac, selectedText: String, range: NSRange) {
        if let blockId = blockIdForCell(cell) {
            activeBlockId = blockId
        }
        activeTextSelectionRange = range
        onSelectionChange?(selectedText, range)
        
        if selectedText.isEmpty {
            onSelectedBlockIdsChange?([])
        } else if let blockId = blockIdForCell(cell) {
            onSelectedBlockIdsChange?([blockId])
        }
    }
    
    func textBlockCellDidRequestBackspaceAtStart(_ cell: TextBlockCellViewMac) {
        guard let index = indexForCell(cell), index > 0 else {
            titleFocusBridge?.requestFocus = true
            return
        }
        
        let previousIndex = index - 1
        let currentText = document.blocks[index].text
        let previousText = document.blocks[previousIndex].text
        document.blocks[previousIndex].text = previousText + currentText
        document.blocks.remove(at: index)
        onDocumentChange?(document)
        rebuildBlocks()
        
        DispatchQueue.main.async {
            let prevBlock = self.document.blocks[previousIndex]
            if let prevCell = self.blockViews[prevBlock.id] as? TextBlockCellViewMac {
                prevCell.beginEditing(atEnd: true)
            }
        }
    }
    
    func textBlockCellDidToggleTodo(_ cell: TextBlockCellViewMac) {
        guard let index = indexForCell(cell),
              document.blocks[index].kind == .todo else { return }
        let current = document.blocks[index].isChecked ?? false
        document.blocks[index].isChecked = !current
        onDocumentChange?(document)
        rebuildBlocks()
    }
    
    func textBlockCellDidTrigger(_ cell: TextBlockCellViewMac, trigger: MarkdownTrigger) {
        guard let index = indexForCell(cell) else { return }
        var block = document.blocks[index]
        
        switch trigger {
        case .heading(let level):
            block.kind = .heading
            block.level = level
            block.text = ""
        case .bullet:
            block.kind = .bullet
            block.text = ""
        case .numbered:
            block.kind = .numbered
            block.text = ""
        case .todo:
            block.kind = .todo
            block.isChecked = false
            block.text = ""
        case .quote:
            block.kind = .quote
            block.text = ""
        case .codeBlock:
            block.kind = .code
            block.text = ""
        case .table:
            block = Block.table(rows: 3, cols: 3)
            document.blocks[index] = block
            document.blocks.insert(Block.paragraph(""), at: index + 1)
            onDocumentChange?(document)
            rebuildBlocks()
            return
        case .attachment(let type, let data, let fileName):
            block = Block.attachment(type: type, fileName: fileName, data: data)
            document.blocks[index] = block
            document.blocks.insert(Block.paragraph(""), at: index + 1)
            onDocumentChange?(document)
            rebuildBlocks()
            return
        }
        
        document.blocks[index] = block
        onDocumentChange?(document)
        rebuildBlocks()
        
        DispatchQueue.main.async {
            if let cell = self.blockViews[block.id] as? TextBlockCellViewMac {
                cell.beginEditing()
            }
        }
    }
    
    private func indexForCell(_ cell: TextBlockCellViewMac) -> Int? {
        guard let blockId = blockIdForCell(cell) else { return nil }
        return document.blocks.firstIndex(where: { $0.id == blockId })
    }
    
    private func blockIdForCell(_ cell: TextBlockCellViewMac) -> UUID? {
        for (id, view) in blockViews {
            if view === cell {
                return id
            }
        }
        return nil
    }
}

// MARK: - Table Block Cell Delegate

extension BlockEditorViewControllerMac: TableBlockCellViewMacDelegate {
    func tableBlockCellDidChange(_ cell: TableBlockCellViewMac, table: TableModel) {
        guard let blockId = tableBlockIdForCell(cell),
              let index = document.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        document.blocks[index].table = table
        onDocumentChange?(document)
    }
    
    func tableBlockCellDidRequestDelete(_ cell: TableBlockCellViewMac) {
        guard let blockId = tableBlockIdForCell(cell),
              let index = document.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        document.blocks.remove(at: index)
        onDocumentChange?(document)
        rebuildBlocks()
    }
    
    private func tableBlockIdForCell(_ cell: TableBlockCellViewMac) -> UUID? {
        for (id, view) in blockViews {
            if view === cell {
                return id
            }
        }
        return nil
    }
}

// MARK: - Attachment Block Cell Delegate

extension BlockEditorViewControllerMac: AttachmentBlockCellViewMacDelegate {
    func attachmentBlockCellDidRequestDelete(_ cell: AttachmentBlockCellViewMac) {
        guard let blockId = attachmentBlockIdForCell(cell),
              let index = document.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        document.blocks.remove(at: index)
        onDocumentChange?(document)
        rebuildBlocks()
    }
    
    func attachmentBlockCellDidRequestPreview(_ cell: AttachmentBlockCellViewMac) {
        // Will implement Quick Look preview later
    }
    
    private func attachmentBlockIdForCell(_ cell: AttachmentBlockCellViewMac) -> UUID? {
        for (id, view) in blockViews {
            if view === cell {
                return id
            }
        }
        return nil
    }
}

#endif
