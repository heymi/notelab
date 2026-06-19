import Foundation

import Foundation

struct Notebook: Identifiable, Hashable {
    let id: UUID
    var title: String
    var color: NotebookColor
    var iconName: String
    var createdAt: Date
    var notes: [Note]
    var isPinned: Bool = false
    /// 笔记本背景介绍，用于AI分析时提供上下文
    var notebookDescription: String = ""
}

struct Note: Identifiable, Hashable {
    let id: UUID
    var title: String
    var summary: String
    var paragraphCount: Int
    var bulletCount: Int
    var hasAdditionalContext: Bool
    var createdAt: Date
    var updatedAt: Date = Date()
    var contentRTF: Data?
    var content: String
    var isPinned: Bool = false
}

enum VoiceNoteStatus: String, Codable, Hashable, CaseIterable {
    case recording
    case transcribing
    case organizing
    case completed
    case failed
    case needsAI

    nonisolated var displayText: String {
        switch self {
        case .recording:
            return "正在录音"
        case .transcribing:
            return "正在转写"
        case .organizing:
            return "正在分析"
        case .completed:
            return "已完成"
        case .failed:
            return "处理失败"
        case .needsAI:
            return "待整理"
        }
    }

    nonisolated var isProcessing: Bool {
        self == .transcribing || self == .organizing
    }
}

struct VoiceNoteRecord: Identifiable, Hashable {
    let id: UUID
    let profileId: UUID
    let noteId: UUID
    let notebookId: UUID
    let audioAttachmentId: UUID
    let audioStoragePath: String
    let audioFileName: String
    var duration: TimeInterval
    var status: VoiceNoteStatus
    var rawTranscript: String
    var errorMessage: String?
    var retryCount: Int
    var createdAt: Date
    var updatedAt: Date
}

enum NotebookColor: String, CaseIterable, Hashable {
    case lime
    case sky
    case orange
    case lavender
    case mint
    case teal
    case sand
}

extension NotebookColor {
    var displayName: String {
        switch self {
        case .lime:
            return "Lime"
        case .sky:
            return "Sky"
        case .orange:
            return "Orange"
        case .lavender:
            return "Lavender"
        case .mint:
            return "Mint"
        case .teal:
            return "Teal"
        case .sand:
            return "Sand"
        }
    }
}

extension Note {
    var contextText: String {
        if !summary.isEmpty {
            return summary
        }
        if hasAdditionalContext {
            return "\(paragraphCount) 段落，\(bulletCount) 要点"
        }
        if paragraphCount == 0 && bulletCount == 0 {
            return "暂无上下文"
        }
        return "\(paragraphCount) 段落，\(bulletCount) 要点"
    }
}

extension Note {
    mutating func updateMetrics() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            paragraphCount = 0
            bulletCount = 0
            hasAdditionalContext = false
            return
        }

        let paragraphSegments = content
            .split(separator: "\n\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        paragraphCount = paragraphSegments.count

        let bulletLines = content
            .split(whereSeparator: \ .isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        bulletCount = bulletLines.filter { line in
            line.hasPrefix("- [ ]") ||
            line.hasPrefix("- [x]") ||
            line.hasPrefix("- [X]") ||
            line.hasPrefix("- ") ||
            line.hasPrefix("* ") ||
            line.hasPrefix("• ")
        }.count

        hasAdditionalContext = true
    }
}

enum NoteTitleDeriver {
    private static let structuralTitles: Set<String> = [
        "摘要",
        "ai摘要",
        "ai 摘要",
        "内容摘要",
        "正文",
        "待办",
        "待办事项",
        "任务",
        "需求整理"
    ]

    static func title(from document: NoteDocument, fallback: String = "") -> String {
        title(from: document, fallback: fallback, ignoringGeneratedSummary: nil)
    }

    static func title(from document: NoteDocument, fallback: String = "", ignoringGeneratedSummary summary: String?) -> String {
        let generatedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for block in document.blocks {
            guard block.kind != .attachment, block.kind != .table else { continue }
            let title = cleanedTitleLine(block.text)
            guard !title.isEmpty else { continue }
            if isStructuralTitle(title) {
                continue
            }
            if !generatedSummary.isEmpty && title == generatedSummary {
                continue
            }
            return clipped(title)
        }
        return fallback
    }

    static func title(fromMarkdown markdown: String, fallback: String = "") -> String {
        title(from: NoteDocument.fromMarkdown(markdown), fallback: fallback)
    }

    static func title(fromAI rawTitle: String?, fallback: String = "") -> String {
        let cleaned = cleanedTitleLine(rawTitle ?? "")
        guard !cleaned.isEmpty, !isStructuralTitle(cleaned) else { return fallback }
        return clippedAITitle(cleaned)
    }

    static func cleanedTitleLine(_ text: String) -> String {
        guard let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first
        else {
            return ""
        }

        var line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^#{1,6}\s+"#,
            #"^>\s+"#,
            #"^- \[[ xX]\]\s+"#,
            #"^[-*•]\s+"#,
            #"^\d+[.)]\s+"#
        ]
        for pattern in patterns {
            line = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if line.hasPrefix("![") || line.hasPrefix("attachment:") {
            return ""
        }
        return line
    }

    private static func isStructuralTitle(_ title: String) -> Bool {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
        return structuralTitles.contains(normalized)
    }

    private static func clipped(_ title: String) -> String {
        let maxCount = 64
        guard title.count > maxCount else { return title }
        return String(title.prefix(maxCount)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clippedAITitle(_ title: String) -> String {
        if title.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            guard title.count > 10 else { return title }
            return String(title.prefix(10)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        let byWords = words.count > 5 ? words.prefix(5).joined(separator: " ") : title
        guard byWords.count > 42 else { return byWords }
        return String(byWords.prefix(42)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AISummaryRegistry {
    private static let keyPrefix = "ai.summary.generated."

    static func mark(noteId: UUID, summary: String) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear(noteId: noteId)
            return
        }
        UserDefaults.standard.set(trimmed, forKey: key(for: noteId))
    }

    static func isGenerated(noteId: UUID, summary: String) -> Bool {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return UserDefaults.standard.string(forKey: key(for: noteId)) == trimmed
    }

    static func clear(noteId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: noteId))
    }

    private static func key(for noteId: UUID) -> String {
        keyPrefix + noteId.uuidString
    }
}

enum AISummaryText {
    static func normalized(_ summary: String) -> String {
        summary
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Notification Names
// Centralized notification names for cross-file visibility with Swift 6's MEMBER_IMPORT_VISIBILITY
extension Notification.Name {
    static let whiteboardSyncDidUpdate = Notification.Name("whiteboard.sync.didUpdate")
    static let profileSyncDidUpdate = Notification.Name("profile.sync.didUpdate")
    static let voiceNoteDidUpdate = Notification.Name("voice.note.didUpdate")
    static let voiceNoteRetryRequested = Notification.Name("voice.note.retryRequested")
}
