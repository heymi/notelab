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
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1) :
                UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        }
    }

    private var tableHeaderBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.15, alpha: 1.0) :
                UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        }
    }
    
    private var tableCellBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.1, alpha: 1.0) :
                UIColor.white
        }
    }
    
    private var gridBorderColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.3, alpha: 1.0) :
                UIColor(white: 0.85, alpha: 1.0)
        }
    }
    
    private var buttonBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.25, alpha: 0.8) :
                UIColor.white.withAlphaComponent(0.6)
        }
    }
    
    private var buttonTextColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.9, alpha: 0.8) :
                UIColor(white: 0.2, alpha: 0.8)
        }
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
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.3, green: 0.25, blue: 0.05, alpha: 1.0) :
                UIColor(red: 1.0, green: 0.95, blue: 0.64, alpha: 1.0)
        }
    }

    private func setupViews() {
        sentHighlightBackgroundView.backgroundColor = sentHighlightColor
        sentHighlightBackgroundView.layer.cornerRadius = 12
        sentHighlightBackgroundView.isHidden = true
        contentView.addSubview(sentHighlightBackgroundView)
        sentHighlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        multiSelectBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.06)
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
        gridStack.layer.cornerRadius = 8
        gridStack.clipsToBounds = true

        container.axis = .vertical
        container.spacing = 8
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
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    private func makeHeaderButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        button.setTitleColor(buttonTextColor, for: .normal)
        button.backgroundColor = buttonBackgroundColor
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
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
        let textView = UITextView()
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.tag = row * 1000 + col
        textView.text = tableModel.cells[safe: row]?[safe: col] ?? ""
        
        if row == 0 {
            textView.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            textView.backgroundColor = tableHeaderBackgroundColor
            textView.textColor = inkColor
        } else {
            textView.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            textView.backgroundColor = tableCellBackgroundColor
            textView.textColor = inkColor
        }
        textView.layer.cornerRadius = 0 // No corner radius for joined cells
        
        return textView
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

    func setContentInteractionEnabled(_ enabled: Bool) {
        addRowButton?.isEnabled = enabled
        addColButton?.isEnabled = enabled
        removeRowButton?.isEnabled = enabled
        removeColButton?.isEnabled = enabled
        deleteTableButton?.isEnabled = enabled
        addRowButton?.alpha = enabled ? 1.0 : 0.4
        addColButton?.alpha = enabled ? 1.0 : 0.4
        removeRowButton?.alpha = enabled ? 1.0 : 0.4
        removeColButton?.alpha = enabled ? 1.0 : 0.4
        deleteTableButton?.alpha = enabled ? 1.0 : 0.4
        if !enabled {
            setControlsVisible(false)
        }
        if enabled {
            updateControlAvailability()
        }
        for tv in cellTextViews {
            tv.isEditable = enabled
            tv.isSelectable = enabled
            tv.isUserInteractionEnabled = enabled
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let row = textView.tag / 1000
        let col = textView.tag % 1000
        if row < tableModel.rows, col < tableModel.cols {
            tableModel.cells[row][col] = textView.text
            delegate?.tableBlockCellDidChange(self, table: tableModel)
        }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
#endif