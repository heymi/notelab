import Foundation

struct NoteDigestBudget {
    let maxNotes: Int
    let maxTotalChars: Int
    let maxSnippetChars: Int
    let maxHeadingCount: Int
    let maxBulletCount: Int
    let maxHeadingChars: Int
    let maxBulletChars: Int
    let maxParagraphCount: Int
    let maxParagraphChars: Int
}

enum NoteDigestBuilder {
    static func buildRecentDigests(
        notes: [(note: Note, notebookTitle: String)],
        budget: NoteDigestBudget
    ) -> [NoteDigest] {
        let sorted = notes.sorted { $0.note.createdAt > $1.note.createdAt }
        var digests: [NoteDigest] = []
        digests.reserveCapacity(budget.maxNotes)

        for item in sorted {
            if digests.count >= budget.maxNotes { break }
            let digest = buildDigest(note: item.note, notebookTitle: item.notebookTitle, budget: budget)
            digests.append(digest)
        }

        var total = totalChars(for: digests)
        if total <= budget.maxTotalChars { return digests }

        var trimmed = digests
        while total > budget.maxTotalChars, trimmed.count > 1 {
            trimmed.removeLast()
            total = totalChars(for: trimmed)
        }

        if total > budget.maxTotalChars, var first = trimmed.first {
            let limitedSnippet = String(first.snippet.prefix(max(40, budget.maxSnippetChars / 2)))
            let updated = NoteDigest(
                noteId: first.noteId,
                noteTitle: first.noteTitle,
                notebookTitle: first.notebookTitle,
                createdAt: first.createdAt,
                headings: first.headings,
                bullets: first.bullets,
                snippet: limitedSnippet
            )
            trimmed[0] = updated
        }

        return trimmed
    }

    static func buildDigest(note: Note, notebookTitle: String, budget: NoteDigestBudget) -> NoteDigest {
        let cleaned = sanitizeContent(note.content)
        let lines = cleaned.split(whereSeparator: { $0.isNewline }).map { String($0) }

        var headings: [String] = []
        var bullets: [String] = []
        var paragraphs: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                if !title.isEmpty {
                    headings.append(String(title.prefix(budget.maxHeadingChars)))
                }
                continue
            }
            if trimmed.hasPrefix("- [ ] ") {
                bullets.append(String(trimmed.dropFirst(6).prefix(budget.maxBulletChars)))
                continue
            }
            if trimmed.hasPrefix("- ") {
                bullets.append(String(trimmed.dropFirst(2).prefix(budget.maxBulletChars)))
                continue
            }
            paragraphs.append(trimmed)
        }

        let cappedHeadings = Array(headings.prefix(budget.maxHeadingCount))
        let cappedBullets = Array(bullets.prefix(budget.maxBulletCount))
        let cappedParagraphs = Array(paragraphs.prefix(budget.maxParagraphCount)).map { String($0.prefix(budget.maxParagraphChars)) }
        let snippet = String(cappedParagraphs.joined(separator: " ").prefix(budget.maxSnippetChars))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let createdAt = formatter.string(from: note.createdAt)

        return NoteDigest(
            noteId: note.id.uuidString,
            noteTitle: note.title,
            notebookTitle: notebookTitle,
            createdAt: createdAt,
            headings: cappedHeadings,
            bullets: cappedBullets,
            snippet: snippet
        )
    }

    private static func totalChars(for digests: [NoteDigest]) -> Int {
        digests.reduce(0) { partial, digest in
            partial
                + digest.noteTitle.count
                + digest.notebookTitle.count
                + digest.headings.joined(separator: " ").count
                + digest.bullets.joined(separator: " ").count
                + digest.snippet.count
        }
    }

    private static func sanitizeContent(_ content: String) -> String {
        let stripped = stripFencedCodeBlocks(in: content)
        let lines = stripped.split(whereSeparator: \.isNewline)
        var results: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                continue
            }
            results.append(String(trimmed))
        }
        return results.joined(separator: "\n")
    }

    private static func stripFencedCodeBlocks(in content: String) -> String {
        let lines = content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var output: [String] = []
        var insideCode = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.hasPrefix("```") {
                insideCode.toggle()
                if !insideCode {
                    output.append("[代码块省略]")
                }
                continue
            }
            if !insideCode {
                output.append(String(line))
            }
        }
        return output.joined(separator: "\n")
    }
}
