import SwiftUI
import Combine

struct NoteEditorHeaderView: View {
    @Binding var title: String
    @ObservedObject var focusBridge: TitleFocusBridge
    let linkBlocks: [LinkedNoteBlock]
    let isWhiteboard: Bool
    let onOpenNote: (UUID) -> Void
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if isWhiteboard {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("标题", text: $title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)

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
