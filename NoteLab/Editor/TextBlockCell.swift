import Foundation
#if canImport(UIKit)
import UIKit

protocol TextBlockCellDelegate: AnyObject {
    func textBlockCellDidChange(_ cell: TextBlockCell, text: String)
    func textBlockCellDidRequestNewBlock(_ cell: TextBlockCell, splitAtLocation location: Int)
    func textBlockCellDidTrigger(_ cell: TextBlockCell, trigger: MarkdownTrigger)
    func textBlockCellSelectionDidChange(_ cell: TextBlockCell, selectedText: String, range: NSRange)
    func textBlockCellDidRequestBackspaceAtStart(_ cell: TextBlockCell)
    func textBlockCellDidToggleTodo(_ cell: TextBlockCell)
    func textBlockCellDidRequestLayoutUpdate(_ cell: TextBlockCell)
    func textBlockCellDidRequestCommand(_ cell: TextBlockCell, command: EditorCommand)
}

final class TextBlockCell: UITableViewCell, UITextViewDelegate {
    static let reuseIdentifier = "TextBlockCell"

    weak var delegate: TextBlockCellDelegate?

    private let prefixLabel = UILabel()
    private let checkboxButton = UIButton(type: .system)
    private let textView = UITextView()
    private let hStack = UIStackView()
    private let quoteBorderView = UIView()
    private let multiSelectBackgroundView = UIView()
    private let sentHighlightBackgroundView = UIView()

    private var kind: BlockKind = .paragraph
    private var blockId: UUID = UUID()
    private var numberIndex: Int = 1
    private var headingLevel: Int = 1
    private var todoChecked: Bool = false
    private var isMultiSelected: Bool = false
    private var isSentHighlighted: Bool = false
    private var lastRenderedText: String = ""
    private var isApplyingStyle: Bool = false
    private var fontSizeOffset: CGFloat = 0
    
    

    private var inkColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1) :
                UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        }
    }
    
    private var secondaryInkColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1) :
                UIColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
        }
    }

    private var codeBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.15, alpha: 1.0) :
                UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
        }
    }

    private var codeBorderColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.3, alpha: 1.0) :
                UIColor(white: 0.9, alpha: 1.0)
        }
    }

    private var quoteBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.15, alpha: 1.0) :
                UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
        }
    }
    
    private var quoteBorderColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.4, alpha: 1.0) :
                UIColor(white: 0.8, alpha: 1.0)
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

        quoteBorderView.backgroundColor = quoteBorderColor
        quoteBorderView.layer.cornerRadius = 2
        quoteBorderView.isHidden = true
        contentView.addSubview(quoteBorderView)
        quoteBorderView.translatesAutoresizingMaskIntoConstraints = false

        multiSelectBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.06)
        multiSelectBackgroundView.layer.cornerRadius = 12
        multiSelectBackgroundView.isHidden = true
        contentView.addSubview(multiSelectBackgroundView)
        multiSelectBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        hStack.axis = .horizontal
        hStack.alignment = .top
        hStack.spacing = 8
        contentView.addSubview(hStack)
        hStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sentHighlightBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            sentHighlightBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            sentHighlightBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            sentHighlightBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            quoteBorderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            quoteBorderView.topAnchor.constraint(equalTo: hStack.topAnchor, constant: 2),
            quoteBorderView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor, constant: -2),
            quoteBorderView.widthAnchor.constraint(equalToConstant: 4),
            multiSelectBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            multiSelectBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            multiSelectBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            multiSelectBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            hStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])

        prefixLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        prefixLabel.textColor = secondaryInkColor
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        checkboxButton.setImage(UIImage(systemName: "circle"), for: .normal)
        checkboxButton.tintColor = secondaryInkColor
        checkboxButton.addTarget(self, action: #selector(toggleCheckbox), for: .touchUpInside)
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textView.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        textView.textColor = inkColor
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        // Must use high priority to ensure textView expands properly when content changes (e.g., paste)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        hStack.addArrangedSubview(prefixLabel)
        hStack.addArrangedSubview(checkboxButton)
        hStack.addArrangedSubview(textView)

        NSLayoutConstraint.activate([
            checkboxButton.widthAnchor.constraint(equalToConstant: 24),
            checkboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])
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
        textView.isEditable = enabled
        textView.isSelectable = enabled
        textView.isUserInteractionEnabled = enabled
    }

    func configure(with block: Block, numberIndex: Int) {
        self.kind = block.kind
        self.blockId = block.id
        self.numberIndex = numberIndex
        self.headingLevel = block.level ?? 1
        self.todoChecked = block.isChecked ?? false
        self.fontSizeOffset = block.fontSizeOffset ?? 0
        textView.text = block.text
        applyStyle()
    }

    func blockIdentifier() -> UUID {
        blockId
    }

    private func applyStyle() {
        applyStyle(animated: false)
    }
    
    private func applyStyle(animated: Bool) {
        isApplyingStyle = true
        defer { isApplyingStyle = false }
        
        prefixLabel.isHidden = true
        checkboxButton.isHidden = true
        quoteBorderView.isHidden = true
        textView.textColor = inkColor
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = 0
        textView.layer.borderWidth = 0
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        hStack.alignment = .top
        hStack.isLayoutMarginsRelativeArrangement = false
        
        let currentText = textView.text ?? ""
        let savedSelection = textView.selectedRange
        
        // Default paragraph style with good line spacing
        let defaultParagraphStyle = NSMutableParagraphStyle()
        let defaultScale = (16 + fontSizeOffset) / 16
        defaultParagraphStyle.lineSpacing = 4 * defaultScale
        defaultParagraphStyle.lineHeightMultiple = 1.15

        switch kind {
        case .heading:
            let baseSize: CGFloat
            switch headingLevel {
            case 1: baseSize = 30
            case 2: baseSize = 24
            case 3: baseSize = 20
            default: baseSize = 18
            }
            let size = baseSize + fontSizeOffset
            let scale = size / baseSize
            let headingParagraphStyle = NSMutableParagraphStyle()
            headingParagraphStyle.lineSpacing = 4 * scale
            headingParagraphStyle.lineHeightMultiple = 1.1
            headingParagraphStyle.paragraphSpacingBefore = 12 // Add spacing before heading
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: headingParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: .bold), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: UIFont.systemFont(ofSize: size, weight: .bold))
            setAttributedTextAnimated(attrString, animated: animated)
            textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 4, right: 0)
            
        case .quote:
            quoteBorderView.isHidden = false
            // Add background for quote
            textView.backgroundColor = quoteBackgroundColor
            textView.layer.cornerRadius = 6
            
            let size = 16 + fontSizeOffset
            let scale = size / 16
            let quoteParagraphStyle = NSMutableParagraphStyle()
            quoteParagraphStyle.lineSpacing = 5 * scale
            quoteParagraphStyle.lineHeightMultiple = 1.2
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: quoteParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: size), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: secondaryInkColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: UIFont.italicSystemFont(ofSize: size))
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
            hStack.isLayoutMarginsRelativeArrangement = true
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            
        case .bullet:
            prefixLabel.isHidden = false
            prefixLabel.text = "•"
            let size = 16 + fontSizeOffset
            prefixLabel.font = UIFont.systemFont(ofSize: 20 + fontSizeOffset, weight: .bold)
            prefixLabel.textColor = inkColor.withAlphaComponent(0.7)
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: defaultParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: .regular), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: UIFont.systemFont(ofSize: size, weight: .regular))
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
            
        case .numbered:
            prefixLabel.isHidden = false
            prefixLabel.text = "\(numberIndex)."
            let size = 16 + fontSizeOffset
            prefixLabel.font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            prefixLabel.textColor = inkColor.withAlphaComponent(0.7)
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: defaultParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: .regular), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: UIFont.systemFont(ofSize: size, weight: .regular))
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
            
        case .todo:
            checkboxButton.isHidden = false
            hStack.alignment = .top // Align to top for multiline support
            let size = 16 + fontSizeOffset
            let config = UIImage.SymbolConfiguration(pointSize: 17 + fontSizeOffset, weight: .regular)
            let name = todoChecked ? "checkmark.circle.fill" : "circle"
            checkboxButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
            checkboxButton.tintColor = todoChecked ? UIColor.systemBlue : UIColor(white: 0.35, alpha: 1.0)
            checkboxButton.imageView?.contentMode = .scaleAspectFit // Prevent distortion
            
            // Adjust text inset to align visually with checkbox
            textView.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
            
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: defaultParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: .regular), range: NSMakeRange(0, attrString.length))
            
            if todoChecked {
                attrString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSMakeRange(0, attrString.length))
                attrString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: NSMakeRange(0, attrString.length))
            } else {
                attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
                applyInlineMarkdownStyles(to: attrString, baseFont: UIFont.systemFont(ofSize: size, weight: .regular))
            }
            setAttributedTextAnimated(attrString, animated: animated)
            
        case .code:
            let size = 14 + fontSizeOffset
            let scale = size / 14
            let codeParagraphStyle = NSMutableParagraphStyle()
            codeParagraphStyle.lineSpacing = 2 * scale
            codeParagraphStyle.lineHeightMultiple = 1.3
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: codeParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: size, weight: .regular), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            // Don't apply inline markdown to code blocks
            setAttributedTextAnimated(attrString, animated: animated)
            textView.backgroundColor = codeBackgroundColor
            textView.layer.cornerRadius = 8
            textView.layer.borderWidth = 1
            textView.layer.borderColor = codeBorderColor.cgColor
            textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
            
        default:
            // Paragraph style with inline markdown
            let size = 16 + fontSizeOffset
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: defaultParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: .regular), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: UIFont.systemFont(ofSize: size, weight: .regular))
            setAttributedTextAnimated(attrString, animated: animated)
            textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        }
        
        // Restore selection (NSRange uses UTF-16 lengths)
        let textLength = (textView.text as NSString).length
        if savedSelection.location <= textLength {
            let clampedLength = min(savedSelection.length, max(0, textLength - savedSelection.location))
            textView.selectedRange = NSRange(location: savedSelection.location, length: clampedLength)
        }
        
        // Set typing attributes to maintain consistent formatting when typing
        textView.typingAttributes = [
            .font: textView.font ?? UIFont.systemFont(ofSize: 16, weight: .regular),
            .foregroundColor: textView.textColor ?? inkColor,
            .paragraphStyle: defaultParagraphStyle
        ]
        
        lastRenderedText = currentText
    }
    
    // MARK: - Inline Markdown Rendering
    
    private func applyInlineMarkdownStyles(to attrString: NSMutableAttributedString, baseFont: UIFont) {
        let text = attrString.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        
        // Bold: **text** - process first to handle ** before *
        applyInlinePattern("\\*\\*(.+?)\\*\\*", to: attrString, in: fullRange, style: .bold, baseFont: baseFont)
        
        // Italic: *text* (but not inside bold)
        applyInlinePattern("(?<!\\*)\\*([^*]+?)\\*(?!\\*)", to: attrString, in: fullRange, style: .italic, baseFont: baseFont)
        
        // Inline code: `text`
        applyInlinePattern("`([^`]+)`", to: attrString, in: fullRange, style: .code, baseFont: baseFont)
        
        // Highlight: ==color:text==
        applyHighlightPattern(to: attrString, in: fullRange)
    }
    
    private func applyHighlightPattern(to attrString: NSMutableAttributedString, in range: NSRange) {
        let pattern = "==(\\w+):([^=]+)=="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let text = attrString.string as NSString
        let matches = regex.matches(in: text as String, options: [], range: range)
        
        let highlightColors: [String: UIColor] = [
            "yellow": UIColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 1.0),
            "green": UIColor(red: 0.6, green: 0.95, blue: 0.6, alpha: 1.0),
            "blue": UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0),
            "pink": UIColor(red: 1.0, green: 0.75, blue: 0.85, alpha: 1.0),
            "orange": UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1.0),
            "purple": UIColor(red: 0.85, green: 0.75, blue: 1.0, alpha: 1.0)
        ]
        
        let markerHiddenFont = UIFont.systemFont(ofSize: 0.1)
        
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let fullMatchRange = match.range(at: 0)
            let colorKeyRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            
            let colorKey = text.substring(with: colorKeyRange)
            let bgColor = highlightColors[colorKey] ?? highlightColors["yellow"]!
            
            // Apply background color to content
            attrString.addAttribute(.backgroundColor, value: bgColor, range: contentRange)
            
            // Hide the ==color: prefix and == suffix
            let prefixLength = colorKey.count + 3  // == + color + :
            let prefixRange = NSRange(location: fullMatchRange.location, length: prefixLength)
            let suffixRange = NSRange(location: fullMatchRange.location + fullMatchRange.length - 2, length: 2)
            
            attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
            attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
            attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
            attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
        }
    }
    
    private enum InlineStyle {
        case bold
        case italic
        case code
    }
    
    private func applyInlinePattern(_ pattern: String, to attrString: NSMutableAttributedString, in range: NSRange, style: InlineStyle, baseFont: UIFont) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let text = attrString.string as NSString
        let matches = regex.matches(in: text as String, options: [], range: range)
        
        let markerHiddenFont = UIFont.systemFont(ofSize: 0.1)
        let codeBg = UIColor.black.withAlphaComponent(0.06)
        
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange = match.range(at: 0)
            let innerRange = match.range(at: 1)
            
            // Apply style to inner content
            switch style {
            case .bold:
                let boldFont = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold)
                attrString.addAttribute(.font, value: boldFont, range: innerRange)
                // Hide the ** markers
                let prefixRange = NSRange(location: fullRange.location, length: 2)
                let suffixRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
                
            case .italic:
                let italicFont = UIFont.italicSystemFont(ofSize: baseFont.pointSize)
                attrString.addAttribute(.font, value: italicFont, range: innerRange)
                // Hide the * markers
                let prefixRange = NSRange(location: fullRange.location, length: 1)
                let suffixRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
                
            case .code:
                let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
                attrString.addAttribute(.font, value: codeFont, range: innerRange)
                attrString.addAttribute(.backgroundColor, value: codeBg, range: innerRange)
                // Hide the ` markers
                let prefixRange = NSRange(location: fullRange.location, length: 1)
                let suffixRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
            }
        }
    }
    
    private func setAttributedTextAnimated(_ attrString: NSAttributedString, animated: Bool) {
        if animated && !isApplyingStyle {
            UIView.transition(with: textView, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.textView.attributedText = attrString
            }
        } else {
            textView.attributedText = attrString
        }
    }
    
    // MARK: - Inline Format Insertion
    
    func insertInlineFormat(prefix: String, suffix: String, selectedRange: NSRange?) {
        let currentText = textView.text ?? ""
        
        if let range = selectedRange, range.length > 0 {
            // Wrap selected text
            let nsString = currentText as NSString
            let selectedText = nsString.substring(with: range)
            let replacement = prefix + selectedText + suffix
            
            // Check if already formatted - if so, remove formatting
            let beforeIndex = max(0, range.location - prefix.count)
            let afterIndex = min(currentText.count, range.location + range.length + suffix.count)
            
            if beforeIndex >= 0 && range.location >= prefix.count {
                let beforeRange = NSRange(location: beforeIndex, length: prefix.count)
                let afterRange = NSRange(location: range.location + range.length, length: suffix.count)
                
                if afterRange.location + afterRange.length <= currentText.count {
                    let beforeText = nsString.substring(with: beforeRange)
                    let afterText = nsString.substring(with: afterRange)
                    
                    if beforeText == prefix && afterText == suffix {
                        // Remove formatting
                        var newText = currentText
                        let suffixStartIndex = newText.index(newText.startIndex, offsetBy: afterRange.location)
                        let suffixEndIndex = newText.index(suffixStartIndex, offsetBy: suffix.count)
                        newText.removeSubrange(suffixStartIndex..<suffixEndIndex)
                        
                        let prefixStartIndex = newText.index(newText.startIndex, offsetBy: beforeRange.location)
                        let prefixEndIndex = newText.index(prefixStartIndex, offsetBy: prefix.count)
                        newText.removeSubrange(prefixStartIndex..<prefixEndIndex)
                        
                        textView.text = newText
                        textView.selectedRange = NSRange(location: beforeRange.location, length: range.length)
                        delegate?.textBlockCellDidChange(self, text: newText)
                        applyStyle(animated: true)
                        return
                    }
                }
            }
            
            // Apply formatting
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            let newCursorPosition = range.location + replacement.count
            textView.selectedRange = NSRange(location: range.location + prefix.count, length: selectedText.count)
            delegate?.textBlockCellDidChange(self, text: textView.text)
            applyStyle(animated: true)
        } else {
            // No selection - insert format markers with cursor between them
            let cursorPosition = textView.selectedRange.location
            let placeholder = prefix + suffix
            let nsString = (currentText as NSString).mutableCopy() as! NSMutableString
            nsString.insert(placeholder, at: cursorPosition)
            textView.text = nsString as String
            textView.selectedRange = NSRange(location: cursorPosition + prefix.count, length: 0)
            delegate?.textBlockCellDidChange(self, text: textView.text)
            applyStyle(animated: true)
        }
    }

    @objc private func toggleCheckbox() {
        guard kind == .todo else { return }
        Haptics.shared.play(.selection)
        delegate?.textBlockCellDidToggleTodo(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        delegate?.textBlockCellDidChange(self, text: textView.text)
        // Request layout update to handle height changes (e.g., after paste)
        delegate?.textBlockCellDidRequestLayoutUpdate(self)
        
        // Re-apply inline markdown styles if text changed and contains markdown markers
        let currentText = textView.text ?? ""
        if currentText != lastRenderedText && kind != .code {
            // Check if text contains any markdown patterns that need rendering
            if containsInlineMarkdown(currentText) {
                applyStyle(animated: true)
            } else {
                lastRenderedText = currentText
            }
        }
    }
    
    private func containsInlineMarkdown(_ text: String) -> Bool {
        // Check for complete markdown patterns
        let patterns = [
            "\\*\\*[^*]+\\*\\*",  // **bold**
            "(?<!\\*)\\*[^*]+\\*(?!\\*)",  // *italic*
            "`[^`]+`",  // `code`
            "==\\w+:[^=]+=="  // ==color:text== highlight
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil {
                return true
            }
        }
        return false
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        let range = textView.selectedRange
        if range.length > 0, let textRange = Range(range, in: textView.text) {
            delegate?.textBlockCellSelectionDidChange(self, selectedText: String(textView.text[textRange]), range: range)
        } else {
            delegate?.textBlockCellSelectionDidChange(self, selectedText: "", range: range)
        }
    }

    @available(iOS 16.0, *)
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard range.length > 0 else { return UIMenu(children: suggestedActions) }
        
        // 高亮颜色子菜单
        let highlightColors: [(String, String, UIColor)] = [
            ("黄色", "yellow", UIColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 1.0)),
            ("绿色", "green", UIColor(red: 0.6, green: 0.95, blue: 0.6, alpha: 1.0)),
            ("蓝色", "blue", UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0)),
            ("粉色", "pink", UIColor(red: 1.0, green: 0.75, blue: 0.85, alpha: 1.0)),
            ("橙色", "orange", UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1.0)),
            ("紫色", "purple", UIColor(red: 0.85, green: 0.75, blue: 1.0, alpha: 1.0))
        ]
        
        let highlightActions = highlightColors.map { (title, colorKey, color) in
            let image = UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
            return UIAction(title: title, image: image) { [weak self] _ in
                self?.insertHighlight(colorKey: colorKey, selectedRange: range)
            }
        }
        
        let highlightMenu = UIMenu(title: "高亮", image: UIImage(systemName: "highlighter"), children: highlightActions)
        
        // 按顺序排列：标题2、标题3、加粗、符号、编号、待办、引用、代码
        let formatActions: [UIMenuElement] = [
            UIAction(title: "标题 2", image: UIImage(systemName: "textformat.size.larger")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .heading(level: 2))
            },
            UIAction(title: "标题 3", image: UIImage(systemName: "textformat.size")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .heading(level: 3))
            },
            UIAction(title: "加粗", image: UIImage(systemName: "bold")) { [weak self] _ in
                self?.insertInlineFormat(prefix: "**", suffix: "**", selectedRange: range)
            },
            highlightMenu,
            UIAction(title: "符号", image: UIImage(systemName: "list.bullet")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .bullet)
            },
            UIAction(title: "编号", image: UIImage(systemName: "list.number")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .numbered)
            },
            UIAction(title: "待办", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .todo)
            },
            UIAction(title: "引用", image: UIImage(systemName: "text.quote")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .quote)
            },
            UIAction(title: "代码", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .code)
            }
        ]

        let formatMenu = UIMenu(title: "格式", options: .displayInline, children: formatActions)
        let systemMenu = UIMenu(title: "", options: .displayInline, children: suggestedActions)
        return UIMenu(children: [formatMenu, systemMenu])
    }
    
    private func insertHighlight(colorKey: String, selectedRange: NSRange) {
        let currentText = textView.text ?? ""
        let nsString = currentText as NSString
        let selectedText = nsString.substring(with: selectedRange)
        let replacement = "==\(colorKey):\(selectedText)=="
        
        textView.textStorage.replaceCharacters(in: selectedRange, with: replacement)
        textView.selectedRange = NSRange(location: selectedRange.location + colorKey.count + 3, length: selectedText.count)
        delegate?.textBlockCellDidChange(self, text: textView.text)
        applyStyle(animated: true)
    }

    func selectionRectInView(_ view: UIView) -> CGRect? {
        let range = textView.selectedRange
        guard range.length > 0 else { return nil }
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else {
            return nil
        }
        let rect = textView.firstRect(for: textRange)
        if rect.isNull || rect.isEmpty { return nil }
        return textView.convert(rect, to: view)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle backspace at start
        if text.isEmpty && range.location == 0 && range.length == 0 && textView.selectedRange.location == 0 {
            delegate?.textBlockCellDidRequestBackspaceAtStart(self)
            return false
        }
        
        if text == "\n" && textView.text == "```" {
            delegate?.textBlockCellDidTrigger(self, trigger: .codeBlock)
            return false
        }

        if text == "\n" && textView.text == "/table" {
            delegate?.textBlockCellDidTrigger(self, trigger: .table)
            return false
        }

        if text == "\n" {
            if kind == .code {
                return true
            }
            // Pass the cursor location so the text can be split correctly
            delegate?.textBlockCellDidRequestNewBlock(self, splitAtLocation: range.location)
            return false
        }

        let currentTextLength = (textView.text as NSString).length
        if text == " " && range.location == currentTextLength {
            let candidate = textView.text + " "
            if candidate == "# " {
                delegate?.textBlockCellDidTrigger(self, trigger: .heading(level: 1))
                return false
            }
            if candidate == "## " {
                delegate?.textBlockCellDidTrigger(self, trigger: .heading(level: 2))
                return false
            }
            if candidate == "### " {
                delegate?.textBlockCellDidTrigger(self, trigger: .heading(level: 3))
                return false
            }
            if candidate == "- " {
                delegate?.textBlockCellDidTrigger(self, trigger: .bullet)
                return false
            }
            if candidate == "1. " {
                delegate?.textBlockCellDidTrigger(self, trigger: .numbered)
                return false
            }
            if candidate == "- [ ] " {
                delegate?.textBlockCellDidTrigger(self, trigger: .todo)
                return false
            }
            if candidate == "> " {
                delegate?.textBlockCellDidTrigger(self, trigger: .quote)
                return false
            }
        }

        return true
    }

    func beginEditing(atEnd: Bool = false) {
        textView.becomeFirstResponder()
        let location = atEnd ? textView.text.utf16.count : 0
        textView.selectedRange = NSRange(location: location, length: 0)
    }
}

enum MarkdownTrigger: Equatable {
    case heading(level: Int)
    case bullet
    case numbered
    case todo
    case quote
    case codeBlock
    case table
    case attachment(type: AttachmentType, data: Data, fileName: String)
}
#endif