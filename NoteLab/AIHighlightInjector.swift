import Foundation

enum AIHighlightInjector {
    static func applyHighlightsIfNeeded(markdown: String, aiClient: AIClient) async throws -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return markdown }

        let counts = desiredHighlightCounts(for: trimmed)
        let existingCount = countHighlights(in: trimmed)
        if existingCount >= counts.min { return markdown }

        let remainingSlots = max(counts.max - existingCount, 0)
        guard remainingSlots > 0 else { return markdown }

        let suggestions = try await aiClient.supplementHighlights(text: trimmed, maxHighlights: remainingSlots)
        if suggestions.isEmpty { return markdown }
        return injectHighlights(markdown: markdown, highlights: suggestions)
    }

    private static func desiredHighlightCounts(for text: String) -> (min: Int, max: Int) {
        let length = text.count
        if length <= 200 { return (0, 2) }
        if length <= 800 { return (3, 5) }
        return (5, 8)
    }

    private static func countHighlights(in markdown: String) -> Int {
        let pattern = "==\\w+:[^=]+=="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return 0 }
        let range = NSRange(location: 0, length: (markdown as NSString).length)
        return regex.numberOfMatches(in: markdown, options: [], range: range)
    }

    private static func injectHighlights(markdown: String, highlights: [AIHighlightSuggestion]) -> String {
        var current = markdown
        var leftovers: [AIHighlightSuggestion] = []

        for item in highlights {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let replacement = "==\(item.normalizedColor):\(text)=="
            let (updated, didReplace) = replaceFirstOutsideCodeBlocks(in: current, target: text, replacement: replacement)
            if didReplace {
                current = updated
            } else {
                leftovers.append(item)
            }
        }

        if leftovers.isEmpty { return current }
        var output = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty { output += "\n\n" }
        output += "## 重点\n"
        let lines = leftovers.map { "- ==\($0.normalizedColor):\($0.text.trimmingCharacters(in: .whitespacesAndNewlines))==" }
        output += lines.joined(separator: "\n")
        return output
    }

    private static func replaceFirstOutsideCodeBlocks(in markdown: String, target: String, replacement: String) -> (String, Bool) {
        guard !target.isEmpty else { return (markdown, false) }
        let parts = markdown.components(separatedBy: "```")
        guard parts.count > 1 else {
            if let range = markdown.range(of: target) {
                var updated = markdown
                updated.replaceSubrange(range, with: replacement)
                return (updated, true)
            }
            return (markdown, false)
        }

        var didReplace = false
        var newParts: [String] = []
        newParts.reserveCapacity(parts.count)
        for (index, part) in parts.enumerated() {
            if didReplace || index % 2 == 1 {
                newParts.append(part)
                continue
            }
            if let range = part.range(of: target) {
                var updated = part
                updated.replaceSubrange(range, with: replacement)
                newParts.append(updated)
                didReplace = true
            } else {
                newParts.append(part)
            }
        }
        return (newParts.joined(separator: "```"), didReplace)
    }
}
