import Foundation
import Combine
import os

enum AIClientError: Error {
    case invalidURL
    case missingAPIKey
    case missingSubscriptionCredential
    case quotaExhausted
    case badResponse(Int, String?)
    case decodingFailed
    case emptyResponse
}

enum AIRewriteMode: String {
    case optimize
    case dedupe
    case expand
}

extension AIClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的请求地址"
        case .missingAPIKey:
            return "请先在设置中配置 API Key"
        case .missingSubscriptionCredential:
            return "订阅凭证未同步，请恢复购买后重试云端 AI"
        case .quotaExhausted:
            return "本月 AI 点数已用完"
        case .badResponse(let status, let message):
            if let message, !message.isEmpty {
                return "请求失败 (\(status))：\(message)"
            }
            return "请求失败 (\(status))"
        case .decodingFailed:
            return "解析失败"
        case .emptyResponse:
            return "AI 返回空响应"
        }
    }
}

@MainActor
final class AIClient: ObservableObject {
    private let logger = Logger(subsystem: "NoteLab", category: "AI")
    private let requestTimeout: TimeInterval = 120
    private let aiSettings = AISettings.shared
    private let proxyURL = URL(string: "https://notelab.aedc.cc/v1/ai/generate")!

    private func ensureAPIKey() throws -> String {
        let key = aiSettings.currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIClientError.missingAPIKey }
        return key
    }

    func extractTasks(text: String) async throws -> [AITaskSuggestion] {
        let prompt = buildExtractTasksPrompt(text: text)
        let response = try await sendPrompt(prompt, feature: .extractTasks)
        let parsed = try decodeTasks(from: response)
        if !parsed.isEmpty {
            return parsed
        }
        logger.info("AI extractTasks empty result, retrying once")
        let retryResponse = try await sendPrompt(prompt, feature: .extractTasks)
        return try decodeTasks(from: retryResponse)
    }

    private func decodeTasks(from response: String) throws -> [AITaskSuggestion] {
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIExtractTasksData.self, from: data) else {
            logger.error("AI extractTasks decode failed response=\(Self.truncate(string: response), privacy: .public)")
            throw AIClientError.decodingFailed
        }
        return normalizeTasks(result.tasks)
    }

    func noteInsight(text: String, title: String, notebookContext: String? = nil, protectedAttachmentTokens: [String] = []) async throws -> (formattedMarkdown: String, report: AINoteInsightReport?, tasks: [AITaskSuggestion]) {
        let prompt = buildNoteInsightPrompt(text: text, title: title, notebookContext: notebookContext, protectedAttachmentTokens: protectedAttachmentTokens)
        let response = try await sendPrompt(prompt, feature: .organize)
        let parsed = try decodeNoteInsight(from: response)
        if parsed.report != nil {
            return parsed
        }
        logger.info("AI noteInsight missing report, retrying once")
        let retryResponse = try await sendPrompt(prompt, feature: .organize)
        return try decodeNoteInsight(from: retryResponse)
    }

    private func decodeNoteInsight(from response: String) throws -> (formattedMarkdown: String, report: AINoteInsightReport?, tasks: [AITaskSuggestion]) {
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8) else {
            logger.error("AI noteInsight invalid UTF8 response")
            throw AIClientError.decodingFailed
        }
        if let result = try? JSONDecoder().decode(AINoteInsightData.self, from: data) {
            logger.info("AI noteInsight parsed report successfully")
            return (result.formattedMarkdown, result.report, normalizeTasks(result.tasks ?? []))
        }
        if let partial = try? JSONDecoder().decode(AIPartialInsightData.self, from: data) {
            logger.info("AI noteInsight parsed partial data")
            return (partial.formattedMarkdown, nil, [])
        }
        logger.error("AI noteInsight decode failed response=\(Self.truncate(string: cleaned), privacy: .public)")
        throw AIClientError.decodingFailed
    }

    private func normalizeTasks(_ tasks: [AITaskSuggestion]) -> [AITaskSuggestion] {
        var seen = Set<String>()
        var normalized: [AITaskSuggestion] = []
        for task in tasks {
            let text = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .lowercased()
            guard seen.insert(key).inserted else { continue }
            normalized.append(task)
            if normalized.count == 7 { break }
        }
        return normalized
    }

    func supplementHighlights(text: String, maxHighlights: Int) async throws -> [AIHighlightSuggestion] {
        let prompt = buildHighlightSupplementPrompt(text: text, maxHighlights: maxHighlights)
        let response = try await sendPrompt(prompt, feature: .highlight)
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIHighlightsData.self, from: data) else {
            logger.error("AI supplementHighlights decode failed response=\(Self.truncate(string: response), privacy: .public)")
            throw AIClientError.decodingFailed
        }
        return result.highlights
    }

    func rewriteNote(
        text: String,
        title: String,
        notebookContext: String? = nil,
        mode: AIRewriteMode,
        protectedAttachmentTokens: [String] = []
    ) async throws -> (title: String?, markdown: String) {
        let prompt = buildRewritePrompt(
            text: text,
            title: title,
            notebookContext: notebookContext,
            mode: mode,
            protectedAttachmentTokens: protectedAttachmentTokens
        )
        let response = try await sendPrompt(prompt, feature: .rewrite)
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIRewriteData.self, from: data) else {
            logger.error("AI rewrite decode failed response=\(Self.truncate(string: cleaned), privacy: .public)")
            throw AIClientError.decodingFailed
        }
        let markdown = result.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if markdown.isEmpty {
            throw AIClientError.emptyResponse
        }
        return (result.title, markdown)
    }

    func organizeVoiceTranscript(
        rawTranscript: String,
        titleHint: String,
        notebookContext: String? = nil
    ) async throws -> VoiceNoteAIResult {
        let prompt = buildVoiceNotePrompt(
            rawTranscript: rawTranscript,
            titleHint: titleHint,
            notebookContext: notebookContext
        )
        let response = try await sendPrompt(prompt, feature: .organize)
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(VoiceNoteAIResult.self, from: data) else {
            logger.error("AI voice note decode failed response=\(Self.truncate(string: cleaned), privacy: .public)")
            throw AIClientError.decodingFailed
        }
        let markdown = result.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else { throw AIClientError.emptyResponse }
        let title = NoteTitleDeriver.title(fromAI: result.title, fallback: titleHint)
        return VoiceNoteAIResult(
            title: title.isEmpty ? "语音笔记" : title,
            summary: AISummaryText.normalized(result.summary),
            markdown: markdown
        )
    }

    func plan(mode: String, goal: String, tasks: [PlanTaskRequest]) async throws -> AIPlanData {
        let prompt = buildPlanPrompt(mode: mode, goal: goal, tasks: tasks)
        let response = try await sendPrompt(prompt, feature: .plan)
        
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIPlanData.self, from: data) else {
            logger.error("AI plan decode failed response=\(Self.truncate(string: response), privacy: .public)")
            throw AIClientError.decodingFailed
        }
        return result
    }

    func recentFocusPayload(digests: [NoteDigest]) async throws -> (report: AIRecentFocusReport?, markdown: String?) {
        let prompt = buildRecentFocusPrompt(digests: digests)
        let response = try await sendPrompt(prompt, feature: .recentFocus)
        
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8) else {
            return (nil, response)
        }
        
        if let result = try? JSONDecoder().decode(AIRecentFocusReport.self, from: data) {
            logger.info("AI recentFocus parsed report successfully")
            return (result, nil)
        }
        
        return (nil, response)
    }

    func semanticConnections(digests: [NoteDigest], limit: Int) async throws -> [AIConnectionSuggestion] {
        guard !digests.isEmpty, limit > 0 else { return [] }
        let prompt = buildConnectionPrompt(digests: digests, limit: limit)
        let response = try await sendPrompt(prompt, feature: .semanticConnections)
        let cleaned = cleanJSONResponse(response)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIConnectionData.self, from: data) else {
            logger.error("AI semanticConnections decode failed response=\(Self.truncate(string: cleaned), privacy: .public)")
            throw AIClientError.decodingFailed
        }
        return result.connections
    }
    
    // MARK: - Core Request Methods
    
    private func sendPrompt(_ prompt: String, feature: AIFeature) async throws -> String {
        guard let credential = await SubscriptionManager.shared.currentEntitlementCredential() else {
            throw AIClientError.missingSubscriptionCredential
        }

        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(AIProxyRequest(feature: feature.rawValue, prompt: prompt))

        logger.info("AI proxy request feature=\(feature.rawValue, privacy: .public)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.badResponse(-1, nil)
        }
        if http.statusCode == 402 {
            throw AIClientError.quotaExhausted
        }
        if !(200...299).contains(http.statusCode) {
            throw AIClientError.badResponse(http.statusCode, Self.extractErrorMessage(from: data))
        }
        guard let payload = try? JSONDecoder().decode(AIProxyResponse.self, from: data) else {
            logger.error("AI proxy response parse failed body=\(Self.truncate(data: data), privacy: .public)")
            throw AIClientError.decodingFailed
        }
        guard !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.emptyResponse
        }
        return payload.text
    }
    
    private func sendGeminiRequest(prompt: String, apiKey: String) async throws -> String {
        let model = AIProvider.gemini.modelName
        let url = AIProvider.gemini.baseURL
            .appendingPathComponent("models/\(model):generateContent")
        
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let finalURL = urlComponents.url else {
            throw AIClientError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 8192
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.badResponse(-1, nil)
        }
        
        if !(200...299).contains(http.statusCode) {
            logger.error("Gemini request failed status=\(http.statusCode, privacy: .public) body=\(Self.truncate(data: data), privacy: .public)")
            throw AIClientError.badResponse(http.statusCode, Self.extractErrorMessage(from: data))
        }
        
        // 解析 Gemini 响应
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            logger.error("Gemini response parse failed body=\(Self.truncate(data: data), privacy: .public)")
            throw AIClientError.emptyResponse
        }
        
        logger.info("Gemini request success bytes=\(data.count, privacy: .public)")
        return text
    }
    
    private func sendDeepSeekRequest(prompt: String, apiKey: String) async throws -> String {
        let url = AIProvider.deepseek.baseURL.appendingPathComponent("chat/completions")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let systemPrompt = """
你是 NoteLab 的助手。你必须只输出合法 JSON，不得包含任何额外文字或 markdown。
必须严格遵循 user 提示中的 JSON 结构，不要擅自添加/删除字段或改变 schema。
"""

        let body: [String: Any] = [
            "model": AIProvider.deepseek.modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 8192,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.badResponse(-1, nil)
        }
        
        if !(200...299).contains(http.statusCode) {
            logger.error("DeepSeek request failed status=\(http.statusCode, privacy: .public) body=\(Self.truncate(data: data), privacy: .public)")
            throw AIClientError.badResponse(http.statusCode, Self.extractErrorMessage(from: data))
        }
        
        // 解析 DeepSeek 响应 (OpenAI 格式)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            logger.error("DeepSeek response parse failed body=\(Self.truncate(data: data), privacy: .public)")
            throw AIClientError.emptyResponse
        }
        
        logger.info("DeepSeek request success bytes=\(data.count, privacy: .public)")
        return content
    }
    
    // MARK: - Helpers
    
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除 markdown 代码块标记
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(data: Data, limit: Int = 2048) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        return truncate(string: text, limit: limit)
    }
    
    private static func truncate(string: String, limit: Int = 2048) -> String {
        if string.count <= limit { return string }
        let end = string.index(string.startIndex, offsetBy: limit)
        return String(string[..<end]) + "..."
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Gemini 错误格式
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            // DeepSeek/OpenAI 错误格式
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            // 通用
            if let message = object["message"] as? String, !message.isEmpty {
                return message
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(500))
        }
        return nil
    }
}

// MARK: - Response Types

private struct AIPartialInsightData: Decodable {
    let formattedMarkdown: String
}

private struct AIProxyRequest: Encodable {
    let feature: String
    let prompt: String
}

private struct AIProxyResponse: Decodable {
    let text: String
}

private func buildRecentFocusPrompt(digests: [NoteDigest]) -> String {
    var lines: [String] = []
    lines.append("你是 NoteLab 的助手。请基于最近 3 篇笔记摘要生成‘最近重点报告’。")
    lines.append("只输出 JSON，不要输出任何额外文字、注释或 markdown。")
    lines.append("必须遵循以下 JSON 结构（字段必须存在，允许空数组/空字符串）：")
    lines.append("{")
    lines.append("  \"title\": string,")
    lines.append("  \"summary\": string,")
    lines.append("  \"timeRangeLabel\": string,")
    lines.append("  \"sections\": [ { \"heading\": string, \"paragraphs\": [string], \"bullets\": [string] } ],")
    lines.append("  \"tables\": [ { \"title\": string, \"columns\": [string], \"rows\": [[string]], \"notes\": string? } ],")
    lines.append("  \"sources\": [ { \"noteId\": string, \"noteTitle\": string, \"notebookTitle\": string, \"createdAt\": string } ]")
    lines.append("}")
    lines.append("要求：如果出现计划/安排/时间线/协作分工等结构性内容，必须放入 tables，时间粒度按天。columns<=6，rows<=12。")
    lines.append("timeRangeLabel 固定为 \"最近3篇\"。")
    lines.append("")
    lines.append("以下是笔记摘要：")

    for (index, digest) in digests.enumerated() {
        lines.append("笔记 \(index + 1):")
        lines.append("- noteId: \(digest.noteId)")
        lines.append("- noteTitle: \(digest.noteTitle)")
        lines.append("- notebookTitle: \(digest.notebookTitle)")
        lines.append("- createdAt: \(digest.createdAt)")
        if !digest.headings.isEmpty {
            lines.append("- headings: \(digest.headings.joined(separator: "; "))")
        }
        if !digest.bullets.isEmpty {
            lines.append("- bullets: \(digest.bullets.joined(separator: "; "))")
        }
        if !digest.snippet.isEmpty {
            lines.append("- snippet: \(digest.snippet)")
        }
        lines.append("")
    }

    return lines.joined(separator: "\n")
}

private func buildConnectionPrompt(digests: [NoteDigest], limit: Int) -> String {
    var lines: [String] = []
    lines.append("你是 NoteLab 的助手。请基于笔记摘要进行语义关联发现。")
    lines.append("只输出 JSON，不要输出任何额外文字、注释或 markdown。")
    lines.append("必须遵循以下 JSON 结构（字段必须存在，允许空数组）：")
    lines.append("{")
    lines.append("  \"connections\": [ { \"sourceNoteId\": string, \"targetNoteId\": string, \"reason\": string } ]")
    lines.append("}")
    lines.append("规则：")
    lines.append("1) 只能使用给定 noteId，不能编造。")
    lines.append("2) 不允许 sourceNoteId == targetNoteId。")
    lines.append("3) 不要输出重复或反向重复的连接。")
    lines.append("4) reason 需要体现语义关系（主题、背景、事件、人物、目标、问题等），禁止使用“关键词重合/待办/摘要”等字眼。")
    lines.append("5) reason 保持精炼，建议 6-18 个字。")
    lines.append("6) 最多输出 \(limit) 条；如果没有明显关联，返回空数组。")
    lines.append("")
    lines.append("以下是笔记摘要：")
    for (index, digest) in digests.enumerated() {
        lines.append("笔记 \(index + 1):")
        lines.append("- noteId: \(digest.noteId)")
        lines.append("- noteTitle: \(digest.noteTitle)")
        lines.append("- notebookTitle: \(digest.notebookTitle)")
        lines.append("- createdAt: \(digest.createdAt)")
        if !digest.headings.isEmpty {
            lines.append("- headings: \(digest.headings.joined(separator: "; "))")
        }
        if !digest.bullets.isEmpty {
            lines.append("- bullets: \(digest.bullets.joined(separator: "; "))")
        }
        if !digest.snippet.isEmpty {
            lines.append("- snippet: \(digest.snippet)")
        }
        lines.append("")
    }
    return lines.joined(separator: "\n")
}

private func buildNoteInsightPrompt(text: String, title: String, notebookContext: String? = nil, protectedAttachmentTokens: [String] = []) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let charCount = trimmed.count
    let isVeryShort = charCount < 40
    let isShort = charCount < 200

    var lines: [String] = []
    lines.append("你是 NoteLab 的助手。请对单篇笔记做‘格式化重写 + 结构化分析’，并返回严格 JSON。")
    lines.append("只输出 JSON，不要输出任何额外文字、注释或 markdown。")
    lines.append("必须遵循以下 JSON 结构（字段必须存在，允许空数组）：")
    lines.append("{")
    lines.append("  \"formattedMarkdown\": string,")
    lines.append("  \"report\": { \"title\": string, \"summary\": string, \"sections\": [ { \"heading\": string, \"paragraphs\": [string], \"bullets\": [string] } ], \"tables\": [ { \"title\": string, \"columns\": [string], \"rows\": [[string]], \"notes\": string? } ] },")
    lines.append("  \"tasks\": [ { \"text\": string, \"dueDate\": string?, \"priority\": string, \"confidence\": number, \"sourceAnchor\": { \"paragraphIndex\": number } } ]")
    lines.append("}")
    lines.append("输出规则：")
    lines.append("1) formattedMarkdown 只输出正文重写，不要包含标题(H1)、摘要/要点/待办/表格等结构内容。")
    lines.append("2) report 承担结构化内容：title/summary/sections/tables；tasks 只提取真正需要后续跟进、决策、交付、确认或沟通的事项，不要编造。")
    lines.append("2.0) report.title 必须是 AI 根据全文生成的短标题，中文不超过 10 个字；英文不超过 5 个词或 42 个字符。不能使用“摘要”“AI 摘要”“正文”“待办”“需求整理”等默认章节名或泛标题。")
    lines.append("2.1) tasks 字段必须存在（允许空数组）。")
    lines.append("2.2) report.tables 必须存在（允许空数组）。")
    lines.append("2.3) report.sections 必须存在（允许空数组）。")
    lines.append("3) 计划/排期/时间线/里程碑/协作分工等结构性内容，必须放入 report.tables（默认倾向按天时间线；允许根据内容自动选择表格列）。流程步骤、检查清单、操作指南优先放入正文 sections/tables，不要逐项转成待办。")
    lines.append("3.1) report.tables 禁止生成“任务/状态”“待办/状态”这类假状态表；状态列如果全是“待办/未完成”没有信息价值，必须省略。真正待办只放 tasks 数组，由应用渲染为可勾选清单。")
    lines.append("3.2) 如果确实需要用表格表达任务规划，表头必须包含“序号/标题/类型/重要程度”中的至少三项，不能只包含“任务/状态”。")
    lines.append("4) 明确的后续行动必须输出到 tasks 数组（不要只写在正文里），但同一目标下的连续小步骤要合并为一个较高层级任务。")
    lines.append("4.1) 不要把 tasks 或 tables 放进 formattedMarkdown（否则会被去重剥离）。")
    lines.append("5) 代码/命令/配置片段必须使用 fenced code block：```代码```。")
    lines.append("6) 需要强调的重点请使用高亮语法：==yellow:重要内容==。可选颜色：yellow/green/blue/pink/orange/purple。")
    lines.append("7) 高亮目标数量按字数分档：短文(<=200字)0-2处；中等(200-800字)3-5处；长文(>800字)5-8处。若字数 > 200，至少 3 处高亮。")
    lines.append("8) 高亮粒度优先 2-12 个字的短语，必要时可高亮整句；不要在代码块内插入高亮。")
    lines.append("9) 高亮内容类型优先：结论/决定、风险/注意事项、关键数字/日期、下一步、关键配置/命令说明。")
    lines.append("10) 禁止逐句复述原文，必须重组为“信息架构/数据规则/交互流程/校验规则/待办任务”。")
    lines.append("10.1) 不要输出大段文字墙。每个 paragraph 建议 40-120 个中文字符；超过 160 个中文字符必须按主题拆成多个 paragraph 或 bullets。")
    lines.append("10.2) 工作流、规则、步骤、排查过程优先拆成小标题 + bullets/numbered list；不要把多个流程节点塞进一个 paragraph。")
    lines.append("11) 字段清单必须输出为 Markdown 表格（至少 1 张表）。")
    lines.append("12) 不要为了凑数量生成待办。没有明确后续责任、未决问题或交付动作时，tasks 返回空数组。通常 0-5 条；复杂项目最多 7 条。")
    lines.append("12.1) 待办颗粒度要偏产品/项目管理层级，例如“完成图标资源清理与验证”，不要拆成“检查 A、删除 B、运行 C、确认 D”这类流程步骤。")
    lines.append("12.2) 如果原文是流程文档、操作指南、规范说明或排查步骤，默认不生成待办，除非文中出现“需要/下一步/待确认/负责人/截止时间/阻塞/风险跟进”等明显任务信号。")
    lines.append("13) summary <= 100 个中文字符，1-2 句；必须是分析性概括，综合主题、意图和关键判断，不得直接摘录标题、首句或原文连续片段；sections <= 3；每节 bullets <= 6；避免套话与重复，不要在 summary 和 bullets 重复表达同一点。")
    if isShort {
        lines.append("14) 原文较短时不要扩写或脑补，只做更清晰的表达与轻量结构化。")
        lines.append("15) 原文较短时 report.tables 必须为空，除非原文明确包含表格/字段/时间线/对比结构。")
    }
    if isVeryShort {
        lines.append("16) 原文极短时尽量只做标点、换行与项目符号整理，不生成冗长摘要。")
    }
    if !protectedAttachmentTokens.isEmpty {
        lines.append("17) 文中包含附件占位符 token，代表原笔记中的图片或附件。必须原样保留，不得删除/改写/放入代码块。")
        lines.append("18) 尽量保持这些 token 在原有相对位置。")
        lines.append("附件占位符：\(protectedAttachmentTokens.joined(separator: ", "))")
    }
    lines.append("")
    lines.append("JSON 示例（仅示意格式）：")
    lines.append("{")
    lines.append("  \"formattedMarkdown\": \"项目概述... ==yellow:关键规则== ...\",")
    lines.append("  \"report\": {")
    lines.append("    \"title\": \"需求整理\",")
    lines.append("    \"summary\": \"简要总结\",")
    lines.append("    \"sections\": [")
    lines.append("      { \"heading\": \"信息架构\", \"paragraphs\": [\"代理填报字段与运营只读字段分组展示\"], \"bullets\": [\"==yellow:代理时间优先==\"] }")
    lines.append("    ],")
    lines.append("    \"tables\": [")
    lines.append("      { \"title\": \"代理填报字段\", \"columns\": [\"字段\", \"可编辑\", \"说明\"], \"rows\": [[\"船中文名\", \"是\", \"详情页优先\"], [\"抵港时间\", \"是\", \"代理优先\" ]], \"notes\": null }")
    lines.append("    ]")
    lines.append("  },")
    lines.append("  \"tasks\": [")
    lines.append("    { \"text\": \"实现代理填报字段分组与优先展示\", \"dueDate\": null, \"priority\": \"high\", \"confidence\": 0.7, \"sourceAnchor\": { \"paragraphIndex\": 2 } }")
    lines.append("  ]")
    lines.append("}")
    lines.append("")
    
    // 添加笔记本背景介绍作为上下文
    if let context = notebookContext, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("笔记本背景介绍（请结合此背景理解笔记内容）：")
        lines.append(context)
        lines.append("")
    }
    
    lines.append("原文标题：\(title)")
    lines.append("原文字数：\(charCount)")
    lines.append("原文如下：")
    lines.append(trimmed.isEmpty ? "<empty>" : trimmed)

    return lines.joined(separator: "\n")
}

private func buildExtractTasksPrompt(text: String) -> String {
    var lines: [String] = []
    lines.append("你是 NoteLab 的助手。请从以下文本中提取待办事项/任务，并只输出 JSON。")
    lines.append("只输出 JSON，不要输出任何额外文字、注释或 markdown。")
    lines.append("必须遵循以下 JSON 结构（字段必须存在）：")
    lines.append("{")
    lines.append("  \"tasks\": [ { \"text\": string, \"dueDate\": string?, \"priority\": string, \"confidence\": number, \"sourceAnchor\": { \"paragraphIndex\": number } } ]")
    lines.append("}")
    lines.append("规则：")
    lines.append("1) 只提取真正需要后续跟进、决策、交付、确认或沟通的事项；允许把“下一步/风险/阻塞项/问题/待确认项”转成可执行待办，但不要编造事实。")
    lines.append("2) priority 为 \"high\", \"medium\", \"low\" 之一。")
    lines.append("3) confidence 为 0-1 之间的数字，表示这是待办事项的置信度。")
    lines.append("4) dueDate 格式为 ISO8601，如果没有明确日期则为 null。")
    lines.append("5) 不要把流程步骤、操作指南、检查清单逐项转成待办；同一目标下的连续小步骤要合并成一个较高层级任务。")
    lines.append("6) 不要为了凑数量生成待办。通常 0-5 条；复杂项目最多 7 条。")
    lines.append("7) 如果没有任务，必须返回空数组：{\"tasks\": []}。")
    lines.append("8) 不要输出除 JSON 外的任何文字。")
    lines.append("")
    lines.append("JSON 示例：")
    lines.append("{\"tasks\": [{\"text\": \"跟进日志异常原因\", \"dueDate\": null, \"priority\": \"medium\", \"confidence\": 0.62, \"sourceAnchor\": {\"paragraphIndex\": 3}}]}")
    lines.append("")
    lines.append("原文如下：")
    lines.append(text)
    return lines.joined(separator: "\n")
}

private func buildRewritePrompt(
    text: String,
    title: String,
    notebookContext: String? = nil,
    mode: AIRewriteMode,
    protectedAttachmentTokens: [String] = []
) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let charCount = trimmed.count
    var lines: [String] = []
    
    lines.append("你是 NoteLab 的助手。请严格按指定模式处理笔记，并只输出 JSON。")
    lines.append("只输出 JSON，不要输出任何额外文字、注释或 markdown。")
    lines.append("必须遵循以下 JSON 结构：")
    lines.append("{\"title\": string?, \"markdown\": string}")
    lines.append("")
    
    // 根据不同模式给出完全不同的约束
    switch mode {
    case .optimize:
        lines.append("【模式】优化笔记排版与书写")
        lines.append("")
        lines.append("【核心目标】只做排版美化，不改变内容本身")
        lines.append("")
        lines.append("【必须执行】")
        lines.append("1. 为长段落添加合适的二级/三级标题（## / ###）")
        lines.append("2. 将并列项转换为无序列表（- item）或有序列表（1. item）")
        lines.append("3. 将可执行事项转换为待办格式（- [ ] task）")
        lines.append("4. 对关键词/重点用加粗（**文字**）标记")
        lines.append("5. 对特别重要的结论/警告用高亮（==yellow:文字==）标记")
        lines.append("6. 代码/命令必须放入代码块（```code```）")
        lines.append("7. 适当分段，每段不超过 5 句话")
        lines.append("")
        lines.append("【严格禁止】")
        lines.append("- 禁止删减任何原有内容")
        lines.append("- 禁止添加原文没有的新内容")
        lines.append("- 禁止改变原文的语义和措辞")
        lines.append("- 禁止合并或省略任何段落")
        lines.append("")
        lines.append("【输出长度】与原文相当（±10%），约 \(charCount) 字")
        
    case .dedupe:
        lines.append("【模式】内容去重与精炼")
        lines.append("")
        lines.append("【核心目标】大幅压缩内容，删除冗余，保留精华")
        lines.append("")
        lines.append("【必须执行】")
        lines.append("1. 删除重复表达的内容，只保留第一次出现")
        lines.append("2. 删除口水话/套话/废话（如“众所周知”“总的来说”“换句话说”等）")
        lines.append("3. 将啰嗦的句子改写为简洁表达")
        lines.append("4. 合并语义相近的段落")
        lines.append("5. 删除不必要的修饰词和副词")
        lines.append("6. 将冗长的解释压缩为一句话")
        lines.append("")
        lines.append("【严格禁止】")
        lines.append("- 禁止添加任何新内容")
        lines.append("- 禁止扩写或补充解释")
        lines.append("- 禁止改变原文的核心信息")
        lines.append("")
        lines.append("【输出长度】必须比原文短 30%-50%，目标约 \(Int(Double(charCount) * 0.6)) 字")
        lines.append("【原文字数】\(charCount) 字")
        
    case .expand:
        lines.append("【模式】笔记扩写")
        lines.append("")
        lines.append("【核心目标】丰富内容，补充背景和上下文")
        lines.append("")
        lines.append("【必须执行】")
        lines.append("1. 为每个要点补充 1-2 句背景解释")
        lines.append("2. 为专业术语添加简短定义或说明")
        lines.append("3. 为结论补充推导过程或依据")
        lines.append("4. 为任务/计划补充可能的风险或注意事项")
        lines.append("5. 为列表项补充具体的细节或示例")
        lines.append("6. 在适当位置添加过渡句，使内容更连贯")
        lines.append("")
        lines.append("【严格禁止】")
        lines.append("- 禁止删除任何原有内容")
        lines.append("- 禁止编造与原文/背景无关的事实")
        lines.append("- 禁止添加主观评价或个人观点")
        lines.append("")
        lines.append("【输出长度】必须比原文长 50%-100%，目标约 \(Int(Double(charCount) * 1.7)) 字")
        lines.append("【原文字数】\(charCount) 字")
        if let context = notebookContext, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("【笔记本背景介绍 - 扩写时必须参考】")
            lines.append(context)
        }
    }
    
    lines.append("")
    lines.append("【通用格式规则】")
    lines.append("- 代码/命令/配置使用 fenced code block：```代码```")
    lines.append("- 重点高亮语法：==color:文字==，可选颜色：yellow/green/blue/pink/orange/purple")
    lines.append("- 如无必要不变更标题，若需优化则在 title 字段给出，否则为 null")
    
    if !protectedAttachmentTokens.isEmpty {
        lines.append("")
        lines.append("【附件保护】文中包含附件占位符 token，必须原样保留：")
        lines.append(protectedAttachmentTokens.joined(separator: ", "))
    }
    
    // 只在非 expand 模式下添加笔记本背景（expand 模式已在上面添加）
    if mode != .expand, let context = notebookContext, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("")
        lines.append("【笔记本背景介绍】")
        lines.append(context)
    }
    
    lines.append("")
    lines.append("【原文标题】\(title)")
    lines.append("【原文内容】")
    lines.append(trimmed.isEmpty ? "<empty>" : trimmed)
    
    return lines.joined(separator: "\n")
}

private func buildVoiceNotePrompt(
    rawTranscript: String,
    titleHint: String,
    notebookContext: String? = nil
) -> String {
    let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = []
    lines.append("你是 NoteLab 的语音笔记整理助手。请把一段中文口语转写整理为可阅读的 Markdown 笔记，并只输出 JSON。")
    lines.append("只输出 JSON，不要输出任何额外文字、注释或 markdown。")
    lines.append("必须遵循以下 JSON 结构：")
    lines.append("{\"title\": string, \"summary\": string, \"markdown\": string}")
    lines.append("")
    lines.append("整理规则：")
    lines.append("1) 去除无意义口语填充词，例如“嗯、啊、呃、那个、就是、然后、你知道吧、对吧”等；如果这些词承担真实语义或连接关系，保留其语义但改写成书面表达。")
    lines.append("2) 删除明显重复、口误、断裂重启的表达，但不得删掉事实、数字、日期、人名、地点、任务、决策和风险。")
    lines.append("3) 根据内容自动加二级/三级标题、列表、待办和表格；不要为了格式而编造内容。")
    lines.append("4) title 必须是根据全文生成的短标题，中文不超过 10 个字，不能用“语音笔记/摘要/正文/待办”等泛标题。")
    lines.append("5) summary 不超过 100 个中文字符，概括主题、意图和关键结论。")
    lines.append("6) markdown 不要包含 H1 标题；正文应比原始转写更清晰，但保留原意。")
    if let notebookContext, !notebookContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("")
        lines.append("笔记本背景介绍：")
        lines.append(notebookContext)
    }
    lines.append("")
    lines.append("标题提示：\(titleHint)")
    lines.append("原始转写如下：")
    lines.append(trimmed.isEmpty ? "<empty>" : trimmed)
    return lines.joined(separator: "\n")
}

private func buildHighlightSupplementPrompt(text: String, maxHighlights: Int) -> String {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var lines: [String] = []
    lines.append("你是 NoteLab 的助手。请从下文中提取重要内容，生成高亮列表，只输出 JSON。")
    lines.append("必须遵循以下 JSON 结构：")
    lines.append("{\"highlights\": [{\"color\": \"yellow\", \"text\": \"...\"}]}")
    lines.append("规则：")
    lines.append("1) 高亮粒度优先 2-12 个字的短语，必要时可用一句话。")
    lines.append("2) 不要高亮代码块内容（```...```）。")
    lines.append("3) 不要包含附件 token（如 [[ATTACHMENT:n]]）。")
    lines.append("4) 选择结论/决定、风险/注意事项、关键数字/日期、下一步、关键配置/命令说明。")
    lines.append("5) 最多返回 \(maxHighlights) 条；可少但不要为空。")
    lines.append("")
    lines.append("正文如下：")
    lines.append(cleaned.isEmpty ? "<empty>" : cleaned)
    return lines.joined(separator: "\n")
}

private func buildPlanPrompt(mode: String, goal: String, tasks: [PlanTaskRequest]) -> String {
    var lines: [String] = []
    lines.append("你是 NoteLab 的助手。请基于以下任务列表生成今日计划。")
    lines.append("只输出 JSON，不要输出任何额外文字、注释或 markdown。")
    lines.append("必须遵循以下 JSON 结构：")
    lines.append("{")
    lines.append("  \"topFocus\": { \"text\": string, \"estMinutes\": number, \"sourceRefs\": [{ \"taskId\": string? }]? },")
    lines.append("  \"actionQueue\": [ { \"taskId\": string?, \"text\": string, \"estMinutes\": number?, \"scheduledDate\": string, \"sourceRef\": { \"noteTitle\": string?, \"noteId\": string?, \"notebookId\": string?, \"sourceAnchor\": { \"paragraphIndex\": number }? }? } ],")
    lines.append("  \"risks\": [ { \"text\": string, \"suggestion\": string?, \"draftMessage\": string? } ],")
    lines.append("  \"rationale\": string")
    lines.append("}")
    lines.append("")
    lines.append("模式：\(mode)")
    lines.append("目标：\(goal)")
    lines.append("")
    lines.append("任务列表：")
    
    for task in tasks {
        var taskLine = "- \(task.text)"
        if let priority = task.priority {
            taskLine += " (优先级: \(priority))"
        }
        if let source = task.source {
            taskLine += " [来源: \(source.noteTitle)]"
        }
        lines.append(taskLine)
    }
    
    return lines.joined(separator: "\n")
}
