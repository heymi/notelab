import SwiftUI

#if os(macOS)
import AppKit

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(styledText(from: text))

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if context.coordinator.isApplyingStyle { return }
        if textView.string != text {
            textView.string = text
            textView.textStorage?.setAttributedString(styledText(from: text))
        }
    }

    private func styledText(from markdown: String) -> NSAttributedString {
        if let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) {
            return NSAttributedString(attributed)
        }
        return NSAttributedString(string: markdown)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MarkdownTextEditor
        var isApplyingStyle = false

        init(parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if isApplyingStyle { return }
            parent.text = textView.string

            let selectedRange = textView.selectedRange()
            isApplyingStyle = true
            textView.textStorage?.setAttributedString(parent.styledText(from: textView.string))
            textView.setSelectedRange(selectedRange)
            isApplyingStyle = false
        }
    }
}
#endif
