import SwiftUI
import Combine

@MainActor
final class AIProcessingCenter: ObservableObject {
    enum AIMode {
        case autoOrganize
        case extractTodos
        case optimize
        case dedupe
        case expand
    }

    @Published var isVisible = false
    @Published var isLoading = false
    @Published var isCompleted = false
    @Published var error: String?
    @Published var mode: AIMode?
    @Published var stageIndex = 0
    @Published var activeNoteId: UUID?
    @Published private(set) var lastTaskCount = 0
    @Published private(set) var lastAppliedNoteId: UUID?

    private var aiTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    var statusTitle: String {
        if error != nil { return "AI 出错" }
        if isCompleted { return "已完成" }
        switch mode {
        case .autoOrganize:
            return "正在整理…"
        case .extractTodos:
            return "正在提取待办…"
        case .optimize:
            return "正在优化…"
        case .dedupe:
            return "正在精炼…"
        case .expand:
            return "正在扩写…"
        case .none:
            return "正在处理…"
        }
    }

    var statusDetail: String {
        if let error { return error }
        if mode == .extractTodos, !isLoading, error == nil, lastTaskCount == 0 {
            return "未识别到待办"
        }
        return stageTitle
    }

    var stageTitle: String {
        let index = min(stageIndex, AIProgressStage.allCases.count - 1)
        return AIProgressStage.allCases[index].title
    }

    func startAutoOrganize(
        noteId: UUID,
        title: String,
        content: String,
        notebookContext: String?,
        aiClient: AIClient,
        store: NotebookStore
    ) {
        resetForNewRun(noteId: noteId, mode: .autoOrganize)
        startProgressFlow()
        aiTask?.cancel()
        aiTask = Task {
            do {
                let document = NoteDocument.fromMarkdown(content)
                let attachmentTokens = AttachmentPreserver.extractTokens(from: document)
                let tokenizedContent = AttachmentPreserver.tokenize(content: content, tokens: attachmentTokens)
                let payload = try await aiClient.noteInsight(
                    text: tokenizedContent,
                    title: title,
                    notebookContext: notebookContext,
                    protectedAttachmentTokens: attachmentTokens.map { $0.token }
                )
                let newTitle = AIInsightComposer.resolvedTitle(from: payload.report?.title, fallback: title)
                let combined = AIInsightComposer.composeInsightMarkdown(
                    formattedMarkdown: payload.formattedMarkdown,
                    report: payload.report,
                    tasks: payload.tasks,
                    fallbackTitle: newTitle
                )
                let restored = AttachmentPreserver.restoreAndEnsure(markdown: combined, tokens: attachmentTokens)
                let highlighted = try await AIHighlightInjector.applyHighlightsIfNeeded(
                    markdown: restored,
                    aiClient: aiClient
                )
                applyFormattedResult(
                    noteId: noteId,
                    title: newTitle,
                    markdown: highlighted,
                    store: store
                )
                completeProgress(success: true)
                finish(success: true)
            } catch {
                if Task.isCancelled { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.error = message
                completeProgress(success: false)
                isLoading = false
                isVisible = true
            }
        }
    }

    func startExtractTodosInsertTop(
        noteId: UUID,
        content: String,
        aiClient: AIClient,
        store: NotebookStore
    ) {
        resetForNewRun(noteId: noteId, mode: .extractTodos)
        startProgressFlow()
        aiTask?.cancel()
        aiTask = Task {
            do {
                let tasks = try await aiClient.extractTasks(text: content)
                lastTaskCount = tasks.count
                if !tasks.isEmpty {
                    applyExtractedTasks(tasks, noteId: noteId, store: store)
                }
                completeProgress(success: true)
                finish(success: true)
            } catch {
                if Task.isCancelled { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.error = message
                completeProgress(success: false)
                isLoading = false
                isVisible = true
            }
        }
    }

    func startRewrite(
        noteId: UUID,
        title: String,
        content: String,
        notebookContext: String?,
        mode: AIRewriteMode,
        aiClient: AIClient,
        store: NotebookStore
    ) {
        let mappedMode: AIMode
        switch mode {
        case .optimize:
            mappedMode = .optimize
        case .dedupe:
            mappedMode = .dedupe
        case .expand:
            mappedMode = .expand
        }
        resetForNewRun(noteId: noteId, mode: mappedMode)
        startProgressFlow()
        aiTask?.cancel()
        aiTask = Task {
            do {
                let document = NoteDocument.fromMarkdown(content)
                let attachmentTokens = AttachmentPreserver.extractTokens(from: document)
                let tokenizedContent = AttachmentPreserver.tokenize(content: content, tokens: attachmentTokens)
                let rewrite = try await aiClient.rewriteNote(
                    text: tokenizedContent,
                    title: title,
                    notebookContext: notebookContext,
                    mode: mode,
                    protectedAttachmentTokens: attachmentTokens.map { $0.token }
                )
                let resolvedTitle = AIInsightComposer.resolvedTitle(from: rewrite.title, fallback: title)
                let restored = AttachmentPreserver.restoreAndEnsure(markdown: rewrite.markdown, tokens: attachmentTokens)
                let highlighted = try await AIHighlightInjector.applyHighlightsIfNeeded(
                    markdown: restored,
                    aiClient: aiClient
                )
                applyFormattedResult(
                    noteId: noteId,
                    title: resolvedTitle,
                    markdown: highlighted,
                    store: store
                )
                completeProgress(success: true)
                finish(success: true)
            } catch {
                if Task.isCancelled { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.error = message
                completeProgress(success: false)
                isLoading = false
                isVisible = true
            }
        }
    }

    func cancel() {
        aiTask?.cancel()
        progressTask?.cancel()
        dismissTask?.cancel()
        isLoading = false
        error = nil
        isCompleted = false
        isVisible = false
        lastTaskCount = 0
    }

    func dismiss() {
        dismissTask?.cancel()
        isCompleted = false
        isVisible = false
    }

    private func resetForNewRun(noteId: UUID, mode: AIMode) {
        dismissTask?.cancel()
        error = nil
        isCompleted = false
        isLoading = true
        isVisible = true
        stageIndex = 0
        lastTaskCount = 0
        activeNoteId = noteId
        self.mode = mode
    }

    private func startProgressFlow() {
        progressTask?.cancel()
        stageIndex = 0
        progressTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, isLoading else { return }
            stageIndex = 1

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isLoading else { return }
            stageIndex = 2

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isLoading else { return }
            stageIndex = 3
        }
    }

    private func completeProgress(success: Bool) {
        progressTask?.cancel()
        stageIndex = AIProgressStage.allCases.count - 1
        Haptics.shared.play(success ? .success : .error)
    }

    private func finish(success: Bool) {
        isLoading = false
        isCompleted = success
        scheduleDismiss(after: 3.0)
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isCompleted = false
            isVisible = false
        }
    }

    private func applyFormattedResult(noteId: UUID, title: String, markdown: String, store: NotebookStore) {
        guard let binding = store.noteBinding(noteId: noteId) else { return }
        var updated = binding.wrappedValue
        NoteUndoSnapshotStore.save(noteId: updated.id, title: updated.title, content: updated.content)
        if !title.isEmpty { updated.title = title }
        updated.content = markdown
        updated.updateMetrics()
        binding.wrappedValue = updated
        store.updateDocument(noteId: updated.id, document: NoteDocument.fromMarkdown(markdown))
        lastAppliedNoteId = updated.id
    }

    private func applyExtractedTasks(_ tasks: [AITaskSuggestion], noteId: UUID, store: NotebookStore) {
        guard let binding = store.noteBinding(noteId: noteId) else { return }
        var updated = binding.wrappedValue
        NoteUndoSnapshotStore.save(noteId: updated.id, title: updated.title, content: updated.content)
        let doc = NoteDocument.fromMarkdown(updated.content)
        var blocks: [Block] = []
        blocks.append(.heading(2, text: "待办"))
        for task in tasks {
            blocks.append(.todo(task.text, checked: false))
        }
        let merged = NoteDocument(version: 1, blocks: blocks + doc.blocks)
        let markdown = merged.flattenMarkdown()
        updated.content = markdown
        updated.updateMetrics()
        binding.wrappedValue = updated
        store.updateDocument(noteId: updated.id, document: merged)
        lastAppliedNoteId = updated.id
    }
}

private enum AIProgressStage: CaseIterable {
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
