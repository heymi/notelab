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

// MARK: - Notification Names
// Centralized notification names for cross-file visibility with Swift 6's MEMBER_IMPORT_VISIBILITY
extension Notification.Name {
    static let whiteboardSyncDidUpdate = Notification.Name("whiteboard.sync.didUpdate")
    static let profileSyncDidUpdate = Notification.Name("profile.sync.didUpdate")
}
