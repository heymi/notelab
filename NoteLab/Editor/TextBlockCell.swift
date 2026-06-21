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
    private let todoCardBackgroundView = UIView()

    private var kind: BlockKind = .paragraph
    private var blockId: UUID = UUID()
    private var numberIndex: Int = 1
    private var headingLevel: Int = 1
    private var todoChecked: Bool = false
    private var isMultiSelected: Bool = false
    private var isSentHighlighted: Bool = false
    private var isVisuallyCollapsed: Bool = false
    private var presentationMode: NoteDetailPresentationMode = .reading
    private var lastRenderedText: String = ""
    private var isApplyingStyle: Bool = false
    private var fontSizeOffset: CGFloat = 0
    
    

    private var inkColor: UIColor {
        .noteEditorInk
    }
    
    private var secondaryInkColor: UIColor {
        .noteEditorSecondaryInk
    }

    private var codeBackgroundColor: UIColor {
        .noteEditorPaperSoft
    }

    private var codeBorderColor: UIColor {
        .noteEditorLine
    }

    private var quoteBackgroundColor: UIColor {
        .noteEditorPaperSoft
    }
    
    private var quoteBorderColor: UIColor {
        .noteEditorAccent
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

    private func displayFont(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        UIFont(name: "STSongti-SC-Black", size: size)
            ?? UIFont(name: "STSongti-SC-Bold", size: size)
            ?? UIFont(name: "SongtiSC-Black", size: size)
            ?? UIFont(name: "SongtiSC-Bold", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func bodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func readingBodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func readingParagraphStyle(size: CGFloat, lineHeightMultiple: CGFloat = 1.44, lineSpacing: CGFloat = 2.5, paragraphSpacing: CGFloat = 7) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        let scale = size / 17
        style.lineHeightMultiple = lineHeightMultiple
        style.lineSpacing = lineSpacing * scale
        style.paragraphSpacing = paragraphSpacing * scale
        return style
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

        todoCardBackgroundView.layer.cornerRadius = 22
        todoCardBackgroundView.layer.cornerCurve = .continuous
        todoCardBackgroundView.layer.borderWidth = 0.6
        todoCardBackgroundView.layer.shadowColor = UIColor.black.cgColor
        todoCardBackgroundView.layer.shadowOpacity = 0.035
        todoCardBackgroundView.layer.shadowRadius = 18
        todoCardBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 8)
        todoCardBackgroundView.isHidden = true
        contentView.addSubview(todoCardBackgroundView)
        todoCardBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        multiSelectBackgroundView.backgroundColor = UIColor.noteEditorSelection
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
            sentHighlightBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            sentHighlightBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            quoteBorderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            quoteBorderView.topAnchor.constraint(equalTo: hStack.topAnchor, constant: 2),
            quoteBorderView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor, constant: -2),
            quoteBorderView.widthAnchor.constraint(equalToConstant: 4),
            todoCardBackgroundView.topAnchor.constraint(equalTo: hStack.topAnchor),
            todoCardBackgroundView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor),
            todoCardBackgroundView.leadingAnchor.constraint(equalTo: hStack.leadingAnchor),
            todoCardBackgroundView.trailingAnchor.constraint(equalTo: hStack.trailingAnchor),
            multiSelectBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            multiSelectBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            multiSelectBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            multiSelectBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            hStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 46),
            hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -46)
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

        textView.font = bodyFont(size: 17)
        textView.textColor = inkColor
        textView.tintColor = .noteEditorAccentDeep
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

        applyAdaptiveColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyAdaptiveColors()
        applyStyle()
    }

    private func applyAdaptiveColors() {
        sentHighlightBackgroundView.backgroundColor = sentHighlightColor
        quoteBorderView.backgroundColor = quoteBorderColor
        todoCardBackgroundView.backgroundColor = UIColor.noteEditorPaper.withAlphaComponent(0.72)
        todoCardBackgroundView.layer.borderColor = UIColor.noteEditorLine.withAlphaComponent(0.2).cgColor
        multiSelectBackgroundView.backgroundColor = UIColor.noteEditorSelection
        prefixLabel.textColor = secondaryInkColor
        textView.textColor = inkColor
        textView.tintColor = .noteEditorAccentDeep
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
        textView.isEditable = editable && !isVisuallyCollapsed
        textView.isSelectable = selectable && !isVisuallyCollapsed
        textView.isUserInteractionEnabled = (editable || selectable) && !isVisuallyCollapsed
    }

    func setContentInteractionEnabled(_ enabled: Bool) {
        setContentInteraction(editable: enabled, selectable: enabled)
    }

    func setVisuallyCollapsed(_ collapsed: Bool) {
        isVisuallyCollapsed = collapsed
        contentView.isHidden = collapsed
        isUserInteractionEnabled = !collapsed
        textView.isHidden = collapsed
        prefixLabel.isHidden = collapsed || prefixLabel.isHidden
        checkboxButton.isHidden = collapsed || checkboxButton.isHidden
        quoteBorderView.isHidden = true
        multiSelectBackgroundView.isHidden = true
        sentHighlightBackgroundView.isHidden = true
    }

    func configure(with block: Block, numberIndex: Int, presentationMode: NoteDetailPresentationMode = .reading) {
        isVisuallyCollapsed = false
        contentView.isHidden = false
        isUserInteractionEnabled = true
        self.presentationMode = presentationMode
        textView.isHidden = false
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
        todoCardBackgroundView.isHidden = true
        textView.textColor = inkColor
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = 0
        textView.layer.borderWidth = 0
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        hStack.alignment = .top
        hStack.spacing = presentationMode.isEditing ? 8 : 11
        hStack.isLayoutMarginsRelativeArrangement = false
        
        let currentText = textView.text ?? ""
        let savedSelection = textView.selectedRange
        
        // Default paragraph style with good line spacing
        let defaultParagraphStyle = NSMutableParagraphStyle()
        let defaultScale = (17 + fontSizeOffset) / 17
        defaultParagraphStyle.lineSpacing = 6 * defaultScale
        defaultParagraphStyle.lineHeightMultiple = 1.2

        if presentationMode.isEditing {
            applyPlainEditingStyle(currentText: currentText, paragraphStyle: defaultParagraphStyle, animated: animated)
            restoreSelection(savedSelection)
            updateTypingAttributes(paragraphStyle: defaultParagraphStyle)
            lastRenderedText = currentText
            return
        }

        switch kind {
        case .heading:
            let baseSize: CGFloat
            switch headingLevel {
            case 1: baseSize = 31
            case 2: baseSize = 23
            case 3: baseSize = 19
            default: baseSize = 18
            }
            let size = baseSize + fontSizeOffset
            let scale = size / baseSize
            let headingParagraphStyle = NSMutableParagraphStyle()
            headingParagraphStyle.lineSpacing = (headingLevel == 1 ? 2 : 4) * scale
            headingParagraphStyle.lineHeightMultiple = headingLevel == 1 ? 1.08 : 1.16
            headingParagraphStyle.paragraphSpacingBefore = headingLevel == 1 ? 16 : 12
            headingParagraphStyle.paragraphSpacing = headingLevel == 1 ? 8 : 6
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: headingParagraphStyle, range: NSMakeRange(0, attrString.length))
            let headingFont = headingLevel == 1 ? displayFont(size: size) : bodyFont(size: size, weight: .bold)
            attrString.addAttribute(.font, value: headingFont, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: headingFont)
            setAttributedTextAnimated(attrString, animated: animated)
            textView.textContainerInset = UIEdgeInsets(top: headingLevel == 1 ? 15 : 12, left: 0, bottom: headingLevel == 1 ? 10 : 7, right: 0)
            
        case .quote:
            textView.backgroundColor = quoteBackgroundColor
            textView.layer.cornerRadius = 18
            
            let size = 17 + fontSizeOffset
            let quoteParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 3, paragraphSpacing: 7)
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: quoteParagraphStyle, range: NSMakeRange(0, attrString.length))
            let quoteFont = readingBodyFont(size: size, weight: .regular)
            attrString.addAttribute(.font, value: quoteFont, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: UIColor.noteEditorAccentDeep, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: quoteFont)
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.layoutMargins = UIEdgeInsets(top: 6, left: 2, bottom: 8, right: 2)
            hStack.isLayoutMarginsRelativeArrangement = true
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
            
        case .bullet:
            prefixLabel.isHidden = false
            prefixLabel.text = "•"
            let size = 16.5 + fontSizeOffset
            prefixLabel.font = UIFont.systemFont(ofSize: 15 + fontSizeOffset, weight: .bold)
            prefixLabel.textColor = .noteEditorAccent
            let attrString = NSMutableAttributedString(string: currentText)
            let listParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 2.5, paragraphSpacing: 5)
            attrString.addAttribute(.paragraphStyle, value: listParagraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: UIColor.noteEditorBody, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: font)
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 7, right: 0)
            
        case .numbered:
            prefixLabel.isHidden = false
            prefixLabel.text = "\(numberIndex)."
            let size = 16.5 + fontSizeOffset
            prefixLabel.font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            prefixLabel.textColor = .noteEditorAccentDeep
            let attrString = NSMutableAttributedString(string: currentText)
            let listParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 2.5, paragraphSpacing: 5)
            attrString.addAttribute(.paragraphStyle, value: listParagraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: UIColor.noteEditorBody, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: font)
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 7, right: 0)
            
        case .todo:
            checkboxButton.isHidden = false
            hStack.alignment = presentationMode.isEditing ? .top : .center
            todoCardBackgroundView.isHidden = false
            hStack.layoutMargins = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
            hStack.isLayoutMarginsRelativeArrangement = true
            hStack.spacing = 14
            let size = 16.5 + fontSizeOffset
            let config = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
            let name = todoChecked ? "checkmark.circle.fill" : "circle"
            checkboxButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
            checkboxButton.tintColor = todoChecked ? .noteEditorAccentDeep : .noteEditorSecondaryInk
            checkboxButton.imageView?.contentMode = .scaleAspectFit // Prevent distortion
            
            // Adjust text inset to align visually with checkbox
            textView.textContainerInset = UIEdgeInsets(top: 1, left: 0, bottom: 4, right: 0)
            
            let attrString = NSMutableAttributedString(string: currentText)
            let todoParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 2.5, paragraphSpacing: 5)
            attrString.addAttribute(.paragraphStyle, value: todoParagraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size, weight: .regular)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            
            if todoChecked {
                attrString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSMakeRange(0, attrString.length))
                attrString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: NSMakeRange(0, attrString.length))
            } else {
                attrString.addAttribute(.foregroundColor, value: UIColor.noteEditorBody, range: NSMakeRange(0, attrString.length))
                applyInlineMarkdownStyles(to: attrString, baseFont: font)
            }
            setAttributedTextAnimated(attrString, animated: animated)
            
        case .code:
            let size = 14.5 + fontSizeOffset
            let scale = size / 14.5
            let codeParagraphStyle = NSMutableParagraphStyle()
            codeParagraphStyle.lineSpacing = 4 * scale
            codeParagraphStyle.lineHeightMultiple = 1.38
            codeParagraphStyle.paragraphSpacing = 4 * scale
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: codeParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: size, weight: .regular), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: UIColor.noteEditorInk, range: NSMakeRange(0, attrString.length))
            // Don't apply inline markdown to code blocks
            setAttributedTextAnimated(attrString, animated: animated)
            textView.backgroundColor = codeBackgroundColor
            textView.layer.cornerRadius = 18
            textView.layer.borderWidth = 0.7
            textView.layer.borderColor = codeBorderColor.cgColor
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
            
        default:
            // Paragraph style with inline markdown
            let size = 17 + fontSizeOffset
            let attrString = NSMutableAttributedString(string: currentText)
            let paragraphStyle = readingParagraphStyle(size: size)
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: UIColor.noteEditorBody, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: font)
            setAttributedTextAnimated(attrString, animated: animated)
            textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 10, right: 0)
        }

        restoreSelection(savedSelection)
        updateTypingAttributes(paragraphStyle: defaultParagraphStyle)

        lastRenderedText = currentText
    }

    private func applyPlainEditingStyle(currentText: String, paragraphStyle: NSMutableParagraphStyle, animated: Bool) {
        switch kind {
        case .bullet:
            prefixLabel.isHidden = false
            prefixLabel.text = "•"
            prefixLabel.font = UIFont.systemFont(ofSize: 18 + fontSizeOffset, weight: .bold)
            prefixLabel.textColor = .noteEditorAccent
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 5, right: 0)
        case .numbered:
            prefixLabel.isHidden = false
            prefixLabel.text = "\(numberIndex)."
            prefixLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 17 + fontSizeOffset, weight: .semibold)
            prefixLabel.textColor = .noteEditorAccentDeep
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 5, right: 0)
        case .todo:
            checkboxButton.isHidden = false
            hStack.alignment = .top
            let config = UIImage.SymbolConfiguration(pointSize: 17 + fontSizeOffset, weight: .regular)
            let name = todoChecked ? "checkmark.circle.fill" : "circle"
            checkboxButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
            checkboxButton.tintColor = todoChecked ? .noteEditorAccentDeep : .noteEditorSecondaryInk
            textView.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
        case .code:
            textView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        default:
            textView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        }

        let size: CGFloat = kind == .code ? 15 + fontSizeOffset : 17 + fontSizeOffset
        let font = kind == .code
            ? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : bodyFont(size: size)
        let attrString = NSMutableAttributedString(string: currentText)
        attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSMakeRange(0, attrString.length))
        attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
        attrString.addAttribute(.foregroundColor, value: todoChecked ? UIColor.secondaryLabel : UIColor.noteEditorBody, range: NSMakeRange(0, attrString.length))
        if kind == .todo && todoChecked {
            attrString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSMakeRange(0, attrString.length))
        }
        setAttributedTextAnimated(attrString, animated: animated)
    }

    private func restoreSelection(_ savedSelection: NSRange) {
        let textLength = (textView.text as NSString).length
        if savedSelection.location <= textLength {
            let clampedLength = min(savedSelection.length, max(0, textLength - savedSelection.location))
            textView.selectedRange = NSRange(location: savedSelection.location, length: clampedLength)
        }
    }

    private func updateTypingAttributes(paragraphStyle: NSMutableParagraphStyle) {
        textView.typingAttributes = [
            .font: textView.font ?? bodyFont(size: 17),
            .foregroundColor: textView.textColor ?? inkColor,
            .paragraphStyle: paragraphStyle
        ]
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
        let pattern = "==([A-Za-z]+):([\\s\\S]+?)=="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let text = attrString.string as NSString
        let matches = regex.matches(in: text as String, options: [], range: range)
        
        let highlightColors: [String: UIColor] = [
            "yellow": UIColor(red: 1.0, green: 0.91, blue: 0.36, alpha: 0.42),
            "green": UIColor(red: 0.62, green: 0.88, blue: 0.68, alpha: 0.34),
            "blue": UIColor(red: 0.62, green: 0.80, blue: 0.95, alpha: 0.32),
            "pink": UIColor(red: 1.0, green: 0.74, blue: 0.84, alpha: 0.32),
            "orange": UIColor(red: 1.0, green: 0.78, blue: 0.46, alpha: 0.34),
            "purple": UIColor(red: 0.78, green: 0.70, blue: 0.94, alpha: 0.32)
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
        let codeBg = UIColor.noteEditorPaperSoft
        
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange = match.range(at: 0)
            let innerRange = match.range(at: 1)
            
            // Apply style to inner content
            switch style {
            case .bold:
                let boldFont = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)
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
                attrString.addAttribute(.foregroundColor, value: UIColor.noteEditorAccentDeep, range: innerRange)
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
        if !presentationMode.isEditing && currentText != lastRenderedText && kind != .code {
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
        guard presentationMode.isEditing else { return UIMenu(children: suggestedActions) }
        
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
