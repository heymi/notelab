import Foundation

enum AIInsightComposer {
    static func composeInsightMarkdown(
        formattedMarkdown: String,
        report: AINoteInsightReport?,
        tasks: [AITaskSuggestion],
        fallbackTitle: String
    ) -> String {
        guard let report else { return formattedMarkdown }
        var lines: [String] = []
        let finalTitle = resolvedTitle(from: report.title, fallback: fallbackTitle)

        var seenBullets = Set<String>()
        for section in report.sections {
            let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty {
                lines.append("## \(heading)")
            }
            for paragraph in section.paragraphs where !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(contentsOf: splitLongParagraph(paragraph))
            }
            for bullet in section.bullets {
                let cleaned = bullet.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                if !seenBullets.contains(cleaned) {
                    seenBullets.insert(cleaned)
                    lines.append("- \(cleaned)")
                }
            }
        }

        for table in report.tables {
            guard !isLowValueTodoStatusTable(table) else { continue }
            let title = table.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                lines.append("## \(title)")
            }
            let markdown = markdownTable(from: table)
            if !markdown.isEmpty { lines.append(markdown) }
            if let notes = table.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(notes)
            }
        }

        let taskLines = tasks.map { task -> String in
            if let due = task.normalizedDueDate, !due.isEmpty {
                return "- [ ] \(task.text)（\(due)）"
            }
            return "- [ ] \(task.text)"
        }
        if !taskLines.isEmpty {
            lines.append("## 待办")
            lines.append(contentsOf: taskLines)
        }

        let headingsToStrip = buildStripHeadings(report: report)
        let dropLines = buildDropLines(report: report)
        let processedBody = processBodyMarkdown(
            formattedMarkdown,
            title: finalTitle,
            stripHeadings: headingsToStrip,
            dropLines: dropLines
        )
        if !processedBody.isEmpty {
            if shouldLabelBody(processedBody) {
                lines.append("## 正文")
            }
            lines.append(processedBody)
        }

        return lines.joined(separator: "\n\n")
    }

    static func resolvedTitle(from reportTitle: String?, fallback: String) -> String {
        NoteTitleDeriver.title(fromAI: reportTitle, fallback: fallback)
    }

    private static func buildStripHeadings(report: AINoteInsightReport) -> Set<String> {
        var headings: Set<String> = ["摘要", "待办", "正文"]
        for section in report.sections {
            let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty { headings.insert(heading) }
        }
        for table in report.tables {
            let title = table.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { headings.insert(title) }
        }
        return headings
    }

    private static func processBodyMarkdown(_ markdown: String, title: String, stripHeadings: Set<String>, dropLines: Set<String>) -> String {
        let replaced = replaceLeadingH1(in: markdown, title: title)
        let withoutStrippedSections = stripHeadingSections(from: replaced.body, headings: stripHeadings)
        let withoutTables = stripMarkdownTables(from: withoutStrippedSections)
        let deduped = dedupeMarkdownBlocks(withoutTables, dropLines: dropLines)
        let segmented = segmentLongParagraphLines(deduped)
        return normalizeBlankLines(segmented)
    }

    private static func replaceLeadingH1(in markdown: String, title: String) -> (body: String, didReplace: Bool) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (markdown, false) }
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        guard index < lines.count else { return (markdown, false) }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("# ") else { return (markdown, false) }
        var newLines = lines
        newLines[index] = "# \(title)"
        return (newLines.joined(separator: "\n"), true)
    }

    private static func stripHeadingSections(from markdown: String, headings: Set<String>) -> String {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var result: [String] = []
        var skip = false
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = parseMarkdownHeading(trimmed) {
                let text = heading.text.trimmingCharacters(in: .whitespacesAndNewlines)
                skip = headings.contains(text)
                if !skip { result.append(line) }
                index += 1
                continue
            }
            if skip {
                if trimmed.hasPrefix("#") {
                    if let nextHeading = parseMarkdownHeading(trimmed) {
                        let text = nextHeading.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        skip = headings.contains(text)
                        if !skip { result.append(line) }
                    }
                }
                index += 1
                continue
            }
            result.append(line)
            index += 1
        }
        return result.joined(separator: "\n")
    }

    private static func parseMarkdownHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let level = line.prefix { $0 == "#" }.count
        guard level > 0 && level <= 6 else { return nil }
        let prefix = String(repeating: "#", count: level) + " "
        guard line.hasPrefix(prefix) else { return nil }
        let text = String(line.dropFirst(prefix.count))
        return (level, text)
    }

    private static func stripMarkdownTables(from markdown: String) -> String {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var result: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if isTableHeaderLine(line: line, nextLine: index + 1 < lines.count ? lines[index + 1] : "") {
                index += 2
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.isEmpty || !candidate.contains("|") { break }
                    index += 1
                }
                continue
            }
            result.append(line)
            index += 1
        }
        return result.joined(separator: "\n")
    }

    private static func isTableHeaderLine(line: String, nextLine: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let trimmedNext = nextLine.trimmingCharacters(in: .whitespaces)
        guard trimmedNext.contains("|") else { return false }
        let raw = trimmedNext.replacingOccurrences(of: "|", with: "")
        let valid = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-: "))
        return valid.isEmpty && raw.contains("-")
    }

    private static func dedupeMarkdownBlocks(_ markdown: String, dropLines: Set<String>) -> String {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var result: [String] = []
        var seenBullets = Set<String>()
        var seenParagraphs = Set<String>()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && dropLines.contains(trimmed) { continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let key = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && seenBullets.contains(key) { continue }
                if !key.isEmpty { seenBullets.insert(key) }
                result.append(line)
            } else if trimmed.hasPrefix("#") {
                result.append(line)
            } else if trimmed.isEmpty {
                result.append("")
            } else {
                if seenParagraphs.contains(trimmed) { continue }
                seenParagraphs.insert(trimmed)
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    private static func normalizeBlankLines(_ markdown: String) -> String {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var result: [String] = []
        var lastWasBlank = false
        for line in lines {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if blank {
                if !lastWasBlank { result.append("") }
            } else {
                result.append(line)
            }
            lastWasBlank = blank
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func segmentLongParagraphLines(_ markdown: String) -> String {
        var result: [String] = []
        var inCodeBlock = false
        for line in markdown.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                result.append(line)
                continue
            }
            if inCodeBlock || shouldKeepLineIntact(trimmed) {
                result.append(line)
                continue
            }

            let segments = splitLongParagraph(line)
            if segments.count == 1 {
                result.append(line)
            } else {
                for (index, segment) in segments.enumerated() {
                    if index > 0 { result.append("") }
                    result.append(segment)
                }
            }
        }
        return result.joined(separator: "\n")
    }

    private static func shouldKeepLineIntact(_ line: String) -> Bool {
        line.isEmpty ||
        line.hasPrefix("#") ||
        line.hasPrefix("|") ||
        line.hasPrefix(">") ||
        line.hasPrefix("- ") ||
        line.hasPrefix("* ") ||
        line.hasPrefix("- [") ||
        line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil
    }

    private static func splitLongParagraph(_ paragraph: String) -> [String] {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return [trimmed] }

        let protected = ["AppIcon.appiconset", "Assets.xcassets", "project.pbxproj", "Info.plist"]
        var working = trimmed
        var placeholders: [String: String] = [:]
        for (index, token) in protected.enumerated() where working.contains(token) {
            let placeholder = "__NL_TOKEN_\(index)__"
            placeholders[placeholder] = token
            working = working.replacingOccurrences(of: token, with: placeholder)
        }

        let pieces = working.splitAfterSentencePunctuation()
        guard pieces.count > 1 else { return [trimmed] }

        var segments: [String] = []
        var current = ""
        for piece in pieces {
            let candidate = current.isEmpty ? piece : current + piece
            if candidate.count > 120, !current.isEmpty {
                segments.append(restoreProtectedTokens(current, placeholders: placeholders))
                current = piece
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            segments.append(restoreProtectedTokens(current, placeholders: placeholders))
        }
        return segments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func restoreProtectedTokens(_ text: String, placeholders: [String: String]) -> String {
        var restored = text
        for (placeholder, token) in placeholders {
            restored = restored.replacingOccurrences(of: placeholder, with: token)
        }
        return restored
    }

    private static func shouldLabelBody(_ markdown: String) -> Bool {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lines = trimmed.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return false
        }
        return trimmed.count >= 120
    }

    private static func buildDropLines(report: AINoteInsightReport) -> Set<String> {
        var lines: Set<String> = []
        let summary = report.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { lines.insert(summary) }
        for section in report.sections {
            for paragraph in section.paragraphs {
                let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { lines.insert(text) }
            }
            for bullet in section.bullets {
                let text = bullet.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { lines.insert(text) }
            }
        }
        return lines
    }

    private static func markdownTable(from table: AIReportTable) -> String {
        guard !table.columns.isEmpty else { return "" }
        let headerLine = "| " + table.columns.joined(separator: " | ") + " |"
        let separatorLine = "| " + Array(repeating: "---", count: table.columns.count).joined(separator: " | ") + " |"
        var lines: [String] = [headerLine, separatorLine]
        for row in table.rows {
            let cells = table.columns.indices.map { index -> String in
                index < row.count ? row[index] : ""
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    private static func isLowValueTodoStatusTable(_ table: AIReportTable) -> Bool {
        let title = normalizedTableText(table.title)
        let columns = table.columns.map(normalizedTableText)
        let hasTaskColumn = columns.contains { $0.contains("任务") || $0.contains("待办") || $0.contains("事项") || $0.contains("标题") }
        let hasStatusColumn = columns.contains { $0.contains("状态") }
        let looksLikeTodoTable = title.contains("待办") || title.contains("任务") || title.contains("事项")
        guard hasTaskColumn, hasStatusColumn, looksLikeTodoTable else { return false }

        guard let statusIndex = columns.firstIndex(where: { $0.contains("状态") }) else { return false }
        let statuses = table.rows.compactMap { row -> String? in
            guard statusIndex < row.count else { return nil }
            let status = normalizedTableText(row[statusIndex])
            return status.isEmpty ? nil : status
        }
        guard !statuses.isEmpty else { return true }
        let lowValueStatuses: Set<String> = ["待办", "代办", "未完成", "todo", "open", "pending"]
        return statuses.allSatisfy { lowValueStatuses.contains($0) }
    }

    nonisolated private static func normalizedTableText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
    }
}

private extension String {
    func splitAfterSentencePunctuation() -> [String] {
        var pieces: [String] = []
        var current = ""
        let delimiters = Set<Character>(["。", "；", ";", "!", "！", "?", "？"])
        for character in self {
            current.append(character)
            if delimiters.contains(character) {
                pieces.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pieces.append(current)
        }
        return pieces
    }
}
