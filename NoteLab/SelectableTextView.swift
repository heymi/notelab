import Foundation
#if canImport(UIKit)
import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    @Binding var selectedRange: NSRange
    @Binding var replacement: TextReplacement?
    @Binding var dynamicHeight: CGFloat

    var highlights: [(range: NSRange, color: UIColor)] = []
    var onEdit: ((NSRange, String) -> Void)? = nil
    var renderMarkdown: Bool = false

    var font: UIFont = .systemFont(ofSize: 16, weight: .regular)
    var textColor: UIColor = UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = font
        view.textColor = textColor
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 10, left: 0, bottom: 12, right: 0)
        view.textContainer.lineBreakMode = .byCharWrapping
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.maximumNumberOfLines = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            context.coordinator.textViewDidChange(uiView)
        }
        applyHighlights(in: uiView)
        if let replacement {
            if replacement.range.location != NSNotFound,
               replacement.range.location + replacement.range.length <= uiView.text.count {
                uiView.textStorage.replaceCharacters(in: replacement.range, with: replacement.text)
            }
            DispatchQueue.main.async {
                self.replacement = nil
                context.coordinator.textViewDidChange(uiView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func applyHighlights(in textView: UITextView) {
        let fullRange = NSRange(location: 0, length: textView.text.utf16.count)
        let paragraphStyle = baseParagraphStyle()
        textView.textStorage.beginEditing()
        textView.textStorage.setAttributes([
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ], range: fullRange)
        if renderMarkdown {
            applyMarkdownStyles(in: textView, fullRange: fullRange)
        }
        if !highlights.isEmpty {
            for highlight in highlights {
                let range = highlight.range
                guard range.location != NSNotFound,
                      range.length > 0,
                      range.location + range.length <= fullRange.length else { continue }
                textView.textStorage.addAttribute(.backgroundColor, value: highlight.color, range: range)
            }
        }
        textView.textStorage.endEditing()
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func applyMarkdownStyles(in textView: UITextView, fullRange: NSRange) {
        let text = textView.text as NSString
        let baseFont = font
        let boldFont = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let italicFont = UIFont.italicSystemFont(ofSize: font.pointSize)
        let codeFont = UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular)
        let faintColor = textColor.withAlphaComponent(0.45)
        let codeBg = UIColor.black.withAlphaComponent(0.06)

        var index = 0
        while index < text.length {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let lineText = text.substring(with: lineRange)
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let prefix = String(repeating: "#", count: level) + " "
                if trimmed.hasPrefix(prefix) {
                    let prefixRange = NSRange(location: lineRange.location, length: prefix.utf16.count)
                    textView.textStorage.addAttribute(.foregroundColor, value: faintColor, range: prefixRange)
                    let size = font.pointSize + CGFloat(max(0, 4 - level) * 2)
                    let headingFont = UIFont.systemFont(ofSize: size, weight: .semibold)
                    textView.textStorage.addAttribute(.font, value: headingFont, range: lineRange)
                }
            } else if trimmed.hasPrefix("> ") {
                let prefixRange = NSRange(location: lineRange.location, length: 2)
                textView.textStorage.addAttribute(.foregroundColor, value: faintColor, range: prefixRange)
                textView.textStorage.addAttribute(.foregroundColor, value: textColor.withAlphaComponent(0.85), range: lineRange)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let prefixLen = trimmed.hasPrefix("- [ ") ? 6 : 2
                let prefixRange = NSRange(location: lineRange.location, length: prefixLen)
                textView.textStorage.addAttribute(.foregroundColor, value: faintColor, range: prefixRange)
            } else if isNumbered(lineText) {
                if let numberPrefixLen = numberedPrefixLength(lineText) {
                    let prefixRange = NSRange(location: lineRange.location, length: numberPrefixLen)
                    textView.textStorage.addAttribute(.foregroundColor, value: faintColor, range: prefixRange)
                }
            }

            index = lineRange.location + lineRange.length
        }

        applyInlinePattern("\\*\\*(.+?)\\*\\*", in: textView, font: boldFont)
        applyInlinePattern("\\*(.+?)\\*", in: textView, font: italicFont)
        applyInlinePattern("`([^`]+)`", in: textView, font: codeFont, background: codeBg)
        applyFencedCodeBlocks(in: textView, font: codeFont, background: codeBg, faintColor: faintColor)
    }

    private func applyInlinePattern(_ pattern: String, in textView: UITextView, font: UIFont, background: UIColor? = nil) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let text = textView.text as NSString
        let matches = regex.matches(in: text as String, options: [], range: NSRange(location: 0, length: text.length))
        for match in matches {
            if match.numberOfRanges < 2 { continue }
            let inner = match.range(at: 1)
            textView.textStorage.addAttribute(.font, value: font, range: inner)
            if let background {
                textView.textStorage.addAttribute(.backgroundColor, value: background, range: inner)
            }
        }
    }

    private func applyFencedCodeBlocks(in textView: UITextView, font: UIFont, background: UIColor, faintColor: UIColor) {
        let text = textView.text as NSString
        let pattern = "```(\\n|\\r\\n)([\\s\\S]*?)(\\n|\\r\\n)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: text as String, options: [], range: NSRange(location: 0, length: text.length))
        for match in matches {
            if match.numberOfRanges < 3 { continue }
            let full = match.range(at: 0)
            let inner = match.range(at: 2)
            textView.textStorage.addAttribute(.font, value: font, range: inner)
            textView.textStorage.addAttribute(.backgroundColor, value: background, range: inner)
            textView.textStorage.addAttribute(.foregroundColor, value: faintColor, range: full)
        }
    }

    private func isNumbered(_ line: String) -> Bool {
        let chars = Array(line)
        var idx = 0
        while idx < chars.count, chars[idx].isNumber { idx += 1 }
        return idx > 0 && idx + 1 < chars.count && chars[idx] == "." && chars[idx + 1] == " "
    }

    private func numberedPrefixLength(_ line: String) -> Int? {
        let chars = Array(line)
        var idx = 0
        while idx < chars.count, chars[idx].isNumber { idx += 1 }
        if idx > 0 && idx + 1 < chars.count && chars[idx] == "." && chars[idx + 1] == " " {
            return idx + 2
        }
        return nil
    }

    private func baseParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.18
        style.lineSpacing = 3
        style.paragraphSpacing = 10
        style.paragraphSpacingBefore = 2
        style.alignment = .natural
        return style
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SelectableTextView

        init(parent: SelectableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
            DispatchQueue.main.async {
                self.parent.dynamicHeight = max(200, size.height)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            parent.selectedRange = range
            if range.length > 0, let textRange = Range(range, in: textView.text) {
                parent.selectedText = String(textView.text[textRange])
            } else {
                parent.selectedText = ""
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            parent.onEdit?(range, text)
            return true
        }
    }
}

struct TextReplacement: Equatable {
    let range: NSRange
    let text: String
}
#endif