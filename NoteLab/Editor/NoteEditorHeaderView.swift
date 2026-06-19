import SwiftUI
import Combine

enum NoteDetailPresentationMode: Equatable {
    case reading
    case editing

    var isEditing: Bool {
        self == .editing
    }
}

struct NoteEditorHeaderMetadata: Equatable {
    enum PreviewStyle: Equatable {
        case list
        case outline
        case excerpt
    }

    struct Preview: Equatable {
        var title: String
        var detail: String
        var style: PreviewStyle
        var items: [String]
    }

    var updatedAt: Date
    var summary: String
    var readingMinutes: Int
    var todoCount: Int
    var notebookLabel: String
    var preview: Preview?
    var hasBodyContent: Bool
    var voiceNote: VoiceNoteRecord? = nil

    var updatedLabel: String {
        updatedAt.formatted(date: .omitted, time: .shortened)
    }

    var lede: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NoteEditorHeaderView: View {
    @Binding var title: String
    @ObservedObject var focusBridge: TitleFocusBridge
    let metadata: NoteEditorHeaderMetadata
    let linkBlocks: [LinkedNoteBlock]
    let presentationMode: NoteDetailPresentationMode
    let isWhiteboard: Bool
    let onOpenNote: (UUID) -> Void

    init(
        title: Binding<String>,
        focusBridge: TitleFocusBridge,
        metadata: NoteEditorHeaderMetadata,
        linkBlocks: [LinkedNoteBlock],
        presentationMode: NoteDetailPresentationMode = .reading,
        isWhiteboard: Bool,
        onOpenNote: @escaping (UUID) -> Void
    ) {
        self._title = title
        self.focusBridge = focusBridge
        self.metadata = metadata
        self.linkBlocks = linkBlocks
        self.presentationMode = presentationMode
        self.isWhiteboard = isWhiteboard
        self.onOpenNote = onOpenNote
    }

    private var showsReadingChrome: Bool {
        presentationMode == .reading && metadata.hasBodyContent
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }

    var body: some View {
        Group {
            if isWhiteboard || presentationMode.isEditing {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if showsReadingChrome {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Theme.editorAccent.opacity(0.12))
                                    .frame(width: 20, height: 20)
                                Circle()
                                    .fill(Theme.editorAccent.opacity(0.75))
                                    .frame(width: 10, height: 10)
                            }
                            Text("\(metadata.notebookLabel) · 已同步")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }

                    Text(displayTitle)
                        .font(.custom("STSongti-SC-Black", size: 52))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(3)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsReadingChrome {
                        if let voiceNote = metadata.voiceNote {
                            VoicePlaybackCard(record: voiceNote)
                        }

                        if !metadata.lede.isEmpty && metadata.preview == nil {
                            Text(metadata.lede)
                                .font(.system(size: 18, weight: .regular))
                                .lineSpacing(8)
                                .foregroundStyle(Theme.ink.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 10) {
                            metadataChip("今天 \(metadata.updatedLabel)")
                            metadataChip("\(metadata.readingMinutes) 分钟阅读")
                            metadataChip("\(metadata.todoCount) 个待办")
                        }
                        .padding(.top, -4)

                        if let preview = metadata.preview {
                            contentPreviewCard(preview)
                        }
                    }

                    if presentationMode == .reading && !linkBlocks.isEmpty {
                        linkBlockSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 30)
                .background(Color.clear)
            }
        }
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Theme.editorPaper.opacity(0.72), in: Capsule())
    }

    private func contentPreviewCard(_ preview: NoteEditorHeaderMetadata.Preview) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("NL")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.editorAccentDeep)
                    .frame(width: 34, height: 34)
                    .background(Theme.editorAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(preview.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.editorAccentDeep)

                Spacer()

                Text(preview.detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.editorAccentDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Theme.editorPaperSoft.opacity(0.68), in: Capsule())
            }

            VStack(alignment: .leading, spacing: preview.style == .list ? 11 : 16) {
                ForEach(Array(preview.items.enumerated()), id: \.offset) { index, item in
                    previewRow(item, index: index, style: preview.style)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, preview.style == .excerpt ? 24 : 22)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [Theme.editorPaperSoft.opacity(0.88), Theme.editorPaperSoft.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.editorLine.opacity(0.28), lineWidth: 0.8)
        )
    }

    private func previewRow(_ item: String, index: Int, style: NoteEditorHeaderMetadata.PreviewStyle) -> some View {
        HStack(alignment: style == .excerpt ? .top : .firstTextBaseline, spacing: style == .excerpt ? 12 : 10) {
            switch style {
            case .list:
                Circle()
                    .fill(Theme.editorAccent)
                    .frame(width: 6, height: 6)
            case .outline:
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.editorAccentDeep)
                    .frame(width: 20, height: 20)
                    .background(Theme.editorAccent.opacity(0.14), in: Circle())
            case .excerpt:
                Rectangle()
                    .fill(Theme.editorAccent.opacity(0.58))
                    .frame(width: 3, height: 24)
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }

            Text(verbatim: item)
                .font(.system(size: style == .excerpt ? 16 : (style == .outline ? 15 : 16), weight: style == .outline ? .medium : .regular))
                .foregroundStyle(Theme.ink.opacity(style == .excerpt ? 0.78 : 0.84))
                .lineSpacing(style == .excerpt ? 8 : 2)
                .lineLimit(style == .excerpt ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var linkBlockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("引用")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.editorAccentDeep)

            ForEach(linkBlocks) { block in
                Button(action: { onOpenNote(block.noteId) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.editorAccentDeep)
                            .frame(width: 34, height: 34)
                            .background(Theme.editorPaper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text("点击查看笔记")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.editorQuiet)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.editorPaperSoft.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.editorLine.opacity(0.52), lineWidth: 0.7)
        )
    }
}
