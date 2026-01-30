import Foundation
#if os(macOS)
import AppKit

// MARK: - Table Block Cell Delegate

protocol TableBlockCellViewMacDelegate: AnyObject {
    func tableBlockCellDidChange(_ cell: TableBlockCellViewMac, table: TableModel)
    func tableBlockCellDidRequestDelete(_ cell: TableBlockCellViewMac)
}

// MARK: - Table Block Cell View

final class TableBlockCellViewMac: NSView, BlockCellViewMac, NSTextFieldDelegate {
    weak var delegate: TableBlockCellViewMacDelegate?
    
    private let containerView = NSView()
    private let gridView = NSGridView()
    private let controlsStack = NSStackView()
    private let addRowButton = NSButton()
    private let removeRowButton = NSButton()
    private let addColButton = NSButton()
    private let removeColButton = NSButton()
    private let deleteButton = NSButton()
    private let highlightBackgroundView = NSView()
    
    private var blockId: UUID = UUID()
    private var table: TableModel = TableModel(rows: 3, cols: 3)
    private var cellTextFields: [[NSTextField]] = []
    private var isSentHighlighted: Bool = false
    private var showControls: Bool = false
    
    // MARK: - Colors
    
    private var borderColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.3, alpha: 1.0) :
                NSColor(white: 0.85, alpha: 1.0)
        }
    }
    
    private var headerBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.18, alpha: 1.0) :
                NSColor(white: 0.95, alpha: 1.0)
        }
    }
    
    private var sentHighlightColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.3, green: 0.25, blue: 0.05, alpha: 1.0) :
                NSColor(red: 1.0, green: 0.95, blue: 0.64, alpha: 1.0)
        }
    }
    
    // MARK: - Init
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        wantsLayer = true
        
        // Highlight background
        highlightBackgroundView.wantsLayer = true
        highlightBackgroundView.layer?.backgroundColor = sentHighlightColor.cgColor
        highlightBackgroundView.layer?.cornerRadius = 12
        highlightBackgroundView.isHidden = true
        highlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightBackgroundView)
        
        // Container
        containerView.wantsLayer = true
        containerView.layer?.borderColor = borderColor.cgColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.cornerRadius = 8
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        
        // Grid view
        gridView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(gridView)
        
        // Controls stack
        setupControls()
        
        NSLayoutConstraint.activate([
            highlightBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlightBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            highlightBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            highlightBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            
            gridView.topAnchor.constraint(equalTo: containerView.topAnchor),
            gridView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            controlsStack.topAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 8),
            controlsStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
    
    private func setupControls() {
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 8
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controlsStack)
        
        // Add row button
        addRowButton.bezelStyle = .rounded
        addRowButton.title = "+ 行"
        addRowButton.target = self
        addRowButton.action = #selector(addRowTapped)
        controlsStack.addArrangedSubview(addRowButton)
        
        // Remove row button
        removeRowButton.bezelStyle = .rounded
        removeRowButton.title = "- 行"
        removeRowButton.target = self
        removeRowButton.action = #selector(removeRowTapped)
        controlsStack.addArrangedSubview(removeRowButton)
        
        // Add column button
        addColButton.bezelStyle = .rounded
        addColButton.title = "+ 列"
        addColButton.target = self
        addColButton.action = #selector(addColTapped)
        controlsStack.addArrangedSubview(addColButton)
        
        // Remove column button
        removeColButton.bezelStyle = .rounded
        removeColButton.title = "- 列"
        removeColButton.target = self
        removeColButton.action = #selector(removeColTapped)
        controlsStack.addArrangedSubview(removeColButton)
        
        // Spacer
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlsStack.addArrangedSubview(spacer)
        
        // Delete button
        deleteButton.bezelStyle = .rounded
        deleteButton.title = "删除表格"
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        controlsStack.addArrangedSubview(deleteButton)
        
        controlsStack.isHidden = !showControls
    }
    
    // MARK: - Configuration
    
    func configure(with table: TableModel, blockId: UUID) {
        self.blockId = blockId
        self.table = table
        rebuildGrid()
    }
    
    func setControlsVisible(_ visible: Bool) {
        showControls = visible
        controlsStack.isHidden = !visible
    }
    
    private func rebuildGrid() {
        // Remove existing cells
        gridView.subviews.forEach { $0.removeFromSuperview() }
        cellTextFields.removeAll()
        
        // Rebuild grid
        for row in 0..<table.rows {
            var rowFields: [NSTextField] = []
            
            for col in 0..<table.cols {
                let textField = NSTextField()
                textField.isBordered = true
                textField.bezelStyle = .squareBezel
                textField.font = NSFont.systemFont(ofSize: 13)
                textField.stringValue = table.cells[row][col]
                textField.delegate = self
                textField.tag = row * 1000 + col // Encode position in tag
                textField.placeholderString = row == 0 ? "标题" : ""
                
                // Header row styling
                if row == 0 {
                    textField.backgroundColor = headerBackgroundColor
                    textField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
                }
                
                NSLayoutConstraint.activate([
                    textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
                    textField.heightAnchor.constraint(equalToConstant: 28)
                ])
                
                rowFields.append(textField)
            }
            
            cellTextFields.append(rowFields)
            gridView.addRow(with: rowFields)
        }
        
        gridView.rowSpacing = 0
        gridView.columnSpacing = 0
        
        needsLayout = true
    }
    
    // MARK: - NSTextFieldDelegate
    
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        let row = textField.tag / 1000
        let col = textField.tag % 1000
        
        if row < table.rows && col < table.cols {
            table.cells[row][col] = textField.stringValue
            delegate?.tableBlockCellDidChange(self, table: table)
        }
    }
    
    // MARK: - Actions
    
    @objc private func addRowTapped() {
        table.addRow()
        rebuildGrid()
        delegate?.tableBlockCellDidChange(self, table: table)
    }
    
    @objc private func removeRowTapped() {
        table.removeRow()
        rebuildGrid()
        delegate?.tableBlockCellDidChange(self, table: table)
    }
    
    @objc private func addColTapped() {
        table.addColumn()
        rebuildGrid()
        delegate?.tableBlockCellDidChange(self, table: table)
    }
    
    @objc private func removeColTapped() {
        table.removeColumn()
        rebuildGrid()
        delegate?.tableBlockCellDidChange(self, table: table)
    }
    
    @objc private func deleteTapped() {
        delegate?.tableBlockCellDidRequestDelete(self)
    }
    
    // MARK: - BlockCellViewMac
    
    func setSentHighlight(_ highlighted: Bool) {
        isSentHighlighted = highlighted
        highlightBackgroundView.isHidden = !highlighted
    }
    
    func setMultiSelected(_ selected: Bool) {
        if selected {
            highlightBackgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
            highlightBackgroundView.isHidden = false
        } else if !isSentHighlighted {
            highlightBackgroundView.isHidden = true
        }
    }
    
    // MARK: - Layout
    
    override var intrinsicContentSize: NSSize {
        let rowHeight: CGFloat = 28
        let controlsHeight: CGFloat = showControls ? 40 : 0
        let totalHeight = CGFloat(table.rows) * rowHeight + 16 + controlsHeight
        return NSSize(width: NSView.noIntrinsicMetric, height: totalHeight)
    }
    
    // MARK: - Mouse Events
    
    override func mouseEntered(with event: NSEvent) {
        setControlsVisible(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        setControlsVisible(false)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}

#endif
