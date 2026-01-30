import Foundation

struct AIEnvelope<T: Decodable>: Decodable {
    let requestId: String
    let cacheHit: Bool
    let provider: String
    let model: String
    let latencyMs: Int
    let schemaVersion: Int
    let data: T
}

struct AIFormatData: Codable {
    let title: String
    let summary: String
    let sections: [AISection]
    let highlights: [AIHighlight]
    let metrics: AIMetrics
    let formattedMarkdown: String
}

struct AINoteInsightData: Decodable {
    let formattedMarkdown: String
    let report: AINoteInsightReport
    let tasks: [AITaskSuggestion]?
}

struct AINoteInsightReport: Decodable {
    let title: String
    let summary: String
    let sections: [AIReportSection]
    let tables: [AIReportTable]
}

struct AISection: Codable {
    let heading: String
    let bullets: [String]
    let paragraphs: [String]
}

struct AIHighlight: Codable {
    let text: String
    let anchor: AIAnchor
}

struct AIMetrics: Codable {
    let paragraphCount: Int
    let bulletCount: Int
    let checklistCount: Int
}

struct AIAnchor: Codable {
    let paragraphIndex: Int
}

struct AIExtractTasksData: Decodable {
    let tasks: [AITaskSuggestion]
}

struct AIHighlightsData: Decodable {
    let highlights: [AIHighlightSuggestion]
}

struct AIConnectionData: Decodable {
    let connections: [AIConnectionSuggestion]
}

struct AIConnectionSuggestion: Decodable, Identifiable {
    let sourceNoteId: String
    let targetNoteId: String
    let reason: String

    var id: String { "\(sourceNoteId)->\(targetNoteId)" }
}

struct AIRewriteData: Decodable {
    let title: String?
    let markdown: String
}

struct AIHighlightSuggestion: Decodable, Identifiable {
    let color: String
    let text: String

    var id: String { "\(color)-\(text)" }

    var normalizedColor: String {
        let key = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed: Set<String> = ["yellow", "green", "blue", "pink", "orange", "purple"]
        return allowed.contains(key) ? key : "yellow"
    }
}

struct AITaskSuggestion: Decodable, Identifiable {
    var id: String { "\(sourceAnchor.paragraphIndex)-\(text)" }
    let text: String
    let dueDate: String?
    let priority: String
    let confidence: Double
    let sourceAnchor: AIAnchor

    var normalizedDueDate: String? {
        guard let dueDate = dueDate, dueDate != "omit" else { return nil }
        return dueDate
    }
}

struct AIPlanData: Codable {
    let topFocus: AITopFocus
    let actionQueue: [AIPlannedAction]
    let risks: [AIRisk]
    let rationale: String
}

struct AITopFocus: Codable {
    let text: String
    let estMinutes: Int
    let sourceRefs: [AITaskRef]?
}

struct AITaskRef: Codable {
    let taskId: String?
}

struct AIPlannedAction: Codable, Identifiable {
    var id: String { (taskId ?? text) + "-" + scheduledDate }
    let taskId: String?
    let text: String
    let estMinutes: Int?
    let scheduledDate: String
    let sourceRef: AISourceRef?
}

struct AISourceRef: Codable {
    let noteTitle: String?
    let noteId: String?
    let notebookId: String?
    let sourceAnchor: AIAnchor?
}

struct AIRisk: Codable, Identifiable {
    var id: String { text }
    let text: String
    let suggestion: String?
    let draftMessage: String?
}

struct PlanTaskRequest: Encodable {
    let id: String
    let text: String
    let priority: String?
    let source: PlanTaskSource?
    let sourceAnchor: PlanTaskAnchor?
}

struct PlanTaskSource: Encodable {
    let noteTitle: String
    let notebookTitle: String
    let noteId: String?
    let notebookId: String?
}

struct PlanTaskAnchor: Encodable {
    let paragraphIndex: Int
}

struct NoteDigest: Encodable {
    let noteId: String
    let noteTitle: String
    let notebookTitle: String
    let createdAt: String
    let headings: [String]
    let bullets: [String]
    let snippet: String
}

struct AIRecentFocusReport: Codable {
    let title: String
    let summary: String
    let timeRangeLabel: String
    let sections: [AIReportSection]
    let tables: [AIReportTable]
    let sources: [AIReportSourceNote]
}

struct AIReportSection: Codable {
    let heading: String
    let paragraphs: [String]
    let bullets: [String]
}

struct AIReportTable: Codable {
    let title: String
    let columns: [String]
    let rows: [[String]]
    let notes: String?
}

struct AIReportSourceNote: Codable {
    let noteId: String
    let noteTitle: String
    let notebookTitle: String
    let createdAt: String
}
