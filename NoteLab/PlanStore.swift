import Foundation
import Combine
import CryptoKit

@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var report: AIRecentFocusReport?
    @Published private(set) var rawReportMarkdown: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var hasCachedRecentFocus: Bool {
        report != nil || rawReportMarkdown != nil
    }

    var lastRecentFocusUpdatedAt: Date? {
        cache.updatedAt(key: cacheKey)
    }

    private let cacheKey = "plan.recentFocus.cache"
    private let reportInputHashKey = "plan.recentFocus.inputHash"
    private let refreshInterval: TimeInterval = 24 * 60 * 60
    private let cache = AIResponseCache.shared

    init() {
        load()
    }

    func resetForSignOut() {
        report = nil
        rawReportMarkdown = nil
        isLoading = false
        errorMessage = nil
        cache.clear(key: cacheKey)
        UserDefaults.standard.removeObject(forKey: reportInputHashKey)
    }

    func needsRecentFocus(inputHash: String) -> Bool {
        if report == nil && rawReportMarkdown == nil { return true }
        if storedInputHash() != inputHash { return true }
        return !cache.isValid(key: cacheKey, maxAge: refreshInterval)
    }

    func shouldGenerateRecentFocus(for digests: [NoteDigest], providerId: String, modelName: String, limit: Int) -> Bool {
        if digests.isEmpty { return false }
        let hash = inputHash(for: digests, providerId: providerId, modelName: modelName, limit: limit)
        return needsRecentFocus(inputHash: hash)
    }

    func generateRecentFocusIfNeeded(
        digests: [NoteDigest],
        aiClient: AIClient,
        providerId: String,
        modelName: String,
        limit: Int
    ) async {
        if digests.isEmpty { return }
        let hash = inputHash(for: digests, providerId: providerId, modelName: modelName, limit: limit)
        if !needsRecentFocus(inputHash: hash) {
            return
        }
        await generateRecentFocus(digests: digests, inputHash: hash, aiClient: aiClient)
    }

    func regenerateRecentFocus(
        digests: [NoteDigest],
        aiClient: AIClient,
        providerId: String,
        modelName: String,
        limit: Int
    ) async {
        if digests.isEmpty { return }
        let hash = inputHash(for: digests, providerId: providerId, modelName: modelName, limit: limit)
        await generateRecentFocus(digests: digests, inputHash: hash, aiClient: aiClient)
    }

    private func generateRecentFocus(
        digests: [NoteDigest],
        inputHash: String,
        aiClient: AIClient
    ) async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil

        do {
            let payload = try await aiClient.recentFocusPayload(digests: digests)
            report = payload.report
            rawReportMarkdown = payload.markdown
            if report == nil, let markdown = payload.markdown, let parsed = decodeReport(from: markdown) {
                report = parsed
            }
            let cachePayload = RecentFocusCachePayload(report: report, markdown: rawReportMarkdown)
            cache.save(key: cacheKey, value: cachePayload)
            persistInputHash(inputHash)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func load() {
        if let cached: RecentFocusCachePayload = cache.load(key: cacheKey, maxAge: refreshInterval) {
            report = cached.report
            rawReportMarkdown = cached.markdown
        }
    }

    private func inputHash(for digests: [NoteDigest], providerId: String, modelName: String, limit: Int) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = RecentFocusInputPayload(
            providerId: providerId,
            modelName: modelName,
            limit: limit,
            digests: digests
        )
        guard let data = try? encoder.encode(payload) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func persistInputHash(_ hash: String) {
        UserDefaults.standard.set(hash, forKey: reportInputHashKey)
    }

    private func storedInputHash() -> String? {
        UserDefaults.standard.string(forKey: reportInputHashKey)
    }

    private func decodeReport(from markdown: String) -> AIRecentFocusReport? {
        guard let json = extractJSON(from: markdown) else { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIRecentFocusReport.self, from: data)
    }

    private func extractJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return trimmed
        }
        if let start = trimmed.firstIndex(of: "{") {
            if let end = trimmed.lastIndex(of: "}") {
                if start < end {
                    return String(trimmed[start...end])
                }
            }
        }
        return nil
    }
}

private struct RecentFocusCachePayload: Codable {
    let report: AIRecentFocusReport?
    let markdown: String?
}

private struct RecentFocusInputPayload: Encodable {
    let providerId: String
    let modelName: String
    let limit: Int
    let digests: [NoteDigest]
}
