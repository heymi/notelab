import Foundation
#if canImport(UIKit)
import UIKit

protocol TableBlockCellDelegate: AnyObject {
    func tableBlockCellDidChange(_ cell: TableBlockCell, table: TableModel)
    func tableBlockCellDidRequestAddRow(_ cell: TableBlockCell)
    func tableBlockCellDidRequestRemoveRow(_ cell: TableBlockCell)
    func tableBlockCellDidRequestAddColumn(_ cell: TableBlockCell)
    func tableBlockCellDidRequestRemoveColumn(_ cell: TableBlockCell)
    func tableBlockCellDidRequestDeleteTable(_ cell: TableBlockCell)
    func tableBlockCellDidBeginEditing(_ cell: TableBlockCell)
    func tableBlockCellDidEndEditing(_ cell: TableBlockCell)
    func tableBlockCellDidRequestLayoutUpdate(_ cell: TableBlockCell)
}

final class TableBlockCell: UITableViewCell, UITextViewDelegate {
    static let reuseIdentifier = "TableBlockCell"

    weak var delegate: TableBlockCellDelegate?
    private var tableModel = TableModel(rows: 1, cols: 1)
    private let gridStack = UIStackView()
    private let headerStack = UIStackView()
    private let container = UIStackView()
    private let multiSelectBackgroundView = UIView()
    private let sentHighlightBackgroundView = UIView()
    private var addRowButton: UIButton?
    private var addColButton: UIButton?
    private var removeRowButton: UIButton?
    private var removeColButton: UIButton?
    private var deleteTableButton: UIButton?
    private var cellTextViews: [UITextView] = []
    private var currentEditingTag: Int?

    private var blockId: UUID = UUID()
    private var isMultiSelected: Bool = false
    private var isSentHighlighted: Bool = false

    private var controlsVisible: Bool = false

    private var inkColor: UIColor {
        .noteEditorInk
    }

    private var tableHeaderBackgroundColor: UIColor {
        .noteEditorPaperSoft
    }
    
    private var tableCellBackgroundColor: UIColor {
        .noteEditorPaper
    }
    
    private var gridBorderColor: UIColor {
        .noteEditorLine
    }
    
    private var buttonBackgroundColor: UIColor {
        .noteEditorPaperSoft
    }
    
    private var buttonTextColor: UIColor {
        .noteEditorAccentDeep
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var sentHighlightColor: UIColor {
        .noteEditorSelection
    }

    private func setupViews() {
        sentHighlightBackgroundView.backgroundColor = sentHighlightColor
        sentHighlightBackgroundView.layer.cornerRadius = 12
        sentHighlightBackgroundView.isHidden = true
        contentView.addSubview(sentHighlightBackgroundView)
        sentHighlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        multiSelectBackgroundView.backgroundColor = UIColor.noteEditorSelection
        multiSelectBackgroundView.layer.cornerRadius = 12
        multiSelectBackgroundView.isHidden = true
        contentView.addSubview(multiSelectBackgroundView)
        multiSelectBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 8
        let rowAdd = makeHeaderButton(title: "+ 行", action: #selector(addRowTapped))
        let rowRemove = makeHeaderButton(title: "- 行", action: #selector(removeRowTapped))
        let colAdd = makeHeaderButton(title: "+ 列", action: #selector(addColTapped))
        let colRemove = makeHeaderButton(title: "- 列", action: #selector(removeColTapped))
        let del = makeHeaderButton(title: "删除", action: #selector(deleteTableTapped))
        addRowButton = rowAdd
        removeRowButton = rowRemove
        addColButton = colAdd
        removeColButton = colRemove
        deleteTableButton = del
        headerStack.addArrangedSubview(rowAdd)
        headerStack.addArrangedSubview(rowRemove)
        headerStack.addArrangedSubview(colAdd)
        headerStack.addArrangedSubview(colRemove)
        headerStack.addArrangedSubview(del)
        headerStack.isHidden = true

        gridStack.axis = .vertical
        gridStack.spacing = 0 // Reduced from 6 to 0 for joined cells
        gridStack.backgroundColor = gridBorderColor // Border color for the grid
        gridStack.layer.borderWidth = 0.5
        gridStack.layer.borderColor = gridBorderColor.cgColor
        gridStack.layer.cornerRadius = 14
        gridStack.clipsToBounds = true

        container.axis = .vertical
        container.spacing = 8
        container.backgroundColor = UIColor.noteEditorPaperSoft.withAlphaComponent(0.42)
        container.layer.cornerRadius = 18
        container.layer.masksToBounds = true
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        container.addArrangedSubview(headerStack)
        container.addArrangedSubview(gridStack)
        contentView.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sentHighlightBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            sentHighlightBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            sentHighlightBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            sentHighlightBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            multiSelectBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            multiSelectBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            multiSelectBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            multiSelectBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24)
        ])
    }

    private func makeHeaderButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        button.setTitleColor(buttonTextColor, for: .normal)
        button.backgroundColor = buttonBackgroundColor
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    func configure(with table: TableModel, blockId: UUID) {
        tableModel = table
        self.blockId = blockId
        rebuildGrid()
        updateControlAvailability()
    }

    func tableSize() -> (rows: Int, cols: Int) {
        (tableModel.rows, tableModel.cols)
    }

    func currentEditingPosition() -> (row: Int, col: Int)? {
        guard let tag = currentEditingTag else { return nil }
        return (tag / 1000, tag % 1000)
    }

    func focusCell(row: Int, col: Int) {
        let tag = row * 1000 + col
        if let textView = cellTextViews.first(where: { $0.tag == tag }) {
            textView.becomeFirstResponder()
        }
    }

    func blockIdentifier() -> UUID {
        blockId
    }

    private func updateControlAvailability() {
        let canRemoveRow = tableModel.rows > 1
        let canRemoveCol = tableModel.cols > 1
        removeRowButton?.isEnabled = canRemoveRow
        removeColButton?.isEnabled = canRemoveCol
        removeRowButton?.alpha = canRemoveRow ? 1.0 : 0.35
        removeColButton?.alpha = canRemoveCol ? 1.0 : 0.35
    }

    private func rebuildGrid() {
        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cellTextViews.removeAll(keepingCapacity: true)
        for row in 0..<tableModel.rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 0.5 // Thin separator
            rowStack.backgroundColor = gridBorderColor // Separator color
            for col in 0..<tableModel.cols {
                let cellView = makeCellView(row: row, col: col)
                cellTextViews.append(cellView)
                rowStack.addArrangedSubview(cellView)
            }
            gridStack.addArrangedSubview(rowStack)
        }
    }

    private func makeCellView(row: Int, col: Int) -> UITextView {
        let textView = TableCellTextView()
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.tag = row * 1000 + col
        textView.text = tableModel.cells[safe: row]?[safe: col] ?? ""
        textView.onTab = { [weak self, weak textView] shift in
            guard let self, let textView else { return }
            self.moveFocus(from: textView, backwards: shift)
        }
        
        if row == 0 {
            textView.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            textView.backgroundColor = tableHeaderBackgroundColor
            textView.textColor = inkColor
        } else {
            textView.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            textView.backgroundColor = tableCellBackgroundColor
            textView.textColor = .noteEditorBody
        }
        textView.tintColor = .noteEditorAccentDeep
        textView.layer.cornerRadius = 0 // No corner radius for joined cells
        
        return textView
    }

    private func moveFocus(from textView: UITextView, backwards: Bool) {
        textViewDidChange(textView)
        let row = textView.tag / 1000
        let col = textView.tag % 1000
        let nextIndex = row * tableModel.cols + col + (backwards ? -1 : 1)
        if backwards, nextIndex < 0 {
            return
        }
        if nextIndex >= tableModel.rows * tableModel.cols {
            tableModel.addRow()
            rebuildGrid()
            delegate?.tableBlockCellDidChange(self, table: tableModel)
            delegate?.tableBlockCellDidRequestLayoutUpdate(self)
            DispatchQueue.main.async {
                self.focusCell(row: self.tableModel.rows - 1, col: 0)
            }
            return
        }
        focusCell(row: nextIndex / tableModel.cols, col: nextIndex % tableModel.cols)
    }

    func setControlsVisible(_ visible: Bool) {
        controlsVisible = visible
        headerStack.isHidden = !visible
    }

    func setMultiSelected(_ selected: Bool) {
        multiSelectBackgroundView.isHidden = !selected
        isMultiSelected = selected
        updateHighlightVisibility()
    }

    func setSentHighlight(_ highlighted: Bool) {
        isSentHighlighted = highlighted
        updateHighlightVisibility()
    }

    private func updateHighlightVisibility() {
        sentHighlightBackgroundView.isHidden = !isSentHighlighted || isMultiSelected
    }

    func setContentInteraction(editable: Bool, selectable: Bool) {
        addRowButton?.isEnabled = editable
        addColButton?.isEnabled = editable
        removeRowButton?.isEnabled = editable
        removeColButton?.isEnabled = editable
        deleteTableButton?.isEnabled = editable
        addRowButton?.alpha = editable ? 1.0 : 0.4
        addColButton?.alpha = editable ? 1.0 : 0.4
        removeRowButton?.alpha = editable ? 1.0 : 0.4
        removeColButton?.alpha = editable ? 1.0 : 0.4
        deleteTableButton?.alpha = editable ? 1.0 : 0.4
        if !editable {
            setControlsVisible(false)
        }
        if editable {
            updateControlAvailability()
        }
        for tv in cellTextViews {
            tv.isEditable = editable
            tv.isSelectable = selectable
            tv.isUserInteractionEnabled = editable || selectable
        }
    }

    func setContentInteractionEnabled(_ enabled: Bool) {
        setContentInteraction(editable: enabled, selectable: enabled)
    }

    func textViewDidChange(_ textView: UITextView) {
        let row = textView.tag / 1000
        let col = textView.tag % 1000
        if row < tableModel.rows, col < tableModel.cols {
            tableModel.cells[row][col] = textView.text
            delegate?.tableBlockCellDidChange(self, table: tableModel)
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\t" {
            moveFocus(from: textView, backwards: false)
            return false
        }
        return true
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        currentEditingTag = textView.tag
        delegate?.tableBlockCellDidBeginEditing(self)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        DispatchQueue.main.async {
            let anyActive = self.cellTextViews.contains(where: { $0.isFirstResponder })
            if !anyActive {
                self.currentEditingTag = nil
                self.delegate?.tableBlockCellDidEndEditing(self)
            }
        }
    }

    @objc private func addRowTapped() {
        Haptics.shared.play(.tap(.medium))
        delegate?.tableBlockCellDidRequestAddRow(self)
    }

    @objc private func removeRowTapped() {
        Haptics.shared.play(.tap(.medium))
        delegate?.tableBlockCellDidRequestRemoveRow(self)
    }

    @objc private func addColTapped() {
        Haptics.shared.play(.tap(.medium))
        delegate?.tableBlockCellDidRequestAddColumn(self)
    }

    @objc private func removeColTapped() {
        Haptics.shared.play(.tap(.medium))
        delegate?.tableBlockCellDidRequestRemoveColumn(self)
    }

    @objc private func deleteTableTapped() {
        Haptics.shared.play(.warning)
        delegate?.tableBlockCellDidRequestDeleteTable(self)
    }
}

private final class TableCellTextView: UITextView {
    var onTab: ((Bool) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handleShiftTab))
        ]
    }

    @objc private func handleTab() {
        onTab?(false)
    }

    @objc private func handleShiftTab() {
        onTab?(true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
#endif
