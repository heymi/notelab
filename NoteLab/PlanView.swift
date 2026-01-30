import SwiftUI
import Combine
import CryptoKit

struct PlanView: View {
    @State private var progressStageIndex = 0
    @State private var progressMessages: [String] = []
    @State private var progressTask: Task<Void, Never>?
    @State private var memorySnippets: [MemorySnippet] = []
    @State private var messyNotes: [MessyNoteCandidate] = []
    @State private var connections: [NoteConnection] = []
    @State private var isLoadingConnections = false
    @State private var connectionErrorMessage: String?
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var aiClient: AIClient
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var aiCenter: AIProcessingCenter
    private let digestLimit = 20
    private let connectionLimit = 3
    private let connectionCacheKey = "plan.connections.cache"
    private let connectionInputHashKey = "plan.connections.inputHash"
    private let connectionCacheInterval: TimeInterval = 24 * 60 * 60
    private let connectionCache = AIResponseCache.shared
    private let digestBudget = NoteDigestBudget(
        maxNotes: 20,
        maxTotalChars: 6000,
        maxSnippetChars: 260,
        maxHeadingCount: 6,
        maxBulletCount: 8,
        maxHeadingChars: 60,
        maxBulletChars: 80,
        maxParagraphCount: 3,
        maxParagraphChars: 120
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(spacing: 24) {
                    AIAnalysisCard(
                        planStore: planStore,
                        recentDigests: recentDigests,
                        progressStageIndex: progressStageIndex,
                        progressMessages: progressMessages,
                        onOpenRecentFocus: openRecentFocus,
                        onRegenerate: { requestRecentFocus(force: true) }
                    )

                    MemoryCardView(
                        snippets: memorySnippets,
                        onRefresh: refreshMemorySnippets,
                        onOpenNote: { noteId in router.push(.note(noteId)) }
                    )

                    MessyNotesCardView(
                        candidates: messyNotes,
                        onAutoOrganize: autoOrganizeNote,
                        onOpenNote: { noteId in router.push(.note(noteId)) }
                    )

                    ConnectionCardView(
                        connections: connections,
                        isLoading: isLoadingConnections,
                        errorMessage: connectionErrorMessage,
                        onOpenNote: { noteId in router.push(.note(noteId)) }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .padding(.top, 16)
            }
        }
        .background(Theme.background)
        .onAppear {
            requestRecentFocus(force: false)
            refreshMemorySnippets()
            refreshMessyNotes()
            refreshConnections()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(date: .complete, time: .omitted).uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .tracking(0.5)
                Text("Plan")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Menu {
                Button("重新生成") { requestRecentFocus(force: true) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardBackground, in: Circle())
                    .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }


    private var recentDigests: [NoteDigest] {
        store.recentNoteDigests(limit: digestLimit, budget: digestBudget)
    }

    private func requestRecentFocus(force: Bool) {
        if recentDigests.isEmpty { return }
        let provider = AISettings.shared.currentProvider
        let providerId = provider.rawValue
        let modelName = provider.modelName
        if !force {
            if planStore.hasCachedRecentFocus {
                let newNotes = store.countNotesCreated(after: planStore.lastRecentFocusUpdatedAt)
                if newNotes < 3 { return }
            }
        }
        startProgressFlow()
        Task {
            if force {
                await planStore.regenerateRecentFocus(
                    digests: recentDigests,
                    aiClient: aiClient,
                    providerId: providerId,
                    modelName: modelName,
                    limit: digestLimit
                )
            } else {
                await planStore.generateRecentFocusIfNeeded(
                    digests: recentDigests,
                    aiClient: aiClient,
                    providerId: providerId,
                    modelName: modelName,
                    limit: digestLimit
                )
            }
            completeProgress(success: planStore.errorMessage == nil)
        }
    }

    private func refreshMemorySnippets() {
        memorySnippets = store.randomOldNoteSnippets(olderThanDays: 7, limit: 3)
    }

    private func refreshMessyNotes() {
        messyNotes = store.findMessyNotes(limit: 3)
    }

    private func refreshConnections(force: Bool = false) {
        let digests = recentDigests
        guard !digests.isEmpty else {
            connections = []
            connectionErrorMessage = nil
            isLoadingConnections = false
            return
        }
        let provider = AISettings.shared.currentProvider
        let inputHash = connectionInputHash(
            for: digests,
            providerId: provider.rawValue,
            modelName: provider.modelName,
            limit: connectionLimit
        )
        if !force,
           let cached: ConnectionCachePayload = connectionCache.load(key: connectionCacheKey, maxAge: connectionCacheInterval),
           storedConnectionInputHash() == inputHash {
            connections = cached.connections
            connectionErrorMessage = nil
            isLoadingConnections = false
            return
        }

        isLoadingConnections = true
        connectionErrorMessage = nil
        Task {
            do {
                let suggestions = try await aiClient.semanticConnections(digests: digests, limit: connectionLimit)
                let mapped = buildConnections(from: suggestions, digests: digests)
                connections = mapped
                connectionCache.save(key: connectionCacheKey, value: ConnectionCachePayload(connections: mapped))
                persistConnectionInputHash(inputHash)
            } catch {
                connectionErrorMessage = "关联生成失败"
                connections = []
            }
            isLoadingConnections = false
        }
    }

    private func buildConnections(from suggestions: [AIConnectionSuggestion], digests: [NoteDigest]) -> [NoteConnection] {
        let digestMap = Dictionary(uniqueKeysWithValues: digests.map { ($0.noteId, $0) })
        var seenPairs = Set<String>()
        var results: [NoteConnection] = []
        for suggestion in suggestions {
            guard let sourceUUID = UUID(uuidString: suggestion.sourceNoteId),
                  let targetUUID = UUID(uuidString: suggestion.targetNoteId),
                  sourceUUID != targetUUID else {
                continue
            }
            let pairKey = sourceUUID.uuidString < targetUUID.uuidString
                ? "\(sourceUUID.uuidString)|\(targetUUID.uuidString)"
                : "\(targetUUID.uuidString)|\(sourceUUID.uuidString)"
            if seenPairs.contains(pairKey) { continue }
            guard let sourceDigest = digestMap[suggestion.sourceNoteId],
                  let targetDigest = digestMap[suggestion.targetNoteId] else {
                continue
            }
            let reason = suggestion.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(
                NoteConnection(
                    id: UUID(),
                    sourceNoteId: sourceUUID,
                    targetNoteId: targetUUID,
                    sourceTitle: sourceDigest.noteTitle,
                    targetTitle: targetDigest.noteTitle,
                    reason: reason.isEmpty ? "主题相关" : reason
                )
            )
            seenPairs.insert(pairKey)
        }
        return results
    }

    private func connectionInputHash(for digests: [NoteDigest], providerId: String, modelName: String, limit: Int) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = ConnectionInputPayload(
            providerId: providerId,
            modelName: modelName,
            limit: limit,
            digests: digests
        )
        guard let data = try? encoder.encode(payload) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func persistConnectionInputHash(_ hash: String) {
        UserDefaults.standard.set(hash, forKey: connectionInputHashKey)
    }

    private func storedConnectionInputHash() -> String? {
        UserDefaults.standard.string(forKey: connectionInputHashKey)
    }

    private func autoOrganizeNote(_ noteId: UUID) {
        guard let metadata = store.noteMetadata(for: noteId) else { return }
        aiCenter.startAutoOrganize(
            noteId: metadata.note.id,
            title: metadata.note.title,
            content: metadata.note.content,
            notebookContext: metadata.notebookDescription,
            aiClient: aiClient,
            store: store
        )
    }

    private func startProgressFlow() {
        progressTask?.cancel()
        progressStageIndex = 0
        progressMessages = ["准备请求..."]

        progressTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, planStore.isLoading else { return }
            progressStageIndex = 1
            progressMessages.append("模型生成中...")

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, planStore.isLoading else { return }
            progressStageIndex = 2
            progressMessages.append("解析结果...")

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, planStore.isLoading else { return }
            progressStageIndex = 3
            progressMessages.append("整理报告...")
        }
    }

    private func completeProgress(success: Bool) {
        progressTask?.cancel()
        progressStageIndex = PlanProgressStage.allCases.count - 1
        progressMessages.append(success ? "完成" : "失败")
    }

    private func openRecentFocus() {
        guard planStore.report != nil else { return }
        router.push(.recentFocus)
    }
}

struct AIAnalysisCard: View {
    @ObservedObject var planStore: PlanStore
    let recentDigests: [NoteDigest]
    let progressStageIndex: Int
    let progressMessages: [String]
    let onOpenRecentFocus: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Smart Review", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
                
                Spacer()

                if hasResult {
                    if let updatedAt = planStore.lastRecentFocusUpdatedAt {
                        Text(updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            content
                .padding(20)
        }
        .background {
            ZStack {
                Theme.cardBackground
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05),
                        Color.orange.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.cardShadow.opacity(0.5), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
    }

    private var hasResult: Bool {
        planStore.report != nil || !(planStore.rawReportMarkdown ?? "").isEmpty
    }

    @ViewBuilder
    private var content: some View {
        if planStore.isLoading {
            loadingView
        } else if let error = planStore.errorMessage {
            errorView(error)
        } else if let report = planStore.report {
            reportView(report)
        } else if let markdown = planStore.rawReportMarkdown, !markdown.isEmpty {
            markdownView
        } else if recentDigests.isEmpty {
            emptyView
        } else {
            // Idle state (should generate)
            idleView
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ThinkingIndicatorView(text: "Thinking", fontSize: 16, iconSize: 14)
                Text("Generating insights...")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.top, 10)

            AIStageStepper(stages: PlanProgressStage.allCases.map { $0.title }, currentIndex: progressStageIndex)
                .padding(.vertical, 8)

            if let message = progressMessages.last {
                Text(message)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .transition(.opacity)
                    .id(message)
            }
        }
        .padding(.bottom, 8)
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Generation Failed")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.top, 10)

            Text(error)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(3)

            Button(action: onRegenerate) {
                Text("Retry")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.ink, in: Capsule())
            }
            .padding(.top, 4)
        }
    }

    private func reportView(_ report: AIRecentFocusReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .padding(.top, 4)

            Text(report.summary)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(3)
                .lineSpacing(5)

            HStack {
                HStack(spacing: 12) {
                    Label("\(report.sources.count) sources", systemImage: "doc.text.fill")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk.opacity(0.8))

                    if !report.tables.isEmpty {
                        Label("Tables included", systemImage: "tablecells.fill")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.blue.opacity(0.8))
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .padding(.top, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenRecentFocus()
        }
    }

    private var markdownView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report Ready")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            Text("Tap to view full analysis")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenRecentFocus()
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No recent notes")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.top, 10)
            Text("Create more notes to get AI insights.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
        }
    }
    
    private var idleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready to review")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            
            Button(action: onRegenerate) {
                Text("Generate Review")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.ink, in: Capsule())
            }
        }
    }
}

private struct ConnectionCachePayload: Codable {
    let connections: [NoteConnection]
}

private struct ConnectionInputPayload: Encodable {
    let providerId: String
    let modelName: String
    let limit: Int
    let digests: [NoteDigest]
}

private enum PlanProgressStage: CaseIterable {
    case preparing
    case generating
    case parsing
    case finalizing
    case finished

    var title: String {
        switch self {
        case .preparing: return "准备"
        case .generating: return "生成"
        case .parsing: return "解析"
        case .finalizing: return "整理"
        case .finished: return "完成"
        }
    }
}
