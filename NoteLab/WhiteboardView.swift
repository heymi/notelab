import SwiftUI
import Combine

struct WhiteboardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var aiClient: AIClient
    var onClose: (() -> Void)? = nil

    var body: some View {
        #if os(iOS)
        NoteEditorView(note: $store.whiteboard, isWhiteboard: true, onClose: onClose)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let isEdgeSwipe = value.startLocation.x < 20
                        let isBackSwipe = value.translation.width > 80
                        let isMostlyHorizontal = abs(value.translation.height) < 80
                        if isEdgeSwipe && isBackSwipe && isMostlyHorizontal {
                            onClose?() ?? dismiss()
                        }
                    }
            )
        #else
        NoteEditorView(note: $store.whiteboard)
        #endif
    }
}
