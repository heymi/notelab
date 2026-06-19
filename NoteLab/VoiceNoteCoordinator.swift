import Combine
import Foundation

#if os(iOS)
import AVFoundation
import Speech
#endif

struct VoiceTranscript: Equatable {
    let text: String
}

protocol VoiceTranscriptionProvider {
    func transcribe(fileURL: URL, locale: Locale) async throws -> VoiceTranscript
}

enum VoiceNoteError: LocalizedError, Equatable {
    case microphoneDenied
    case speechDenied
    case recorderUnavailable
    case recordingTooShort
    case missingNotebook
    case missingProfile
    case missingAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "请在系统设置中允许 NoteLab 使用麦克风"
        case .speechDenied:
            return "请在系统设置中允许 NoteLab 使用语音识别"
        case .recorderUnavailable:
            return "无法开始录音，请稍后再试"
        case .recordingTooShort:
            return "录音太短，请至少录制 1 秒"
        case .missingNotebook:
            return "请先创建一个笔记本"
        case .missingProfile:
            return "当前账号尚未准备好"
        case .missingAudio:
            return "没有可处理的录音"
        case .emptyTranscript:
            return "没有识别到有效语音"
        }
    }
}

#if os(iOS)
final class AppleSpeechTranscriptionProvider: VoiceTranscriptionProvider {
    func transcribe(fileURL: URL, locale: Locale) async throws -> VoiceTranscript {
        let authorized = await requestSpeechAuthorization()
        guard authorized else { throw VoiceNoteError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceNoteError.speechDenied
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = false

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error, !didResume {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal, !didResume else { return }
                didResume = true
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: VoiceTranscript(text: text))
            }

            Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if !didResume {
                    didResume = true
                    task.cancel()
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
#else
final class AppleSpeechTranscriptionProvider: VoiceTranscriptionProvider {
    func transcribe(fileURL: URL, locale: Locale) async throws -> VoiceTranscript {
        throw VoiceNoteError.speechDenied
    }
}
#endif

#if os(iOS)
@MainActor
final class VoiceNoteCoordinator: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case selectingNotebook
        case saving
        case transcribing
        case organizing
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var completedNoteId: UUID?
    @Published var isSelectingNotebook = false

    private let transcriptionProvider: VoiceTranscriptionProvider
    private let voiceRepository: VoiceNoteRepository
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?
    private var processingTask: Task<Void, Never>?

    init(
        transcriptionProvider: VoiceTranscriptionProvider? = nil,
        voiceRepository: VoiceNoteRepository? = nil
    ) {
        self.transcriptionProvider = transcriptionProvider ?? AppleSpeechTranscriptionProvider()
        self.voiceRepository = voiceRepository ?? VoiceNoteRepository()
        super.init()
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    func toggleRecording(store: NotebookStore, aiClient: AIClient) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        completedNoteId = nil
        Task {
            do {
                guard await requestMicrophonePermission() else {
                    throw VoiceNoteError.microphoneDenied
                }
                try beginRecording()
            } catch {
                fail(error)
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        inputLevel = 0
        elapsed = Date().timeIntervalSince(recordingStartedAt ?? Date())
        guard elapsed >= 1 else {
            discardCurrentRecording()
            fail(VoiceNoteError.recordingTooShort)
            return
        }
        phase = .selectingNotebook
        isSelectingNotebook = true
    }

    func discardCurrentRecording() {
        recorder?.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recorder = nil
        recordingURL = nil
        recordingStartedAt = nil
        elapsed = 0
        inputLevel = 0
        isSelectingNotebook = false
        phase = .idle
    }

    func savePendingRecording(to notebookId: UUID, store: NotebookStore, aiClient: AIClient) {
        guard let recordingURL else {
            fail(VoiceNoteError.missingAudio)
            return
        }
        guard store.notebooks.contains(where: { $0.id == notebookId }) else {
            fail(VoiceNoteError.missingNotebook)
            return
        }
        guard let profileId = store.currentProfileId else {
            fail(VoiceNoteError.missingProfile)
            return
        }

        phase = .saving
        isSelectingNotebook = false
        do {
            let data = try Data(contentsOf: recordingURL)
            guard let noteId = store.addNote(to: notebookId, title: "语音笔记", content: "正在分析语音...") else {
                throw VoiceNoteError.missingNotebook
            }
            let attachmentId = UUID()
            let fileName = "\(attachmentId.uuidString).m4a"
            let attachment = try AttachmentStorage.shared.saveNewAttachmentV3(
                data: data,
                attachmentId: attachmentId,
                ownerId: profileId,
                noteId: noteId,
                fileName: fileName,
                mimeType: "audio/mp4"
            )
            Task {
                await AttachmentStorage.shared.uploadAndUpsertMetadataV3(attachment: attachment)
            }
            let now = Date()
            let record = VoiceNoteRecord(
                id: UUID(),
                profileId: profileId,
                noteId: noteId,
                notebookId: notebookId,
                audioAttachmentId: attachmentId,
                audioStoragePath: attachment.storagePath,
                audioFileName: fileName,
                duration: elapsed,
                status: .transcribing,
                rawTranscript: "",
                errorMessage: nil,
                retryCount: 0,
                createdAt: now,
                updatedAt: now
            )
            try voiceRepository.create(record)
            completedNoteId = noteId
            phase = .completed
            processingTask?.cancel()
            processingTask = Task { [weak self] in
                await self?.process(record: record, audioURL: recordingURL, store: store, aiClient: aiClient)
            }
        } catch {
            fail(error)
        }
    }

    func retry(recordId: UUID, profileId: UUID, store: NotebookStore, aiClient: AIClient) {
        do {
            guard let record = try voiceRepository.record(id: recordId, profileId: profileId) else { return }
            processingTask?.cancel()
            processingTask = Task { [weak self] in
                await self?.retry(record: record, store: store, aiClient: aiClient)
            }
        } catch {
            fail(error)
        }
    }

    func record(for noteId: UUID) -> VoiceNoteRecord? {
        try? voiceRepository.record(noteId: noteId)
    }

    func clearCompletedNote() {
        completedNoteId = nil
    }

    private func beginRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notelab-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw VoiceNoteError.recorderUnavailable }
        self.recorder = recorder
        self.recordingURL = url
        self.recordingStartedAt = Date()
        self.elapsed = 0
        self.phase = .recording
        startMetering()
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let coordinator = self else { return }
            Task { @MainActor in
                coordinator.updateMeter()
            }
        }
    }

    private func updateMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        elapsed = Date().timeIntervalSince(recordingStartedAt ?? Date())
        let power = recorder.averagePower(forChannel: 0)
        inputLevel = max(0, min(1, (Double(power) + 55) / 55))
    }

    private func process(record: VoiceNoteRecord, audioURL: URL, store: NotebookStore, aiClient: AIClient) async {
        await processTranscription(record: record, audioURL: audioURL, store: store, aiClient: aiClient)
    }

    private func retry(record: VoiceNoteRecord, store: NotebookStore, aiClient: AIClient) async {
        do {
            let data = try await AttachmentStorage.shared.loadAttachmentData(
                attachmentId: record.audioAttachmentId,
                storagePath: record.audioStoragePath,
                fileName: record.audioFileName
            )
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("notelab-retry-\(record.audioAttachmentId.uuidString).m4a")
            try data.write(to: url, options: [.atomic])
            _ = try voiceRepository.update(
                id: record.id,
                profileId: record.profileId,
                status: .transcribing,
                errorMessage: nil,
                incrementRetry: true
            )
            await processTranscription(record: record, audioURL: url, store: store, aiClient: aiClient)
        } catch {
            _ = try? voiceRepository.update(
                id: record.id,
                profileId: record.profileId,
                status: .failed,
                errorMessage: localized(error),
                incrementRetry: true
            )
        }
    }

    private func processTranscription(record: VoiceNoteRecord, audioURL: URL, store: NotebookStore, aiClient: AIClient) async {
        do {
            let transcript = try await transcriptionProvider.transcribe(fileURL: audioURL, locale: Locale(identifier: AppConfig.locale))
            let rawText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { throw VoiceNoteError.emptyTranscript }
            guard let updatedRecord = try voiceRepository.update(
                id: record.id,
                profileId: record.profileId,
                status: .organizing,
                rawTranscript: rawText,
                errorMessage: nil
            ) else { return }

            guard SubscriptionManager.shared.canUseAIFeature(.organize) else {
                NotificationCenter.default.post(name: .showPaywall, object: PaywallTrigger.aiQuotaExceeded)
                store.updateVoiceNote(noteId: record.noteId, title: "语音笔记", summary: "", content: rawText)
                _ = try voiceRepository.update(
                    id: record.id,
                    profileId: record.profileId,
                    status: .needsAI,
                    rawTranscript: rawText,
                    errorMessage: "AI 配额不足，已保留原始转写"
                )
                return
            }

            let result = try await aiClient.organizeVoiceTranscript(
                rawTranscript: updatedRecord.rawTranscript,
                titleHint: "语音笔记",
                notebookContext: store.noteMetadata(for: record.noteId)?.notebookDescription
            )
            store.updateVoiceNote(
                noteId: record.noteId,
                title: result.title,
                summary: result.summary,
                content: result.markdown
            )
            AISummaryRegistry.mark(noteId: record.noteId, summary: result.summary)
            SubscriptionManager.shared.recordAIUsage(.organize)
            _ = try voiceRepository.update(
                id: record.id,
                profileId: record.profileId,
                status: .completed,
                rawTranscript: rawText,
                errorMessage: nil
            )
            try? FileManager.default.removeItem(at: audioURL)
        } catch AIClientError.missingAPIKey {
            let rawText = (try? voiceRepository.record(id: record.id, profileId: record.profileId)?.rawTranscript) ?? ""
            if !rawText.isEmpty {
                store.updateVoiceNote(noteId: record.noteId, title: "语音笔记", summary: "", content: rawText)
            }
            _ = try? voiceRepository.update(
                id: record.id,
                profileId: record.profileId,
                status: .needsAI,
                rawTranscript: rawText,
                errorMessage: "请先在设置中配置 API Key"
            )
        } catch {
            _ = try? voiceRepository.update(
                id: record.id,
                profileId: record.profileId,
                status: .failed,
                errorMessage: localized(error)
            )
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
    }

    private func fail(_ error: Error) {
        phase = .failed(localized(error))
    }

    private func localized(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
#else
@MainActor
final class VoiceNoteCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case selectingNotebook
        case saving
        case transcribing
        case organizing
        case completed
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var completedNoteId: UUID?
    @Published var isSelectingNotebook = false

    var isRecording: Bool { false }

    init() {}

    func toggleRecording(store: NotebookStore, aiClient: AIClient) {}
    func startRecording() {}
    func stopRecording() {}
    func discardCurrentRecording() {}
    func savePendingRecording(to notebookId: UUID, store: NotebookStore, aiClient: AIClient) {}
    func retry(recordId: UUID, profileId: UUID, store: NotebookStore, aiClient: AIClient) {}
    func record(for noteId: UUID) -> VoiceNoteRecord? { nil }
    func clearCompletedNote() {
        completedNoteId = nil
    }
}
#endif
