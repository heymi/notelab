import Foundation

enum NoteShareBuilder {
    static func plainText(title: String, document: NoteDocument, fallbackMarkdown: String) -> String {
        let body = exportBody(document: document, fallbackMarkdown: fallbackMarkdown)
        return body.isEmpty ? title : "\(title)\n\n\(body)"
    }

    static func markdown(title: String, document: NoteDocument, fallbackMarkdown: String) -> String {
        let body = markdownBody(document: document, fallbackMarkdown: fallbackMarkdown)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return body }
        guard !body.isEmpty else { return "# \(trimmedTitle)" }
        guard !bodyStartsWithTitle(body, title: trimmedTitle) else { return body }
        return "# \(trimmedTitle)\n\n\(body)"
    }

    static func exportBody(document: NoteDocument, fallbackMarkdown: String) -> String {
        let text = document.flattenPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        let fallback = NoteDocument.fromMarkdown(fallbackMarkdown).flattenPlainText()
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func markdownBody(document: NoteDocument, fallbackMarkdown: String) -> String {
        let markdown = document.flattenMarkdown().trimmingCharacters(in: .whitespacesAndNewlines)
        if !markdown.isEmpty {
            return markdown
        }
        let fallback = NoteDocument.fromMarkdown(fallbackMarkdown).flattenMarkdown()
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bodyStartsWithTitle(_ body: String, title: String) -> Bool {
        guard let firstLine = body
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first
        else {
            return false
        }
        return NoteTitleDeriver.cleanedTitleLine(firstLine) == title
    }
}
