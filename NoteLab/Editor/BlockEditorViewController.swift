import Foundation
#if canImport(UIKit)
import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

final class BlockEditorViewController: UIViewController, UIGestureRecognizerDelegate {
    var document: NoteDocument
    var onDocumentChange: ((NoteDocument) -> Void)?
    var onSelectionChange: ((String, NSRange) -> Void)?
    var onSelectedBlockIdsChange: (([UUID]) -> Void)?
    
    /// Context and IDs needed for attachment storage
    var modelContext: ModelContext?
    var ownerId: UUID?
    var noteId: UUID?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var activeIndexPath: IndexPath?
    private var activeTableIndexPath: IndexPath?
    private var headerHost: UIHostingController<NoteEditorHeaderView>?
    private var titleFocusBridge: TitleFocusBridge?
    
    // Drag and drop
    private var draggingSourceIndexPath: IndexPath?
    private var dropIndicatorView: UIView?

    private var activeTextSelectionRange: NSRange?
    private var isMultiSelecting: Bool = false
    private var multiSelectedBlockIds: Set<UUID> = []
    private var sentHighlightBlockIds: Set<UUID> = []
    private lazy var multiSelectLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleMultiSelectLongPress(_:)))
    private lazy var multiSelectTap = UITapGestureRecognizer(target: self, action: #selector(handleMultiSelectTap(_:)))
    private lazy var tableDismissTap = UITapGestureRecognizer(target: self, action: #selector(handleTableDismissTap(_:)))
    

    init(document: NoteDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.register(TextBlockCell.self, forCellReuseIdentifier: TextBlockCell.reuseIdentifier)
        tableView.register(TableBlockCell.self, forCellReuseIdentifier: TableBlockCell.reuseIdentifier)
        tableView.register(AttachmentBlockCell.self, forCellReuseIdentifier: AttachmentBlockCell.reuseIdentifier)

        setupNavigationBar()

        multiSelectLongPress.minimumPressDuration = 0.35
        multiSelectLongPress.cancelsTouchesInView = true
        tableView.addGestureRecognizer(multiSelectLongPress)

        multiSelectTap.cancelsTouchesInView = true
        multiSelectTap.isEnabled = false
        tableView.addGestureRecognizer(multiSelectTap)

        tableDismissTap.cancelsTouchesInView = false
        tableDismissTap.delegate = self
        tableView.addGestureRecognizer(tableDismissTap)

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderLayoutIfNeeded()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Auto-focus on empty note
        if shouldAutoFocusOnAppear {
            shouldAutoFocusOnAppear = false
            focusFirstBlockIfEmpty()
        }
    }
    
    private var shouldAutoFocusOnAppear = true
    
    private func focusFirstBlockIfEmpty() {
        // Check if document is empty (only one block with empty text)
        let isEmpty = document.blocks.count == 1 && 
                      document.blocks[0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      document.blocks[0].kind == .paragraph
        
        if isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                let indexPath = IndexPath(row: 0, section: 0)
                if let cell = self.tableView.cellForRow(at: indexPath) as? TextBlockCell {
                    cell.beginEditing(atEnd: false)
                }
            }
        }
    }
    
    

    func updateContentInsets(top: CGFloat, bottom: CGFloat) {
        tableView.contentInset.top = top
        tableView.contentInset.bottom = bottom
        tableView.scrollIndicatorInsets.top = top
        tableView.scrollIndicatorInsets.bottom = bottom
    }

    func updateHeader(title: Binding<String>, linkBlocks: [LinkedNoteBlock], isWhiteboard: Bool, focusBridge: TitleFocusBridge, onOpenNote: @escaping (UUID) -> Void) {
        titleFocusBridge = focusBridge
        let root = NoteEditorHeaderView(title: title, focusBridge: focusBridge, linkBlocks: linkBlocks, isWhiteboard: isWhiteboard, onOpenNote: onOpenNote)
        if let host = headerHost {
            host.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            headerHost = host
            tableView.tableHeaderView = host.view
        }
        updateHeaderLayoutIfNeeded()
    }

    private func updateHeaderLayoutIfNeeded() {
        guard let headerView = headerHost?.view else { return }
        let width = tableView.bounds.width
        let size = headerView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if headerView.frame.size.height != size.height {
            headerView.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
            tableView.tableHeaderView = headerView
        }
    }

    func updateDocument(_ newDocument: NoteDocument) {
        document = newDocument
        tableView.reloadData()
        if isMultiSelecting {
            pruneMultiSelection()
            notifyMultiSelectionChanged()
        }
        if let active = activeTableIndexPath, active.row >= document.blocks.count || document.blocks[active.row].kind != .table {
            activeTableIndexPath = nil
        }
    }

    func updateSentHighlightBlockIds(_ ids: Set<UUID>) {
        sentHighlightBlockIds = ids
        tableView.reloadData()
    }

    func exitMultiSelectModeIfNeeded() {
        if isMultiSelecting {
            exitMultiSelectMode()
        }
    }

    func apply(command: EditorCommand) {
        guard let indexPath = activeIndexPath ?? tableView.indexPathForSelectedRow ?? firstVisibleTextIndexPath() else { return }
        guard indexPath.row < document.blocks.count else { return }
        var block = document.blocks[indexPath.row]
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
            applyInlineFormat(at: indexPath, prefix: "**", suffix: "**")
            return
        case .italic:
            applyInlineFormat(at: indexPath, prefix: "*", suffix: "*")
            return
        case .inlineCode:
            applyInlineFormat(at: indexPath, prefix: "`", suffix: "`")
            return
        case .increaseFontSize:
            let currentOffset = block.fontSizeOffset ?? 0
            block.fontSizeOffset = min(currentOffset + 2, 12) // Max +12pt
            document.blocks[indexPath.row] = block
            onDocumentChange?(document)
            tableView.reloadRows(at: [indexPath], with: .none)
            return
        case .decreaseFontSize:
            let currentOffset = block.fontSizeOffset ?? 0
            block.fontSizeOffset = max(currentOffset - 2, -8) // Min -8pt
            document.blocks[indexPath.row] = block
            onDocumentChange?(document)
            tableView.reloadRows(at: [indexPath], with: .none)
            return
        }
        document.blocks[indexPath.row] = block
        onDocumentChange?(document)
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
    private func applyInlineFormat(at indexPath: IndexPath, prefix: String, suffix: String) {
        guard let cell = tableView.cellForRow(at: indexPath) as? TextBlockCell else { return }
        guard let range = activeTextSelectionRange, range.length > 0 else {
            // No selection, insert placeholder
            cell.insertInlineFormat(prefix: prefix, suffix: suffix, selectedRange: nil)
            return
        }
        cell.insertInlineFormat(prefix: prefix, suffix: suffix, selectedRange: range)
    }

    private func firstVisibleTextIndexPath() -> IndexPath? {
        return tableView.indexPathsForVisibleRows?.first
    }
    
    private func setupNavigationBar() {
        let addAttachmentItem = UIBarButtonItem(image: UIImage(systemName: "paperclip"), style: .plain, target: self, action: #selector(attachmentButtonTapped))
        navigationItem.rightBarButtonItem = addAttachmentItem
    }
    
    @objc private func attachmentButtonTapped() {
        presentAttachmentPicker()
    }
    
    private func presentAttachmentPicker() {
        let alert = UIAlertController(title: "插入附件", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "图片", style: .default) { _ in
            self.presentImagePicker()
        })
        alert.addAction(UIAlertAction(title: "PDF / 文件", style: .default) { _ in
            self.presentDocumentPicker()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
    
    private func presentImagePicker() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        present(picker, animated: true)
    }
    
    private func presentDocumentPicker() {
        let types: [UTType] = [.pdf, .image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    private func insertAttachment(data: Data, type: AttachmentType, fileName: String) {
        let indexPath = activeIndexPath ?? tableView.indexPathForSelectedRow ?? IndexPath(row: document.blocks.count, section: 0)
        let safeRow = min(indexPath.row, document.blocks.count)
        
        // Create attachment block
        let attachmentBlock: Block
        let attachmentId = UUID()
        
        // If we have context, use the new storage system
        if let context = modelContext, let ownerId = ownerId, let noteId = noteId {
            // Save to local cache immediately for display (using AttachmentCache directly)
            AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName)
            
            // Create LocalAttachment record async
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
                    // Upload immediately so other devices can fetch it without waiting for sync.
                    await AttachmentStorage.shared.uploadAndUpsertMetadata(
                        attachment: localAttachment,
                        context: context
                    )
                } catch {
                    print("Failed to save attachment record: \(error)")
                }
            }
            
            // Create block with storage path reference
            let ext = (fileName as NSString).pathExtension
            let storageName = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
            let storagePath = "\(ownerId.uuidString)/\(storageName)"
            attachmentBlock = Block.attachment(type: type, fileName: fileName, storagePath: storagePath, attachmentId: attachmentId)
        } else {
            // Fallback: use legacy embedded data (for when context is not available)
            attachmentBlock = Block.attachment(type: type, fileName: fileName, data: data)
        }
        
        if safeRow < document.blocks.count {
            let current = document.blocks[safeRow]
            if current.kind != .table && current.kind != .attachment {
                let cursorLocation = activeTextSelectionRange?.location ?? current.text.count
                let safeLocation = min(max(0, cursorLocation), current.text.count)
                let prefix = String(current.text.prefix(safeLocation))
                let suffix = String(current.text.dropFirst(safeLocation))
                
                // Update current block with text before cursor
                document.blocks[safeRow].text = prefix
                
                // Insert attachment after current block
                let attachmentIndex = safeRow + 1
                document.blocks.insert(attachmentBlock, at: attachmentIndex)
                
                // Insert text after cursor as a new block
                if !suffix.isEmpty {
                    let newKind: BlockKind = current.kind == .heading ? .paragraph : current.kind
                    let newBlock = Block(
                        id: UUID(),
                        kind: newKind,
                        text: suffix,
                        level: current.level,
                        isChecked: newKind == .todo ? false : current.isChecked,
                        table: nil,
                        attachment: nil,
                        fontSizeOffset: current.fontSizeOffset
                    )
                    document.blocks.insert(newBlock, at: attachmentIndex + 1)
                } else {
                    document.blocks.insert(Block.paragraph(""), at: attachmentIndex + 1)
                }
                
                onDocumentChange?(document)
                tableView.reloadData()
                
                let attachmentIndexPath = IndexPath(row: attachmentIndex, section: 0)
                DispatchQueue.main.async {
                    self.tableView.scrollToRow(at: attachmentIndexPath, at: .middle, animated: true)
                }
                return
            }
        }
        
        // Fallback: insert at current row
        document.blocks.insert(attachmentBlock, at: safeRow)
        document.blocks.insert(Block.paragraph(""), at: safeRow + 1)
        onDocumentChange?(document)
        tableView.reloadData()
        let attachmentIndexPath = IndexPath(row: safeRow, section: 0)
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: attachmentIndexPath, at: .middle, animated: true)
        }
    }
    
    func moveBlock(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex else { return }
        guard sourceIndex >= 0, sourceIndex < document.blocks.count else { return }
        guard destinationIndex >= 0, destinationIndex <= document.blocks.count else { return }
        
        let block = document.blocks.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        document.blocks.insert(block, at: adjustedDestination)
        
        onDocumentChange?(document)
        tableView.reloadData()
        Haptics.shared.play(.success)
    }
}

extension BlockEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        document.blocks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let block = document.blocks[indexPath.row]
        switch block.kind {
        case .table:
            let cell = tableView.dequeueReusableCell(withIdentifier: TableBlockCell.reuseIdentifier, for: indexPath) as! TableBlockCell
            cell.delegate = self
            cell.configure(with: block.table ?? TableModel(rows: 3, cols: 3), blockId: block.id)
            cell.setMultiSelected(isMultiSelecting && multiSelectedBlockIds.contains(block.id))
            cell.setContentInteractionEnabled(!isMultiSelecting)
            cell.setControlsVisible(!isMultiSelecting && activeTableIndexPath == indexPath)
            cell.setSentHighlight(sentHighlightBlockIds.contains(block.id))
            return cell
        case .attachment:
            let cell = tableView.dequeueReusableCell(withIdentifier: AttachmentBlockCell.reuseIdentifier, for: indexPath) as! AttachmentBlockCell
            cell.delegate = self
            cell.configure(with: block)
            cell.setMultiSelected(isMultiSelecting && multiSelectedBlockIds.contains(block.id))
            cell.setSentHighlight(sentHighlightBlockIds.contains(block.id))
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextBlockCell.reuseIdentifier, for: indexPath) as! TextBlockCell
            cell.delegate = self
            let numberIndex = numberIndexForBlock(at: indexPath.row)
            cell.configure(with: block, numberIndex: numberIndex)
            cell.setMultiSelected(isMultiSelecting && multiSelectedBlockIds.contains(block.id))
            cell.setContentInteractionEnabled(!isMultiSelecting)
            cell.setSentHighlight(sentHighlightBlockIds.contains(block.id))
            return cell
        }
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
}

extension BlockEditorViewController: TextBlockCellDelegate {
    func textBlockCellDidChange(_ cell: TextBlockCell, text: String) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        document.blocks[indexPath.row].text = text
        onDocumentChange?(document)
    }

    func textBlockCellDidRequestNewBlock(_ cell: TextBlockCell, splitAtLocation location: Int) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let current = document.blocks[indexPath.row]
        
        // If the block is empty and it's a list type, pressing enter converts it to a paragraph (exiting the list)
        if current.text.isEmpty {
            if current.kind == .bullet || current.kind == .numbered || current.kind == .todo || current.kind == .quote {
                document.blocks[indexPath.row].kind = .paragraph
                onDocumentChange?(document)
                tableView.reloadRows(at: [indexPath], with: .none)
                return
            }
        }
        
        // Split the text
        let fullText = current.text
        let safeLocation = min(max(0, location), fullText.count)
        
        let prefix = String(fullText.prefix(safeLocation))
        let suffix = String(fullText.dropFirst(safeLocation))
        
        // Update current block
        document.blocks[indexPath.row].text = prefix
        
        // Determine new block kind
        let newKind: BlockKind
        if current.kind == .heading {
            newKind = .paragraph
        } else {
            newKind = (current.kind == .bullet || current.kind == .numbered || current.kind == .todo || current.kind == .quote) ? current.kind : .paragraph
        }
        
        let newBlock = Block(id: UUID(), kind: newKind, text: suffix, level: nil, isChecked: false, table: nil, attachment: nil, fontSizeOffset: current.fontSizeOffset)
        document.blocks.insert(newBlock, at: indexPath.row + 1)
        onDocumentChange?(document)
        
        // Update UI as a single batch to keep row counts consistent
        let newIndexPath = IndexPath(row: indexPath.row + 1, section: 0)
        tableView.performBatchUpdates {
            tableView.reloadRows(at: [indexPath], with: .none)
            tableView.insertRows(at: [newIndexPath], with: .automatic)
        }
        
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: newIndexPath, at: .none, animated: true)
            if let newCell = self.tableView.cellForRow(at: newIndexPath) as? TextBlockCell {
                newCell.beginEditing()
            }
        }
    }

    func textBlockCellDidTrigger(_ cell: TextBlockCell, trigger: MarkdownTrigger) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        var block = document.blocks[indexPath.row]
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
            document.blocks[indexPath.row] = block
            document.blocks.insert(Block.paragraph(""), at: indexPath.row + 1)
            onDocumentChange?(document)
            tableView.reloadData()
            let nextIndex = IndexPath(row: indexPath.row + 1, section: 0)
            DispatchQueue.main.async {
                self.tableView.scrollToRow(at: nextIndex, at: .none, animated: true)
                (self.tableView.cellForRow(at: nextIndex) as? TextBlockCell)?.beginEditing()
            }
            return
        case .attachment(let type, let data, let fileName):
            block = Block.attachment(type: type, fileName: fileName, data: data)
            document.blocks[indexPath.row] = block
            document.blocks.insert(Block.paragraph(""), at: indexPath.row + 1)
            onDocumentChange?(document)
            tableView.reloadData()
            let nextIndex = IndexPath(row: indexPath.row + 1, section: 0)
            DispatchQueue.main.async {
                self.tableView.scrollToRow(at: nextIndex, at: .none, animated: true)
                (self.tableView.cellForRow(at: nextIndex) as? TextBlockCell)?.beginEditing()
            }
            return
        }
        document.blocks[indexPath.row] = block
        onDocumentChange?(document)
        tableView.reloadRows(at: [indexPath], with: .none)
        DispatchQueue.main.async {
            (self.tableView.cellForRow(at: indexPath) as? TextBlockCell)?.beginEditing()
        }
    }

    func textBlockCellSelectionDidChange(_ cell: TextBlockCell, selectedText: String, range: NSRange) {
        if isMultiSelecting {
            return
        }
        activeIndexPath = tableView.indexPath(for: cell)
        activeTextSelectionRange = range
        onSelectionChange?(selectedText, range)
        if selectedText.isEmpty {
            onSelectedBlockIdsChange?([])
        } else {
            onSelectedBlockIdsChange?([cell.blockIdentifier()])
        }
    }
    
    func textBlockCellDidRequestCommand(_ cell: TextBlockCell, command: EditorCommand) {
        activeIndexPath = tableView.indexPath(for: cell)
        apply(command: command)
    }

    func textBlockCellDidRequestBackspaceAtStart(_ cell: TextBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        if indexPath.row == 0 {
            titleFocusBridge?.requestFocus = true
            return
        }
        let previousIndex = IndexPath(row: indexPath.row - 1, section: 0)
        let currentText = document.blocks[indexPath.row].text
        let previousText = document.blocks[previousIndex.row].text
        document.blocks[previousIndex.row].text = previousText + currentText
        document.blocks.remove(at: indexPath.row)
        onDocumentChange?(document)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        tableView.reloadRows(at: [previousIndex], with: .none)
        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: previousIndex, at: .none, animated: true)
            (self.tableView.cellForRow(at: previousIndex) as? TextBlockCell)?.beginEditing(atEnd: true)
        }
    }

    func textBlockCellDidToggleTodo(_ cell: TextBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        guard indexPath.row < document.blocks.count else { return }
        guard document.blocks[indexPath.row].kind == .todo else { return }
        let current = document.blocks[indexPath.row].isChecked ?? false
        document.blocks[indexPath.row].isChecked = !current
        onDocumentChange?(document)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    func textBlockCellDidRequestLayoutUpdate(_ cell: TextBlockCell) {
        // Trigger tableView to recalculate cell height without animation
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }
    
}

extension BlockEditorViewController: TableBlockCellDelegate {
    func tableBlockCellDidChange(_ cell: TableBlockCell, table: TableModel) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        document.blocks[indexPath.row].table = table
        onDocumentChange?(document)
    }

    func tableBlockCellDidRequestAddRow(_ cell: TableBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let focus = cell.currentEditingPosition()
        var table = document.blocks[indexPath.row].table ?? TableModel(rows: 3, cols: 3)
        table.addRow()
        document.blocks[indexPath.row].table = table
        onDocumentChange?(document)
        tableView.reloadRows(at: [indexPath], with: .none)
        restoreTableFocusIfNeeded(indexPath: indexPath, focus: focus)
    }

    func tableBlockCellDidRequestRemoveRow(_ cell: TableBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let focus = cell.currentEditingPosition()
        var table = document.blocks[indexPath.row].table ?? TableModel(rows: 3, cols: 3)
        table.removeRow()
        document.blocks[indexPath.row].table = table
        onDocumentChange?(document)
        tableView.reloadRows(at: [indexPath], with: .none)
        restoreTableFocusIfNeeded(indexPath: indexPath, focus: focus)
    }

    func tableBlockCellDidRequestAddColumn(_ cell: TableBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let focus = cell.currentEditingPosition()
        var table = document.blocks[indexPath.row].table ?? TableModel(rows: 3, cols: 3)
        table.addColumn()
        document.blocks[indexPath.row].table = table
        onDocumentChange?(document)
        tableView.reloadRows(at: [indexPath], with: .none)
        restoreTableFocusIfNeeded(indexPath: indexPath, focus: focus)
    }

    func tableBlockCellDidRequestRemoveColumn(_ cell: TableBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let focus = cell.currentEditingPosition()
        var table = document.blocks[indexPath.row].table ?? TableModel(rows: 3, cols: 3)
        table.removeColumn()
        document.blocks[indexPath.row].table = table
        onDocumentChange?(document)
        tableView.reloadRows(at: [indexPath], with: .none)
        restoreTableFocusIfNeeded(indexPath: indexPath, focus: focus)
    }

    func tableBlockCellDidRequestDeleteTable(_ cell: TableBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        guard indexPath.row < document.blocks.count else { return }

        view.endEditing(true)
        document.blocks.remove(at: indexPath.row)
        if document.blocks.isEmpty {
            document.blocks.append(.paragraph(""))
        }
        activeTableIndexPath = nil
        activeIndexPath = nil
        onDocumentChange?(document)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        let targetRow = min(indexPath.row, document.blocks.count - 1)
        let targetIndexPath = IndexPath(row: targetRow, section: 0)
        DispatchQueue.main.async {
            if let textCell = self.tableView.cellForRow(at: targetIndexPath) as? TextBlockCell {
                textCell.beginEditing()
            } else if let tableCell = self.tableView.cellForRow(at: targetIndexPath) as? TableBlockCell {
                tableCell.setControlsVisible(true)
                self.activeTableIndexPath = targetIndexPath
            }
        }
    }

    func tableBlockCellDidBeginEditing(_ cell: TableBlockCell) {
        guard !isMultiSelecting else { return }
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        let previous = activeTableIndexPath
        activeTableIndexPath = indexPath
        activeIndexPath = indexPath
        if let prev = previous, prev != indexPath, let prevCell = tableView.cellForRow(at: prev) as? TableBlockCell {
            prevCell.setControlsVisible(false)
        }
        cell.setControlsVisible(true)
        refreshTableLayoutForControls()
        onSelectedBlockIdsChange?([cell.blockIdentifier()])
    }

    func tableBlockCellDidEndEditing(_ cell: TableBlockCell) {
        guard !isMultiSelecting else { return }
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        if activeTableIndexPath == indexPath {
            activeTableIndexPath = nil
            cell.setControlsVisible(false)
            refreshTableLayoutForControls()
            onSelectedBlockIdsChange?([])
        }
    }
}

extension BlockEditorViewController {
    @objc private func handleTableDismissTap(_ gesture: UITapGestureRecognizer) {
        guard !isMultiSelecting else { return }
        guard activeTableIndexPath != nil else { return }
        let point = gesture.location(in: tableView)
        if let hit = tableView.hitTest(point, with: nil) {
            if hit is UITextView || hit is UIControl {
                return
            }
        }
        view.endEditing(true)
        hideActiveTableControls()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === tableDismissTap {
            if isMultiSelecting {
                return false
            }
            let point = touch.location(in: tableView)
            if let hit = tableView.hitTest(point, with: nil) {
                if hit is UITextView || hit is UIControl {
                    return false
                }
            }
            return activeTableIndexPath != nil
        }
        return true
    }

    @objc func handleMultiSelectLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point), indexPath.row < document.blocks.count else { return }

        if !isMultiSelecting {
            Haptics.shared.play(.long(duration: 0.2, intensity: 0.85, sharpness: 0.6))
            enterMultiSelectMode()
        }
        Haptics.shared.play(.selection)
        toggleMultiSelectedBlock(at: indexPath)
    }

    @objc func handleMultiSelectTap(_ gesture: UITapGestureRecognizer) {
        guard isMultiSelecting else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point), indexPath.row < document.blocks.count else { return }
        Haptics.shared.play(.selection)
        toggleMultiSelectedBlock(at: indexPath)
    }

    private func enterMultiSelectMode() {
        isMultiSelecting = true
        multiSelectTap.isEnabled = true
        view.endEditing(true)
        hideActiveTableControls()
        tableView.reloadData()
    }

    func exitMultiSelectMode() {
        isMultiSelecting = false
        multiSelectedBlockIds.removeAll()
        multiSelectTap.isEnabled = false
        activeTableIndexPath = nil
        tableView.reloadData()
        onSelectionChange?("", NSRange(location: 0, length: 0))
        onSelectedBlockIdsChange?([])
    }

    private func toggleMultiSelectedBlock(at indexPath: IndexPath) {
        let blockId = document.blocks[indexPath.row].id
        if multiSelectedBlockIds.contains(blockId) {
            multiSelectedBlockIds.remove(blockId)
        } else {
            multiSelectedBlockIds.insert(blockId)
        }

        if multiSelectedBlockIds.isEmpty {
            exitMultiSelectMode()
        } else {
            notifyMultiSelectionChanged()
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    private func notifyMultiSelectionChanged() {
        let text = document.blocks
            .filter { multiSelectedBlockIds.contains($0.id) }
            .map { $0.plainText }
            .joined(separator: "\n\n")
        onSelectionChange?(text, NSRange(location: 0, length: (text as NSString).length))
        onSelectedBlockIdsChange?(Array(multiSelectedBlockIds))
    }

    private func hideActiveTableControls() {
        if let active = activeTableIndexPath, let cell = tableView.cellForRow(at: active) as? TableBlockCell {
            cell.setControlsVisible(false)
        }
        activeTableIndexPath = nil
        refreshTableLayoutForControls()
    }

    private func restoreTableFocusIfNeeded(indexPath: IndexPath, focus: (row: Int, col: Int)?) {
        guard let focus = focus else { return }
        DispatchQueue.main.async {
            guard let cell = self.tableView.cellForRow(at: indexPath) as? TableBlockCell else { return }
            let size = cell.tableSize()
            let row = min(focus.row, max(size.rows - 1, 0))
            let col = min(focus.col, max(size.cols - 1, 0))
            cell.setControlsVisible(!self.isMultiSelecting)
            self.activeTableIndexPath = indexPath
            self.refreshTableLayoutForControls()
            cell.focusCell(row: row, col: col)
        }
    }

    private func refreshTableLayoutForControls() {
        UIView.performWithoutAnimation {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        }
    }

    func pruneMultiSelection() {
        let validIds = Set(document.blocks.map { $0.id })
        multiSelectedBlockIds = multiSelectedBlockIds.intersection(validIds)
        if multiSelectedBlockIds.isEmpty {
            exitMultiSelectMode()
        }
    }

}

extension BlockEditorViewController: AttachmentBlockCellDelegate {
    func attachmentBlockCellDidRequestDelete(_ cell: AttachmentBlockCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        
        UIView.animate(withDuration: 0.2) {
            cell.alpha = 0
            cell.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } completion: { _ in
            self.document.blocks.remove(at: indexPath.row)
            self.onDocumentChange?(self.document)
            self.tableView.deleteRows(at: [indexPath], with: .fade)
            Haptics.shared.play(.warning)
        }
    }
    
    func attachmentBlockCellDidRequestPreview(_ cell: AttachmentBlockCell, attachmentId: UUID, data: Data, fileName: String, type: AttachmentType) {
        let previewController = AttachmentPreviewViewController(
            attachmentId: attachmentId,
            data: data,
            fileName: fileName,
            type: type,
            onDelete: { [weak self] attachmentId in
                self?.deleteAttachment(withId: attachmentId)
            },
            onClose: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        previewController.modalPresentationStyle = .fullScreen
        present(previewController, animated: true)
    }
    
    func attachmentBlockCellDidBeginDragging(_ cell: AttachmentBlockCell, locationInWindow: CGPoint) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        draggingSourceIndexPath = indexPath
        ensureDropIndicator()
        updateDropIndicator(for: locationInWindow, sourceIndexPath: indexPath)
    }
    
    func attachmentBlockCellDidDrag(_ cell: AttachmentBlockCell, locationInWindow: CGPoint) {
        guard let sourceIndexPath = draggingSourceIndexPath else { return }
        updateDropIndicator(for: locationInWindow, sourceIndexPath: sourceIndexPath)
    }
    
    func attachmentBlockCellDidEndDragging(_ cell: AttachmentBlockCell, locationInWindow: CGPoint) {
        guard let sourceIndexPath = draggingSourceIndexPath else { return }
        let destinationRow = dropTargetRow(for: locationInWindow)
        if destinationRow != sourceIndexPath.row {
            moveBlock(from: sourceIndexPath.row, to: destinationRow)
        }
        hideDropIndicator()
        draggingSourceIndexPath = nil
    }
    
    private func ensureDropIndicator() {
        if dropIndicatorView == nil {
            let indicator = UIView()
            indicator.backgroundColor = UIColor.systemBlue
            indicator.layer.cornerRadius = 2
            indicator.alpha = 0
            tableView.addSubview(indicator)
            dropIndicatorView = indicator
        }
    }
    
    private func dropTargetRow(for locationInWindow: CGPoint) -> Int {
        let location = tableView.convert(locationInWindow, from: nil)
        if let destinationIndexPath = tableView.indexPathForRow(at: location) {
            return destinationIndexPath.row
        }
        if location.y < 0 { return 0 }
        return max(0, document.blocks.count - 1)
    }
    
    private func updateDropIndicator(for locationInWindow: CGPoint, sourceIndexPath: IndexPath) {
        guard let indicator = dropIndicatorView else { return }
        let location = tableView.convert(locationInWindow, from: nil)
        let targetRow = dropTargetRow(for: locationInWindow)
        let targetIndexPath = IndexPath(row: targetRow, section: 0)
        let cellRect = tableView.rectForRow(at: targetIndexPath)
        
        let isAboveSource = targetIndexPath.row <= sourceIndexPath.row
        let yPosition = isAboveSource ? cellRect.minY : cellRect.maxY
        
        let indicatorFrame = CGRect(
            x: 16,
            y: yPosition - 2,
            width: tableView.bounds.width - 32,
            height: 4
        )
        
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
            indicator.frame = indicatorFrame
            indicator.alpha = 1
        }
        
        if location.y < 80 {
            tableView.setContentOffset(CGPoint(x: 0, y: max(0, tableView.contentOffset.y - 12)), animated: false)
        } else if location.y > tableView.bounds.height - 80 {
            tableView.setContentOffset(CGPoint(x: 0, y: min(tableView.contentSize.height - tableView.bounds.height, tableView.contentOffset.y + 12)), animated: false)
        }
    }
    
    private func hideDropIndicator() {
        UIView.animate(withDuration: 0.2) {
            self.dropIndicatorView?.alpha = 0
        }
    }

    private func deleteAttachment(withId attachmentId: UUID) {
        guard let index = document.blocks.firstIndex(where: { $0.id == attachmentId }) else { return }
        document.blocks.remove(at: index)
        onDocumentChange?(document)
        tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
        Haptics.shared.play(.warning)
    }
}

extension BlockEditorViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let fileName = "Image_\(Date().timeIntervalSince1970).jpg"
        insertAttachment(data: data, type: .image, fileName: fileName)
    }
}

extension BlockEditorViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        // Start accessing security scoped resource
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let type: AttachmentType = url.pathExtension.lowercased() == "pdf" ? .pdf : .image
            insertAttachment(data: data, type: type, fileName: fileName)
        } catch {
            print("Failed to read document data: \(error)")
        }
    }
}
#endif
