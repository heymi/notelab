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
    let background: NotebookBackground
    let onOpenNote: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: Binding<String>,
        focusBridge: TitleFocusBridge,
        metadata: NoteEditorHeaderMetadata,
        linkBlocks: [LinkedNoteBlock],
        presentationMode: NoteDetailPresentationMode = .reading,
        isWhiteboard: Bool,
        background: NotebookBackground = .default,
        onOpenNote: @escaping (UUID) -> Void
    ) {
        self._title = title
        self.focusBridge = focusBridge
        self.metadata = metadata
        self.linkBlocks = linkBlocks
        self.presentationMode = presentationMode
        self.isWhiteboard = isWhiteboard
        self.background = background
        self.onOpenNote = onOpenNote
    }

    private var showsReadingChrome: Bool {
        presentationMode == .reading && metadata.hasBodyContent
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }

    private var usesLightForeground: Bool {
        currentStyle?.usesLightForeground ?? false
    }

    private var currentStyle: NotebookBackgroundStyle? {
        background.generatedStyle(for: colorScheme)
    }

    private var ink: Color {
        currentStyle.map { Color(hex: $0.inkHex).opacity(0.92) } ?? Theme.ink
    }

    private var bodyInk: Color {
        currentStyle.map { Color(hex: $0.inkHex).opacity(0.78) } ?? Theme.ink.opacity(0.84)
    }

    private var secondaryInk: Color {
        currentStyle.map { Color(hex: $0.secondaryInkHex).opacity(0.88) } ?? Theme.secondaryInk
    }

    private var quietInk: Color {
        currentStyle.map { Color(hex: $0.secondaryInkHex).opacity(0.68) } ?? Theme.editorQuiet
    }

    private var accent: Color {
        usesLightForeground ? Color(red: 0.58, green: 0.92, blue: 0.86) : Theme.editorAccent
    }

    private var accentDeep: Color {
        usesLightForeground ? Color(red: 0.76, green: 0.98, blue: 0.94) : Theme.editorAccentDeep
    }

    private var paper: Color {
        usesLightForeground ? Color.white.opacity(0.14) : Theme.editorPaper
    }

    private var paperSoft: Color {
        usesLightForeground ? Color.white.opacity(0.10) : Theme.editorPaperSoft
    }

    private var line: Color {
        usesLightForeground ? Color.white.opacity(0.18) : Theme.editorLine
    }

    private var aiPosterText: String? {
        guard metadata.preview?.style == .excerpt,
              let text = metadata.preview?.items.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
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
                                    .fill(accent.opacity(0.12))
                                    .frame(width: 20, height: 20)
                                Circle()
                                    .fill(accent.opacity(0.75))
                                    .frame(width: 10, height: 10)
                            }
                            Text("\(metadata.notebookLabel) · 已同步")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(secondaryInk)
                        }
                    }

                    if let aiPosterText, showsReadingChrome {
                        aiPoster(text: aiPosterText)
                    } else {
                        Text(displayTitle)
                            .font(.custom("STSongti-SC-Black", size: 52))
                            .foregroundStyle(ink)
                            .lineSpacing(3)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showsReadingChrome {
                        if let voiceNote = metadata.voiceNote {
                            VoicePlaybackCard(record: voiceNote)
                        }

                        if !metadata.lede.isEmpty && metadata.preview == nil {
                            Text(metadata.lede)
                                .font(.system(size: 18, weight: .regular))
                                .lineSpacing(8)
                                .foregroundStyle(bodyInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 10) {
                            metadataChip("今天 \(metadata.updatedLabel)")
                            metadataChip("\(metadata.readingMinutes) 分钟阅读")
                            metadataChip("\(metadata.todoCount) 个待办")
                        }
                        .padding(.top, -4)

                        if let preview = metadata.preview, preview.style != .excerpt {
                            contentPreviewCard(preview)
                        }
                    }

                    if presentationMode == .reading && !linkBlocks.isEmpty {
                        linkBlockSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 30)
                .background(Color.clear)
            }
        }
    }

    private func aiPoster(text: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(displayTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(verbatim: text)
                .font(.custom("STSongti-SC-Bold", size: posterFontSize(for: text), relativeTo: .largeTitle))
                .foregroundStyle(ink)
                .lineSpacing(6)
                .lineLimit(nil)
                .minimumScaleFactor(0.84)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("AI 摘要")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryInk.opacity(0.58))
                .tracking(1.2)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func posterFontSize(for text: String) -> CGFloat {
        switch text.count {
        case 0...38:
            return 43
        case 39...72:
            return 37
        default:
            return 32
        }
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(usesLightForeground ? Color.white.opacity(0.84) : Theme.ink.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(paper.opacity(usesLightForeground ? 1 : 0.72), in: Capsule())
    }

    private func contentPreviewCard(_ preview: NoteEditorHeaderMetadata.Preview) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("NL")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accentDeep)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(preview.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentDeep)

                Spacer()

                Text(preview.detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(paperSoft.opacity(usesLightForeground ? 1 : 0.68), in: Capsule())
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
                colors: [paperSoft.opacity(usesLightForeground ? 1 : 0.88), paperSoft.opacity(usesLightForeground ? 0.82 : 0.72)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(line.opacity(usesLightForeground ? 1 : 0.28), lineWidth: 0.8)
        )
    }

    private func previewRow(_ item: String, index: Int, style: NoteEditorHeaderMetadata.PreviewStyle) -> some View {
        HStack(alignment: style == .excerpt ? .top : .firstTextBaseline, spacing: style == .excerpt ? 12 : 10) {
            switch style {
            case .list:
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
            case .outline:
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(accentDeep)
                    .frame(width: 20, height: 20)
                    .background(accent.opacity(0.14), in: Circle())
            case .excerpt:
                Rectangle()
                    .fill(accent.opacity(0.58))
                    .frame(width: 3, height: 24)
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }

            Text(verbatim: item)
                .font(.system(size: style == .excerpt ? 16 : (style == .outline ? 15 : 16), weight: style == .outline ? .medium : .regular))
                .foregroundStyle(usesLightForeground ? Color.white.opacity(style == .excerpt ? 0.74 : 0.80) : Theme.ink.opacity(style == .excerpt ? 0.78 : 0.84))
                .lineSpacing(style == .excerpt ? 8 : 2)
                .lineLimit(style == .excerpt ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var linkBlockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("引用")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accentDeep)

            ForEach(linkBlocks) { block in
                Button(action: { onOpenNote(block.noteId) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentDeep)
                            .frame(width: 34, height: 34)
                            .background(paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink)
                            Text("点击查看笔记")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(quietInk)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(paperSoft.opacity(usesLightForeground ? 1 : 0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(line.opacity(usesLightForeground ? 1 : 0.52), lineWidth: 0.7)
        )
    }
}
