import Foundation

enum NoteShareBuilder {
    static func plainText(title: String, document: NoteDocument, fallbackMarkdown: String) -> String {
        let body = exportBody(document: document, fallbackMarkdown: fallbackMarkdown)
        return body.isEmpty ? title : "\(title)\n\n\(body)"
    }

    static func exportBody(document: NoteDocument, fallbackMarkdown: String) -> String {
        let text = document.flattenPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        let fallback = NoteDocument.fromMarkdown(fallbackMarkdown).flattenPlainText()
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
