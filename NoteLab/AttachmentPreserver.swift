import Foundation

struct AttachmentToken: Hashable {
    let token: String
    let markdownLine: String
    let target: String
}

enum AttachmentPreserver {
    static func extractTokens(from document: NoteDocument) -> [AttachmentToken] {
        var tokens: [AttachmentToken] = []
        var index = 0
        for block in document.blocks {
            guard block.kind == .attachment, let attachment = block.attachment else { continue }
            let target = attachment.storagePath ?? attachment.fileName
            let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTarget.isEmpty else { continue }
            let token = "[[ATTACHMENT:\(index)]]"
            let markdownLine = "![Attachment](\(trimmedTarget))"
            tokens.append(AttachmentToken(token: token, markdownLine: markdownLine, target: trimmedTarget))
            index += 1
        }
        return tokens
    }

    static func tokenize(content: String, tokens: [AttachmentToken]) -> String {
        var output = content
        for token in tokens {
            output = replaceFirstOccurrence(in: output, of: token.markdownLine, with: token.token)
        }
        return output
    }

    static func restore(content: String, tokens: [AttachmentToken]) -> String {
        var output = content
        for token in tokens {
            output = output.replacingOccurrences(of: token.token, with: token.markdownLine)
        }
        return output
    }

    static func ensureAllAttachmentsPresent(markdown: String, tokens: [AttachmentToken]) -> String {
        guard !tokens.isEmpty else { return markdown }
        var missingLines: [String] = []
        for token in tokens {
            if !markdown.contains(token.markdownLine) {
                missingLines.append(token.markdownLine)
            }
        }
        guard !missingLines.isEmpty else { return markdown }

        var output = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            output += "\n\n"
        }
        output += "## 附件\n"
        output += missingLines.joined(separator: "\n")
        return output
    }

    static func restoreAndEnsure(markdown: String, tokens: [AttachmentToken]) -> String {
        let restored = restore(content: markdown, tokens: tokens)
        return ensureAllAttachmentsPresent(markdown: restored, tokens: tokens)
    }

    private static func replaceFirstOccurrence(in text: String, of target: String, with replacement: String) -> String {
        guard let range = text.range(of: target) else { return text }
        var result = text
        result.replaceSubrange(range, with: replacement)
        return result
    }
}
