import Foundation
#if os(macOS)
import AppKit

// MARK: - Markdown Triggers (shared with iOS)

enum MarkdownTrigger {
    case heading(level: Int)
    case bullet
    case numbered
    case todo
    case quote
    case codeBlock
    case table
    case attachment(type: AttachmentType, data: Data, fileName: String)
}

// MARK: - Text Block Cell Delegate

protocol TextBlockCellViewMacDelegate: AnyObject {
    func textBlockCellDidChange(_ cell: TextBlockCellViewMac, text: String)
    func textBlockCellDidRequestNewBlock(_ cell: TextBlockCellViewMac, splitAtLocation location: Int)
    func textBlockCellSelectionDidChange(_ cell: TextBlockCellViewMac, selectedText: String, range: NSRange)
    func textBlockCellDidRequestBackspaceAtStart(_ cell: TextBlockCellViewMac)
    func textBlockCellDidToggleTodo(_ cell: TextBlockCellViewMac)
    func textBlockCellDidTrigger(_ cell: TextBlockCellViewMac, trigger: MarkdownTrigger)
}

// MARK: - Text Block Cell View

final class TextBlockCellViewMac: NSView, BlockCellViewMac, NSTextViewDelegate {
    weak var delegate: TextBlockCellViewMacDelegate?
    
    private let hStack = NSStackView()
    private let prefixLabel = NSTextField(labelWithString: "")
    private let checkboxButton = NSButton()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let quoteBorderView = NSView()
    private let highlightBackgroundView = NSView()
    
    private var kind: BlockKind = .paragraph
    private var blockId: UUID = UUID()
    private var numberIndex: Int = 1
    private var headingLevel: Int = 1
    private var todoChecked: Bool = false
    private var isSentHighlighted: Bool = false
    private var fontSizeOffset: CGFloat = 0
    private var lastRenderedText: String = ""
    private var isApplyingStyle: Bool = false
    
    // MARK: - Colors
    
    private var inkColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1) :
                NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        }
    }
    
    private var secondaryInkColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1) :
                NSColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
        }
    }
    
    private var codeBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.15, alpha: 1.0) :
                NSColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
        }
    }
    
    private var quoteBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.15, alpha: 1.0) :
                NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        }
    }
    
    private var quoteBorderColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.4, alpha: 1.0) :
                NSColor(white: 0.8, alpha: 1.0)
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
        highlightBackgroundView.layer?.cornerRadius = 8
        highlightBackgroundView.isHidden = true
        highlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightBackgroundView)
        
        // Quote border
        quoteBorderView.wantsLayer = true
        quoteBorderView.layer?.backgroundColor = quoteBorderColor.cgColor
        quoteBorderView.layer?.cornerRadius = 2
        quoteBorderView.isHidden = true
        quoteBorderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(quoteBorderView)
        
        // Horizontal stack
        hStack.orientation = .horizontal
        hStack.alignment = .top
        hStack.spacing = 8
        hStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hStack)
        
        // Prefix label
        prefixLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        prefixLabel.textColor = secondaryInkColor
        prefixLabel.alignment = .right
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        prefixLabel.isHidden = true
        
        // Checkbox button
        checkboxButton.setButtonType(.toggle)
        checkboxButton.bezelStyle = .regularSquare
        checkboxButton.isBordered = false
        checkboxButton.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        checkboxButton.alternateImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        checkboxButton.target = self
        checkboxButton.action = #selector(toggleCheckbox)
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.isHidden = true
        
        // Text view setup
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        textView.minSize = NSSize(width: 0, height: 24)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        textView.textColor = inkColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        
        scrollView.documentView = textView
        
        hStack.addArrangedSubview(prefixLabel)
        hStack.addArrangedSubview(checkboxButton)
        hStack.addArrangedSubview(scrollView)
        
        NSLayoutConstraint.activate([
            highlightBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlightBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            highlightBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            highlightBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            quoteBorderView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            quoteBorderView.topAnchor.constraint(equalTo: hStack.topAnchor, constant: 2),
            quoteBorderView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor, constant: -2),
            quoteBorderView.widthAnchor.constraint(equalToConstant: 4),
            
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            checkboxButton.widthAnchor.constraint(equalToConstant: 20),
            checkboxButton.heightAnchor.constraint(equalToConstant: 20),
            
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with block: Block, numberIndex: Int) {
        self.blockId = block.id
        self.kind = block.kind
        self.numberIndex = numberIndex
        self.headingLevel = block.level ?? 1
        self.todoChecked = block.isChecked ?? false
        self.fontSizeOffset = block.fontSizeOffset ?? 0
        
        // Update prefix visibility
        updatePrefixVisibility()
        
        // Update checkbox
        checkboxButton.isHidden = kind != .todo
        checkboxButton.state = todoChecked ? .on : .off
        
        // Update quote border
        quoteBorderView.isHidden = kind != .quote
        
        // Update text
        if textView.string != block.text {
            textView.string = block.text
        }
        
        // Apply styling
        applyTextStyle()
        
        // Update background for code blocks
        if kind == .code {
            wantsLayer = true
            layer?.backgroundColor = codeBackgroundColor.cgColor
            layer?.cornerRadius = 8
        } else if kind == .quote {
            wantsLayer = true
            layer?.backgroundColor = quoteBackgroundColor.cgColor
            layer?.cornerRadius = 8
        } else {
            layer?.backgroundColor = nil
        }
    }
    
    private func updatePrefixVisibility() {
        switch kind {
        case .bullet:
            prefixLabel.stringValue = "•"
            prefixLabel.isHidden = false
        case .numbered:
            prefixLabel.stringValue = "\(numberIndex)."
            prefixLabel.isHidden = false
        case .heading:
            prefixLabel.isHidden = true
        default:
            prefixLabel.isHidden = true
        }
    }
    
    private func applyTextStyle() {
        guard let textStorage = textView.textStorage else { return }
        isApplyingStyle = true
        defer { isApplyingStyle = false }
        
        let baseSize: CGFloat
        let weight: NSFont.Weight
        
        switch kind {
        case .heading:
            switch headingLevel {
            case 1: baseSize = 28; weight = .bold
            case 2: baseSize = 24; weight = .bold
            case 3: baseSize = 20; weight = .semibold
            default: baseSize = 18; weight = .semibold
            }
        case .code:
            baseSize = 14
            weight = .regular
        default:
            baseSize = 16
            weight = .regular
        }
        
        let fontSize = baseSize + fontSizeOffset
        let font: NSFont
        
        if kind == .code {
            font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        } else {
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        }
        
        let color = todoChecked ? secondaryInkColor : inkColor
        
        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: color
        ], range: range)
        
        // Apply inline markdown formatting
        applyInlineMarkdown(to: textStorage)
        
        textStorage.endEditing()
    }
    
    private func applyInlineMarkdown(to textStorage: NSTextStorage) {
        let text = textStorage.string
        
        // Bold: **text**
        let boldPattern = "\\*\\*(.+?)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let fullRange = match.range
                    textStorage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: textView.font?.pointSize ?? 16), range: fullRange)
                }
            }
        }
        
        // Italic: *text*
        let italicPattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"
        if let regex = try? NSRegularExpression(pattern: italicPattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let fullRange = match.range
                    if let currentFont = textStorage.attribute(.font, at: fullRange.location, effectiveRange: nil) as? NSFont {
                        let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                        textStorage.addAttribute(.font, value: italicFont, range: fullRange)
                    }
                }
            }
        }
        
        // Inline code: `text`
        let codePattern = "`(.+?)`"
        if let regex = try? NSRegularExpression(pattern: codePattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            for match in matches.reversed() {
                let fullRange = match.range
                textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: textView.font?.pointSize ?? 14, weight: .regular), range: fullRange)
                textStorage.addAttribute(.backgroundColor, value: codeBackgroundColor, range: fullRange)
            }
        }
    }
    
    // MARK: - Public Methods
    
    func blockIdentifier() -> UUID {
        return blockId
    }
    
    func beginEditing(atEnd: Bool = false) {
        window?.makeFirstResponder(textView)
        if atEnd {
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }
    
    func insertInlineFormat(prefix: String, suffix: String, selectedRange: NSRange?) {
        guard let range = selectedRange ?? textView.selectedRange() as NSRange? else { return }
        
        let currentText = textView.string
        let nsString = currentText as NSString
        
        if range.length > 0 {
            let selectedText = nsString.substring(with: range)
            let replacement = prefix + selectedText + suffix
            textView.replaceCharacters(in: range, with: replacement)
        } else {
            let replacement = prefix + suffix
            textView.replaceCharacters(in: range, with: replacement)
            let newPosition = range.location + prefix.count
            textView.setSelectedRange(NSRange(location: newPosition, length: 0))
        }
        
        delegate?.textBlockCellDidChange(self, text: textView.string)
    }
    
    func setSentHighlight(_ highlighted: Bool) {
        isSentHighlighted = highlighted
        highlightBackgroundView.isHidden = !highlighted
    }
    
    func setMultiSelected(_ selected: Bool) {
        // Multi-select visual feedback
        if selected {
            highlightBackgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
            highlightBackgroundView.isHidden = false
        } else if !isSentHighlighted {
            highlightBackgroundView.isHidden = true
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleCheckbox() {
        delegate?.textBlockCellDidToggleTodo(self)
    }
    
    // MARK: - NSTextViewDelegate
    
    func textDidChange(_ notification: Notification) {
        guard !isApplyingStyle else { return }
        let newText = textView.string
        
        // Check for markdown triggers
        if let trigger = checkForMarkdownTrigger(newText) {
            delegate?.textBlockCellDidTrigger(self, trigger: trigger)
            return
        }
        
        delegate?.textBlockCellDidChange(self, text: newText)
        applyTextStyle()
        
        // Trigger layout update
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
    
    func textViewDidChangeSelection(_ notification: Notification) {
        let range = textView.selectedRange()
        let selectedText: String
        if range.length > 0 {
            selectedText = (textView.string as NSString).substring(with: range)
        } else {
            selectedText = ""
        }
        delegate?.textBlockCellSelectionDidChange(self, selectedText: selectedText, range: range)
    }
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let cursorLocation = textView.selectedRange().location
            delegate?.textBlockCellDidRequestNewBlock(self, splitAtLocation: cursorLocation)
            return true
        }
        
        if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            let range = textView.selectedRange()
            if range.location == 0 && range.length == 0 {
                delegate?.textBlockCellDidRequestBackspaceAtStart(self)
                return true
            }
        }
        
        return false
    }
    
    private func checkForMarkdownTrigger(_ text: String) -> MarkdownTrigger? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Heading triggers
        if trimmed == "# " { return .heading(level: 1) }
        if trimmed == "## " { return .heading(level: 2) }
        if trimmed == "### " { return .heading(level: 3) }
        
        // List triggers
        if trimmed == "- " || trimmed == "* " { return .bullet }
        if trimmed == "1. " { return .numbered }
        if trimmed == "- [ ] " || trimmed == "[] " { return .todo }
        if trimmed == "> " { return .quote }
        if trimmed == "```" || trimmed == "``` " { return .codeBlock }
        if trimmed == "/table " || trimmed == "/table" { return .table }
        
        return nil
    }
    
    // MARK: - Layout
    
    override var intrinsicContentSize: NSSize {
        let textHeight = textView.intrinsicContentSize.height
        return NSSize(width: NSView.noIntrinsicMetric, height: max(32, textHeight + 8))
    }
}

#endif
