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
    private var scrollHeightConstraint: NSLayoutConstraint?
    
    private var kind: BlockKind = .paragraph
    private var blockId: UUID = UUID()
    private var numberIndex: Int = 1
    private var headingLevel: Int = 1
    private var todoChecked: Bool = false
    private var isSentHighlighted: Bool = false
    private var presentationMode: NoteDetailPresentationMode = .reading
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

    private var bodyColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.82, green: 0.84, blue: 0.84, alpha: 1) :
                NSColor(red: 0.25, green: 0.29, blue: 0.29, alpha: 1)
        }
    }

    private var accentColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.425, green: 0.760, blue: 0.700, alpha: 1) :
                NSColor(red: 0.290, green: 0.620, blue: 0.560, alpha: 1)
        }
    }

    private var accentDeepColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.610, green: 0.860, blue: 0.820, alpha: 1) :
                NSColor(red: 0.135, green: 0.335, blue: 0.345, alpha: 1)
        }
    }
    
    private var codeBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.165, green: 0.175, blue: 0.180, alpha: 1) :
                NSColor(red: 0.955, green: 0.958, blue: 0.930, alpha: 1)
        }
    }
    
    private var quoteBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.165, green: 0.175, blue: 0.180, alpha: 1) :
                NSColor(red: 0.955, green: 0.958, blue: 0.930, alpha: 1)
        }
    }
    
    private var quoteBorderColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.425, green: 0.760, blue: 0.700, alpha: 1) :
                NSColor(red: 0.290, green: 0.620, blue: 0.560, alpha: 1)
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
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
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
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        scrollView.documentView = textView
        
        hStack.addArrangedSubview(prefixLabel)
        hStack.addArrangedSubview(checkboxButton)
        hStack.addArrangedSubview(scrollView)
        
        let heightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 32)
        heightConstraint.priority = .defaultHigh
        scrollHeightConstraint = heightConstraint

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
            
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            heightConstraint
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with block: Block, numberIndex: Int, presentationMode: NoteDetailPresentationMode = .reading) {
        self.blockId = block.id
        self.kind = block.kind
        self.numberIndex = numberIndex
        self.headingLevel = block.level ?? 1
        self.todoChecked = block.isChecked ?? false
        self.presentationMode = presentationMode
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
        setContentInteraction(editable: presentationMode.isEditing, selectable: true)
        
        // Update background for code blocks
        if kind == .code {
            wantsLayer = true
            layer?.backgroundColor = codeBackgroundColor.cgColor
            layer?.cornerRadius = presentationMode.isEditing ? 8 : 18
            textView.textContainerInset = NSSize(width: presentationMode.isEditing ? 0 : 18, height: presentationMode.isEditing ? 4 : 16)
        } else if kind == .quote {
            wantsLayer = true
            layer?.backgroundColor = quoteBackgroundColor.cgColor
            layer?.cornerRadius = presentationMode.isEditing ? 8 : 18
            textView.textContainerInset = NSSize(width: presentationMode.isEditing ? 0 : 18, height: presentationMode.isEditing ? 4 : 16)
        } else {
            layer?.backgroundColor = nil
        }
        updateMeasuredHeight()
    }
    
    private func updatePrefixVisibility() {
        switch kind {
        case .bullet:
            prefixLabel.stringValue = "•"
            prefixLabel.textColor = accentColor
            prefixLabel.font = NSFont.systemFont(ofSize: 15 + fontSizeOffset, weight: .bold)
            prefixLabel.isHidden = false
        case .numbered:
            prefixLabel.stringValue = "\(numberIndex)."
            prefixLabel.textColor = accentDeepColor
            prefixLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 16.5 + fontSizeOffset, weight: .medium)
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

        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: presentationMode.isEditing ? 4 : 6)
        hStack.spacing = presentationMode.isEditing ? 8 : 11
        
        let baseSize: CGFloat
        let weight: NSFont.Weight
        let paragraphStyle = NSMutableParagraphStyle()
        
        switch kind {
        case .heading:
            switch headingLevel {
            case 1: baseSize = presentationMode.isEditing ? 28 : 31; weight = .bold
            case 2: baseSize = presentationMode.isEditing ? 24 : 23; weight = .bold
            case 3: baseSize = presentationMode.isEditing ? 20 : 19; weight = .semibold
            default: baseSize = 18; weight = .semibold
            }
            paragraphStyle.lineSpacing = headingLevel == 1 ? 2 : 4
            paragraphStyle.lineHeightMultiple = headingLevel == 1 ? 1.08 : 1.16
            paragraphStyle.paragraphSpacingBefore = headingLevel == 1 ? 16 : 12
            paragraphStyle.paragraphSpacing = headingLevel == 1 ? 8 : 6
        case .code:
            baseSize = presentationMode.isEditing ? 14 : 14.5
            weight = .regular
            paragraphStyle.lineSpacing = 4
            paragraphStyle.lineHeightMultiple = 1.38
            paragraphStyle.paragraphSpacing = 4
        default:
            baseSize = presentationMode.isEditing ? 16 : 17
            weight = .regular
            paragraphStyle.lineSpacing = presentationMode.isEditing ? 6 : 2.5
            paragraphStyle.lineHeightMultiple = presentationMode.isEditing ? 1.2 : 1.44
            paragraphStyle.paragraphSpacing = presentationMode.isEditing ? 0 : 7
        }
        
        let fontSize = baseSize + fontSizeOffset
        let font: NSFont
        
        if kind == .code {
            font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        } else if kind == .heading && !presentationMode.isEditing && headingLevel == 1 {
            font = NSFont(name: "STSongti-SC-Black", size: fontSize)
                ?? NSFont(name: "SongtiSC-Black", size: fontSize)
                ?? NSFont.systemFont(ofSize: fontSize, weight: weight)
        } else {
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        }
        
        let color = todoChecked ? secondaryInkColor : (presentationMode.isEditing || kind == .heading ? inkColor : bodyColor)
        
        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ], range: range)
        
        if !presentationMode.isEditing {
            applyInlineMarkdown(to: textStorage)
        }
        
        textStorage.endEditing()
        updateMeasuredHeight()
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
                    guard !containsInlineMarker((text as NSString).substring(with: match.range(at: 1))) else { continue }
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
                    guard !containsInlineMarker((text as NSString).substring(with: match.range(at: 1))) else { continue }
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
                guard match.numberOfRanges >= 2,
                      !containsInlineMarker((text as NSString).substring(with: match.range(at: 1))) else { continue }
                let fullRange = match.range
                textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: textView.font?.pointSize ?? 14, weight: .regular), range: fullRange)
                textStorage.addAttribute(.backgroundColor, value: codeBackgroundColor, range: fullRange)
            }
        }
    }

    private func containsInlineMarker(_ text: String) -> Bool {
        text.contains("**") || text.contains("*") || text.contains("`") || text.contains("==")
    }
    
    // MARK: - Public Methods
    
    func blockIdentifier() -> UUID {
        return blockId
    }
    
    func beginEditing(atEnd: Bool = false) {
        beginEditing(atUTF16Location: atEnd ? textView.string.utf16.count : 0)
    }

    func beginEditing(atUTF16Location location: Int) {
        window?.makeFirstResponder(textView)
        let clamped = min(max(0, location), textView.string.utf16.count)
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
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

    func setContentInteraction(editable: Bool, selectable: Bool) {
        textView.isEditable = editable
        textView.isSelectable = selectable
        checkboxButton.isEnabled = editable
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
        updateMeasuredHeight()
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

    override func layout() {
        super.layout()
        updateMeasuredHeight()
    }

    private func updateMeasuredHeight() {
        let nextHeight = max(24, measuredTextHeight())
        guard abs((scrollHeightConstraint?.constant ?? 0) - nextHeight) > 0.5 else { return }
        scrollHeightConstraint?.constant = nextHeight
        invalidateIntrinsicContentSize()
        superview?.invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func measuredTextHeight() -> CGFloat {
        let fallbackWidth = bounds.width > 0 ? bounds.width - 32 : 480
        let width = max(1, scrollView.bounds.width > 1 ? scrollView.bounds.width : fallbackWidth)
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return textView.intrinsicContentSize.height
        }
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return ceil(usedRect.height + textView.textContainerInset.height * 2)
    }
    
    override var intrinsicContentSize: NSSize {
        let textHeight = scrollHeightConstraint?.constant ?? measuredTextHeight()
        return NSSize(width: NSView.noIntrinsicMetric, height: max(32, textHeight + 8))
    }
}

#endif
