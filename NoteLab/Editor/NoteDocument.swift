import Foundation

struct NoteDocument: Codable, Equatable {
    var version: Int
    var blocks: [Block]

    static func fromPlainText(_ text: String) -> NoteDocument {
        let trimmed = text.trimmingCharacters(in: .newlines)
        if trimmed.isEmpty {
            return NoteDocument(version: 1, blocks: [Block.paragraph("" )])
        }
        let paragraphs = text
            .split(separator: "\n\n", omittingEmptySubsequences: false)
            .map { String($0) }
        let blocks = paragraphs.map { Block.paragraph($0) }
        return NoteDocument(version: 1, blocks: blocks)
    }

    static func fromMarkdown(_ text: String) -> NoteDocument {
        let trimmed = text.trimmingCharacters(in: .newlines)
        if trimmed.isEmpty {
            return NoteDocument(version: 1, blocks: [Block.paragraph("")])
        }

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var blocks: [Block] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            let joined = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraphBuffer.removeAll()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                flushParagraph()
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                blocks.append(.code(codeLines.joined(separator: "\n")))
                index += 1
                continue
            }

            if isTableHeader(line: trimmedLine, nextLine: index + 1 < lines.count ? lines[index + 1] : "") {
                flushParagraph()
                let headerCells = splitTableRow(lines[index])
                let separatorLineIndex = index + 1
                var rowLines: [[String]] = []
                var rowIndex = separatorLineIndex + 1
                while rowIndex < lines.count {
                    let candidate = lines[rowIndex].trimmingCharacters(in: .whitespaces)
                    if candidate.isEmpty || !candidate.contains("|") { break }
                    rowLines.append(splitTableRow(lines[rowIndex]))
                    rowIndex += 1
                }

                let colCount = max(headerCells.count, rowLines.map { $0.count }.max() ?? 0, 1)
                let rowCount = max(rowLines.count + 1, 1)
                var table = TableModel(rows: rowCount, cols: colCount)
                for col in 0..<colCount {
                    table.cells[0][col] = col < headerCells.count ? headerCells[col] : ""
                }
                for row in 0..<rowLines.count {
                    for col in 0..<colCount {
                        table.cells[row + 1][col] = col < rowLines[row].count ? rowLines[row][col] : ""
                    }
                }
                blocks.append(Block(id: UUID(), kind: .table, text: "", level: nil, isChecked: nil, table: table, attachment: nil, fontSizeOffset: nil))
                index = rowIndex
                continue
            }

            if trimmedLine.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let attachment = parseAttachment(trimmedLine) {
                flushParagraph()
                let type: AttachmentType = attachment.fileName.lowercased().hasSuffix(".pdf") ? .pdf : .image
                blocks.append(.attachment(type: type, fileName: attachment.fileName, storagePath: attachment.storagePath, attachmentId: attachment.attachmentId))
                index += 1
                continue
            }

            if let heading = parseHeading(trimmedLine) {
                flushParagraph()
                blocks.append(.heading(heading.level, text: heading.text))
                index += 1
                continue
            }

            if let todo = parseTodo(trimmedLine) {
                flushParagraph()
                blocks.append(.todo(todo.text, checked: todo.isChecked))
                index += 1
                continue
            }

            if let bullet = parseBullet(trimmedLine) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                index += 1
                continue
            }

            if let numbered = parseNumbered(trimmedLine) {
                flushParagraph()
                blocks.append(.numbered(numbered))
                index += 1
                continue
            }

            if let quote = parseQuote(trimmedLine) {
                flushParagraph()
                blocks.append(.quote(quote))
                index += 1
                continue
            }

            paragraphBuffer.append(line)
            index += 1
        }

        flushParagraph()
        return NoteDocument(version: 1, blocks: blocks.isEmpty ? [Block.paragraph("")] : blocks)
    }

    func flattenPlainText() -> String {
        blocks.map { $0.plainText }.joined(separator: "\n\n")
    }

    func flattenMarkdown() -> String {
        blocks.map { $0.markdownText }.joined(separator: "\n\n")
    }
}

enum BlockKind: String, Codable {
    case paragraph
    case heading
    case bullet
    case numbered
    case todo
    case quote
    case code
    case table
    case attachment
}

struct AttachmentModel: Codable, Equatable {
    let id: UUID
    let type: AttachmentType
    let fileName: String
    
    /// Storage path in Supabase Storage (new way)
    let storagePath: String?
    
    /// Legacy: embedded data (for backward compatibility, will be migrated)
    /// New attachments should NOT use this field
    let data: Data?
    
    /// Whether this attachment uses storage (storagePath) or embedded data
    var usesStorage: Bool {
        storagePath != nil && !storagePath!.isEmpty
    }
    
    init(id: UUID, type: AttachmentType, fileName: String, storagePath: String? = nil, data: Data? = nil) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.storagePath = storagePath
        self.data = data
    }
}

enum AttachmentType: String, Codable {
    case image
    case pdf
}

struct Block: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: BlockKind
    var text: String
    var level: Int?
    var isChecked: Bool?
    var table: TableModel?
    var attachment: AttachmentModel?
    var fontSizeOffset: CGFloat?

    static func paragraph(_ text: String) -> Block {
        Block(id: UUID(), kind: .paragraph, text: text, level: nil, isChecked: nil, table: nil, attachment: nil, fontSizeOffset: nil)
    }

    static func heading(_ level: Int, text: String) -> Block {
        Block(id: UUID(), kind: .heading, text: text, level: level, isChecked: nil, table: nil, attachment: nil, fontSizeOffset: nil)
    }

    static func bullet(_ text: String) -> Block {
        Block(id: UUID(), kind: .bullet, text: text, level: nil, isChecked: nil, table: nil, attachment: nil, fontSizeOffset: nil)
    }

    static func numbered(_ text: String) -> Block {
        Block(id: UUID(), kind: .numbered, text: text, level: nil, isChecked: nil, table: nil, attachment: nil, fontSizeOffset: nil)
    }

    static func todo(_ text: String, checked: Bool = false) -> Block {
        Block(id: UUID(), kind: .todo, text: text, level: nil, isChecked: checked, table: nil, attachment: nil, fontSizeOffset: nil)
    }

    static func quote(_ text: String) -> Block {
        Block(id: UUID(), kind: .quote, text: text, level: nil, isChecked: nil, table: nil, attachment: nil, fontSizeOffset: nil)
    }

    static func code(_ text: String) -> Block {
        Block(id: UUID(), kind: .code, text: text, level: nil, isChecked: nil, table: nil, attachment: nil, fontSizeOffset: nil)
    }

    static func table(rows: Int, cols: Int) -> Block {
        Block(id: UUID(), kind: .table, text: "", level: nil, isChecked: nil, table: TableModel(rows: rows, cols: cols), attachment: nil, fontSizeOffset: nil)
    }

    /// Create attachment block with storage path reference (new way)
    static func attachment(type: AttachmentType, fileName: String, storagePath: String?, attachmentId: UUID) -> Block {
        let model = AttachmentModel(id: attachmentId, type: type, fileName: fileName, storagePath: storagePath, data: nil)
        return Block(id: UUID(), kind: .attachment, text: "", level: nil, isChecked: nil, table: nil, attachment: model, fontSizeOffset: nil)
    }
    
    /// Create attachment block with embedded data (legacy, for backward compatibility)
    static func attachment(type: AttachmentType, fileName: String, data: Data) -> Block {
        let model = AttachmentModel(id: UUID(), type: type, fileName: fileName, storagePath: nil, data: data)
        return Block(id: UUID(), kind: .attachment, text: "", level: nil, isChecked: nil, table: nil, attachment: model, fontSizeOffset: nil)
    }

    var plainText: String {
        switch kind {
        case .paragraph:
            return text
        case .heading:
            return text
        case .bullet:
            return "- " + text
        case .numbered:
            return "1. " + text
        case .todo:
            let checked = isChecked ?? false
            return (checked ? "- [x] " : "- [ ] ") + text
        case .quote:
            return "> " + text
        case .code:
            return text
        case .table:
            return table?.plainText ?? ""
        case .attachment:
            return "[Attachment: \(attachment?.fileName ?? "unknown")]"
        }
    }

    var markdownText: String {
        switch kind {
        case .paragraph:
            return text
        case .heading:
            let level = max(1, min(level ?? 1, 6))
            return String(repeating: "#", count: level) + " " + text
        case .bullet:
            return "- " + text
        case .numbered:
            return "1. " + text
        case .todo:
            let checked = isChecked ?? false
            return (checked ? "- [x] " : "- [ ] ") + text
        case .quote:
            return "> " + text
        case .code:
            return "```\n" + text + "\n```"
        case .table:
            return markdownTable(from: table)
        case .attachment:
            let target = attachment?.storagePath ?? attachment?.fileName ?? "unknown"
            return "![Attachment](\(target))"
        }
    }
}

private func parseHeading(_ line: String) -> (level: Int, text: String)? {
    guard line.hasPrefix("#") else { return nil }
    let level = line.prefix { $0 == "#" }.count
    guard level > 0 && level <= 6 else { return nil }
    let prefix = String(repeating: "#", count: level) + " "
    guard line.hasPrefix(prefix) else { return nil }
    let text = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    return (level, text)
}

private func parseTodo(_ line: String) -> (text: String, isChecked: Bool)? {
    if line.hasPrefix("- [ ] ") {
        return (String(line.dropFirst(6)), false)
    }
    if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
        return (String(line.dropFirst(6)), true)
    }
    return nil
}

private func parseBullet(_ line: String) -> String? {
    if line.hasPrefix("- ") {
        return String(line.dropFirst(2))
    }
    if line.hasPrefix("* ") {
        return String(line.dropFirst(2))
    }
    if line.hasPrefix("• ") {
        return String(line.dropFirst(2))
    }
    return nil
}

private func parseNumbered(_ line: String) -> String? {
    let chars = Array(line)
    var idx = 0
    while idx < chars.count, chars[idx].isNumber { idx += 1 }
    guard idx > 0, idx + 1 < chars.count, chars[idx] == ".", chars[idx + 1] == " " else { return nil }
    let start = line.index(line.startIndex, offsetBy: idx + 2)
    return String(line[start...])
}

private func parseQuote(_ line: String) -> String? {
    if line.hasPrefix("> ") {
        return String(line.dropFirst(2))
    }
    return nil
}

private func parseAttachment(_ line: String) -> (fileName: String, storagePath: String, attachmentId: UUID)? {
    guard line.hasPrefix("![Attachment]("), line.hasSuffix(")") else { return nil }
    let start = line.index(line.startIndex, offsetBy: "![Attachment](".count)
    let end = line.index(before: line.endIndex)
    let target = String(line[start..<end]).trimmingCharacters(in: .whitespaces)
    guard !target.isEmpty else { return nil }

    // If target looks like a storage path (e.g. "{userId}/{uuid}.jpg"), extract fileName and UUID.
    let fileName = (target as NSString).lastPathComponent
    let base = (fileName as NSString).deletingPathExtension
    let attachmentId = UUID(uuidString: base) ?? UUID()

    return (fileName: fileName.isEmpty ? "attachment" : fileName, storagePath: target, attachmentId: attachmentId)
}

private func isTableHeader(line: String, nextLine: String) -> Bool {
    guard line.contains("|") else { return false }
    let trimmedNext = nextLine.trimmingCharacters(in: .whitespaces)
    guard trimmedNext.contains("|") else { return false }
    let raw = trimmedNext.replacingOccurrences(of: "|", with: "")
    let valid = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-: "))
    return valid.isEmpty && raw.contains("-")
}

private func splitTableRow(_ line: String) -> [String] {
    var trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") { trimmed.removeFirst() }
    if trimmed.hasSuffix("|") { trimmed.removeLast() }
    return trimmed.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
}

private func markdownTable(from table: TableModel?) -> String {
    guard let table else { return "" }
    let cols = max(table.cols, 1)
    let rows = max(table.rows, 1)
    let header = (0..<cols).map { col in
        col < table.cells[0].count ? table.cells[0][col] : ""
    }
    let headerLine = "| " + header.joined(separator: " | ") + " |"
    let separatorLine = "| " + Array(repeating: "---", count: cols).joined(separator: " | ") + " |"
    var lines: [String] = [headerLine, separatorLine]
    if rows > 1 {
        for row in 1..<rows {
            let cells = (0..<cols).map { col in
                col < table.cells[row].count ? table.cells[row][col] : ""
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
    }
    return lines.joined(separator: "\n")
}
