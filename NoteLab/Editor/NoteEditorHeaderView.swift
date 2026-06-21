import SwiftUI
import Combine

struct NoteEditorHeaderView: View {
    @Binding var title: String
    @ObservedObject var focusBridge: TitleFocusBridge
    let linkBlocks: [LinkedNoteBlock]
    let summary: String
    let isWhiteboard: Bool
    let onOpenNote: (UUID) -> Void
    @FocusState private var titleFocused: Bool

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSummaryPoster: Bool {
        !trimmedSummary.isEmpty
    }

    var body: some View {
        Group {
            if isWhiteboard {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if hasSummaryPoster {
                        summaryPoster
                    } else {
                        titleField
                    }

                    if !linkBlocks.isEmpty {
                        linkBlockSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .background(Theme.background)
                .onChange(of: focusBridge.requestFocus) { _, needsFocus in
                    guard needsFocus else { return }
                    titleFocused = true
                    DispatchQueue.main.async {
                        focusBridge.requestFocus = false
                    }
                }
            }
        }
    }

    private var titleField: some View {
        TextField("标题", text: $title)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .textFieldStyle(.plain)
            .focused($titleFocused)
    }

    private var summaryPoster: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.isEmpty ? "未命名笔记" : title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(2)

            Text(trimmedSummary)
                .font(posterFont(for: trimmedSummary))
                .foregroundStyle(Theme.ink)
                .lineSpacing(6)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("AI 摘要，\(trimmedSummary)")

            Text("AI 摘要")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .textCase(.uppercase)
        }
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func posterFont(for text: String) -> Font {
        let size: CGFloat
        switch text.count {
        case 0...32:
            size = 48
        case 33...64:
            size = 42
        case 65...96:
            size = 36
        default:
            size = 32
        }
        return .custom("STSongti-SC-Bold", size: size, relativeTo: .largeTitle)
    }

    private var linkBlockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("引用")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)

            ForEach(linkBlocks) { block in
                Button(action: { onOpenNote(block.noteId) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(Theme.secondaryInk)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text("点击查看笔记")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 12, x: 0, y: 8)
    }
}
