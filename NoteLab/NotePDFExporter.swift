import Foundation

#if os(iOS)
import UIKit

enum NotePDFExportError: Error, Equatable {
    case renderFailed
    case writeFailed
}

enum NotePDFExporter {
    private enum PDFItem {
        case text(NSAttributedString)
        case image(UIImage)
    }

    @MainActor
    static func export(title: String, document: NoteDocument, pageSize: PDFPageSize, noteId: UUID) async throws -> URL {
        let items = await buildPDFItems(title: title, document: document)
        guard let data = renderPDFData(items: items, pageSize: pageSize) else {
            throw NotePDFExportError.renderFailed
        }

        let safeName = sanitizeFileName(title.isEmpty ? "Note" : title, fallbackId: noteId)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw NotePDFExportError.writeFailed
        }
    }

    private static func sanitizeFileName(_ name: String, fallbackId: UUID) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Note-\(fallbackId.uuidString.prefix(6))" : cleaned
    }

    @MainActor
    private static func buildPDFItems(title: String, document: NoteDocument) async -> [PDFItem] {
        var items: [PDFItem] = []
        items.append(.text(parseMarkdownText(
            title,
            font: .systemFont(ofSize: 24, weight: .bold),
            alignment: .center,
            lineSpacing: 6,
            trailingNewlines: "\n\n"
        )))

        for (index, block) in document.blocks.enumerated() {
            let nextBlock = index + 1 < document.blocks.count ? document.blocks[index + 1] : nil
            let isNextParagraph = nextBlock?.kind == .paragraph || nextBlock?.kind == .bullet || nextBlock?.kind == .numbered || nextBlock?.kind == .todo

            switch block.kind {
            case .heading:
                let level = max(1, min(block.level ?? 1, 6))
                let fontSize: CGFloat = level == 1 ? 20 : level == 2 ? 18 : 16
                items.append(.text(parseMarkdownText(
                    block.text,
                    font: .systemFont(ofSize: fontSize, weight: .semibold),
                    lineSpacing: 4,
                    trailingNewlines: isNextParagraph ? "\n" : "\n\n"
                )))
            case .paragraph:
                if !block.text.isEmpty {
                    items.append(.text(parseMarkdownText(block.text, font: .systemFont(ofSize: 14), lineSpacing: 5, trailingNewlines: "\n")))
                }
            case .bullet:
                items.append(.text(parseMarkdownText("• " + block.text, font: .systemFont(ofSize: 14), lineSpacing: 5, trailingNewlines: "\n")))
            case .numbered:
                items.append(.text(parseMarkdownText("1. " + block.text, font: .systemFont(ofSize: 14), lineSpacing: 5, trailingNewlines: "\n")))
            case .todo:
                let checked = block.isChecked ?? false
                items.append(.text(parseMarkdownText(
                    (checked ? "☑ " : "☐ ") + block.text,
                    font: .systemFont(ofSize: 14),
                    color: checked ? .secondaryLabel : .label,
                    lineSpacing: 5,
                    trailingNewlines: "\n"
                )))
            case .quote:
                items.append(.text(parseMarkdownText(block.text, font: .italicSystemFont(ofSize: 14), color: .secondaryLabel, lineSpacing: 5, trailingNewlines: "\n")))
            case .code:
                let codeText = NSMutableAttributedString()
                let codeStyle = NSMutableParagraphStyle()
                codeStyle.lineSpacing = 3
                codeText.append(NSAttributedString(
                    string: block.text + "\n\n",
                    attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: UIColor.label,
                        .backgroundColor: UIColor.systemGray6,
                        .paragraphStyle: codeStyle
                    ]
                ))
                items.append(.text(codeText))
            case .table:
                let tableText = block.table?.plainText ?? ""
                if !tableText.isEmpty {
                    items.append(.text(parseMarkdownText(tableText, font: .systemFont(ofSize: 14), lineSpacing: 5, trailingNewlines: "\n\n")))
                }
            case .attachment:
                if let attachment = block.attachment, attachment.type == .image {
                    if let image = await loadImageAttachment(attachment) {
                        items.append(.image(image))
                    } else {
                        items.append(.text(parseMarkdownText(
                            "[图片未加载: \(attachment.fileName)]",
                            font: .systemFont(ofSize: 12),
                            color: .secondaryLabel,
                            lineSpacing: 5,
                            trailingNewlines: "\n"
                        )))
                    }
                }
            }
        }
        return items
    }

    private static func parseMarkdownText(_ text: String, font: UIFont, color: UIColor = .label, alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0, trailingNewlines: String = "\n") -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineSpacing = lineSpacing
        let baseAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]
        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        typealias PatternHandler = (NSMutableAttributedString, NSTextCheckingResult, UIFont, UIColor, NSMutableParagraphStyle) -> Void
        let patterns: [(pattern: String, handler: PatternHandler)] = [
            ("\\*\\*(.*?)\\*\\*", { attrStr, match, baseFont, textColor, paraStyle in
                replaceMarkdownMatch(attrStr, match: match, font: boldFont(from: baseFont), color: textColor, paragraphStyle: paraStyle)
            }),
            ("(?<!\\*)\\*([^\\*]+)\\*(?!\\*)", { attrStr, match, baseFont, textColor, paraStyle in
                replaceMarkdownMatch(attrStr, match: match, font: italicFont(from: baseFont), color: textColor, paragraphStyle: paraStyle)
            }),
            ("`([^`]+)`", { attrStr, match, baseFont, _, paraStyle in
                replaceMarkdownMatch(attrStr, match: match, font: .monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular), color: .systemRed, paragraphStyle: paraStyle, backgroundColor: .systemGray6)
            }),
            ("==(\\w+):([^=]+)==", { attrStr, match, baseFont, textColor, paraStyle in
                replaceHighlightMatch(attrStr, match: match, font: baseFont, color: textColor, paragraphStyle: paraStyle)
            })
        ]

        for (pattern, handler) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
            for match in matches.reversed() {
                handler(attributedString, match, font, color, paragraphStyle)
            }
        }

        if !trailingNewlines.isEmpty {
            attributedString.append(NSAttributedString(string: trailingNewlines, attributes: baseAttributes))
        }
        return attributedString
    }

    private static func replaceMarkdownMatch(_ attrStr: NSMutableAttributedString, match: NSTextCheckingResult, font: UIFont, color: UIColor, paragraphStyle: NSMutableParagraphStyle, backgroundColor: UIColor? = nil) {
        let fullRange = match.range
        let contentRange = match.range(at: 1)
        guard let range = Range(contentRange, in: attrStr.string) else { return }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]
        if let backgroundColor {
            attributes[.backgroundColor] = backgroundColor
        }
        attrStr.replaceCharacters(in: fullRange, with: NSAttributedString(string: String(attrStr.string[range]), attributes: attributes))
    }

    private static func replaceHighlightMatch(_ attrStr: NSMutableAttributedString, match: NSTextCheckingResult, font: UIFont, color: UIColor, paragraphStyle: NSMutableParagraphStyle) {
        let fullRange = match.range
        guard let colorKeyRange = Range(match.range(at: 1), in: attrStr.string),
              let contentRange = Range(match.range(at: 2), in: attrStr.string) else { return }
        let bgColor: UIColor
        switch String(attrStr.string[colorKeyRange]) {
        case "yellow": bgColor = UIColor.systemYellow.withAlphaComponent(0.4)
        case "green": bgColor = UIColor.systemGreen.withAlphaComponent(0.4)
        case "blue": bgColor = UIColor.systemBlue.withAlphaComponent(0.3)
        case "pink": bgColor = UIColor.systemPink.withAlphaComponent(0.4)
        case "orange": bgColor = UIColor.systemOrange.withAlphaComponent(0.4)
        case "purple": bgColor = UIColor.systemPurple.withAlphaComponent(0.4)
        default: bgColor = UIColor.systemYellow.withAlphaComponent(0.4)
        }
        attrStr.replaceCharacters(
            in: fullRange,
            with: NSAttributedString(
                string: String(attrStr.string[contentRange]),
                attributes: [.font: font, .foregroundColor: color, .backgroundColor: bgColor, .paragraphStyle: paragraphStyle]
            )
        )
    }

    private static func boldFont(from font: UIFont) -> UIFont {
        font.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
    }

    private static func italicFont(from font: UIFont) -> UIFont {
        font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
    }

    @MainActor
    private static func loadImageAttachment(_ attachment: AttachmentModel) async -> UIImage? {
        if let data = attachment.data, let image = UIImage(data: data) {
            return image
        }
        if let cached = AttachmentStorage.shared.loadFromCache(attachmentId: attachment.id, fileName: attachment.fileName),
           let image = UIImage(data: cached) {
            return image
        }
        if let storagePath = attachment.storagePath, !storagePath.isEmpty {
            if let data = try? await AttachmentStorage.shared.loadAttachmentData(
                attachmentId: attachment.id,
                storagePath: storagePath,
                fileName: attachment.fileName
            ),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    private static func renderPDFData(items: [PDFItem], pageSize: PDFPageSize) -> Data? {
        let pageRect = pageSize.pageRect
        let margin = pageSize.margin
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let contentWidth = pageRect.width - margin * 2
        let contentHeight = pageRect.height - margin * 2

        return renderer.pdfData { context in
            var currentY: CGFloat = 0
            func beginPage() {
                context.beginPage()
                currentY = 0
            }
            beginPage()

            for item in items {
                switch item {
                case .image(let image):
                    let scale = min(contentWidth / image.size.width, contentHeight / image.size.height, 1)
                    let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    if currentY + targetSize.height > contentHeight {
                        beginPage()
                    }
                    image.draw(in: CGRect(x: margin, y: margin + currentY, width: targetSize.width, height: targetSize.height))
                    currentY += targetSize.height + 12
                case .text(let text):
                    let textRect = text.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    let textHeight = ceil(textRect.height)
                    if currentY + textHeight > contentHeight {
                        beginPage()
                    }
                    text.draw(
                        with: CGRect(x: margin, y: margin + currentY, width: contentWidth, height: textHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    currentY += textHeight + 12
                }
            }
        }
    }
}
#endif
