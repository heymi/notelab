import AVFoundation
import Combine
import SwiftUI

struct VoiceRecordingOverlay: View {
    let elapsed: TimeInterval
    let level: Double
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(width: 38, height: 38)
                    .background(Theme.editorPaper.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("正在录音")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 3) {
                    ForEach(0..<16, id: \.self) { index in
                        Capsule()
                            .fill(Theme.editorAccent.opacity(0.45 + 0.45 * level))
                            .frame(width: 4, height: barHeight(index: index))
                    }
                }
                .frame(height: 24, alignment: .center)
            }

            Spacer(minLength: 0)

            Text(Self.format(elapsed))
                .font(.system(size: 14, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.editorLine.opacity(0.32), lineWidth: 0.7)
        )
        .shadow(color: Theme.softShadow.opacity(0.8), radius: 24, x: 0, y: 12)
    }

    private func barHeight(index: Int) -> CGFloat {
        let phase = Double(index % 5) / 4
        return CGFloat(6 + (level * 22 * (0.42 + phase)))
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct VoiceNotebookSelectionSheet: View {
    let notebooks: [Notebook]
    let onSelect: (UUID) -> Void
    let onDiscard: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if notebooks.isEmpty {
                    Text("请先创建一个笔记本")
                        .foregroundStyle(Theme.secondaryInk)
                } else {
                    ForEach(notebooks) { notebook in
                        Button {
                            onSelect(notebook.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: notebook.iconName)
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(Color.notebook(notebook.color))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(notebook.title)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.ink)
                                    Text("\(notebook.notes.count) 条笔记")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("保存到笔记本")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("丢弃录音", role: .destructive) {
                        onDiscard()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct VoiceNoteSavedToast: View {
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(Theme.editorAccentDeep)
            Text("语音笔记已保存，正在分析")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button("查看", action: onOpen)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.editorAccentDeep)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Theme.softShadow.opacity(0.7), radius: 18, x: 0, y: 8)
    }
}

struct VoiceNoteErrorToast: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Theme.softShadow.opacity(0.7), radius: 18, x: 0, y: 8)
    }
}

struct VoicePlaybackCard: View {
    let record: VoiceNoteRecord
    @StateObject private var player = VoiceAudioPlayer()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.toggle(record: record)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.editorAccentDeep, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("语音记录")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(record.status.displayText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }
                ProgressView(value: player.progress)
                    .tint(Theme.editorAccentDeep)
                HStack {
                    Text(Self.format(player.currentTime))
                    Spacer()
                    Text(Self.format(record.duration))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
            }

            if record.status == .failed || record.status == .needsAI {
                Button("重试") {
                    NotificationCenter.default.post(name: .voiceNoteRetryRequested, object: record.id)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.editorAccentDeep)
            } else if record.status.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(Theme.editorPaperSoft.opacity(0.8), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.editorLine.opacity(0.42), lineWidth: 0.7)
        )
        .task(id: record.id) {
            await player.prepare(record: record)
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .needsAI:
            return .orange
        default:
            return Theme.editorAccentDeep
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

@MainActor
final class VoiceAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTime: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func prepare(record: VoiceNoteRecord) async {
        guard player == nil else { return }
        do {
            let data = try await AttachmentStorage.shared.loadAttachmentData(
                attachmentId: record.audioAttachmentId,
                storagePath: record.audioStoragePath,
                fileName: record.audioFileName
            )
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.prepareToPlay()
        } catch {
            player = nil
        }
    }

    func toggle(record: VoiceNoteRecord) {
        Task {
            if player == nil {
                await prepare(record: record)
            }
            guard let player else { return }
            if player.isPlaying {
                player.pause()
                stopTimer()
                isPlaying = false
            } else {
                player.play()
                startTimer()
                isPlaying = true
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.progress = 0
            self.currentTime = 0
            self.stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let player = self else { return }
            Task { @MainActor in
                player.updatePlaybackProgress()
            }
        }
    }

    private func updatePlaybackProgress() {
        guard let player else { return }
        currentTime = player.currentTime
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
