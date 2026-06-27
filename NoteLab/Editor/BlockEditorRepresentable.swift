import Foundation
#if canImport(UIKit)
import SwiftUI

struct BlockEditorRepresentable: UIViewControllerRepresentable {
    @Binding var document: NoteDocument
    @Binding var selectedText: String
    @Binding var selectedRange: NSRange
    @Binding var selectedBlockIds: [UUID]
    @Binding var pendingCommand: EditorCommandRequest?
    @Binding var exitMultiSelectToken: UUID
    @Binding var bodyFocusToken: UUID
    @Binding var title: String
    var titleFocusBridge: TitleFocusBridge
    var headerMetadata: NoteEditorHeaderMetadata
    var linkBlocks: [LinkedNoteBlock]
    var presentationMode: NoteDetailPresentationMode
    var sentHighlightBlockIds: Set<UUID>
    var isWhiteboard: Bool
    var background: NotebookBackground
    var topInset: CGFloat
    var bottomInset: CGFloat
    var onOpenNote: (UUID) -> Void
    var onDocumentChange: (NoteDocument) -> Void
    
    var ownerId: UUID?
    var noteId: UUID?

    final class Coordinator {
        var lastHandledCommandId: UUID?
        var lastExitMultiSelectToken: UUID?
        var lastBodyFocusToken: UUID?
        var lastSentHighlightIds: Set<UUID>?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> BlockEditorViewController {
        let controller = BlockEditorViewController(document: document)
        controller.ownerId = ownerId
        controller.noteId = noteId
        controller.onDocumentChange = { doc in
            onDocumentChange(doc)
        }
        controller.onSelectionChange = { text, range in
            selectedText = text
            selectedRange = range
        }
        controller.onSelectedBlockIdsChange = { ids in
            selectedBlockIds = ids
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: BlockEditorViewController, context: Context) {
        if uiViewController.document != document {
            uiViewController.updateDocument(document)
        }
        uiViewController.ownerId = ownerId
        uiViewController.noteId = noteId
        uiViewController.updatePresentationMode(presentationMode)
        uiViewController.updateContentInsets(top: topInset, bottom: bottomInset)
        uiViewController.updateNotebookBackground(background)
        uiViewController.updateHeader(title: $title, metadata: headerMetadata, linkBlocks: linkBlocks, presentationMode: presentationMode, isWhiteboard: isWhiteboard, focusBridge: titleFocusBridge, onOpenNote: onOpenNote)

        if context.coordinator.lastBodyFocusToken != bodyFocusToken {
            context.coordinator.lastBodyFocusToken = bodyFocusToken
            if presentationMode.isEditing {
                DispatchQueue.main.async {
                    uiViewController.focusPreferredTextBlock()
                }
            }
        }

        if context.coordinator.lastSentHighlightIds != sentHighlightBlockIds {
            context.coordinator.lastSentHighlightIds = sentHighlightBlockIds
            uiViewController.updateSentHighlightBlockIds(sentHighlightBlockIds)
        }

        if context.coordinator.lastExitMultiSelectToken != exitMultiSelectToken {
            context.coordinator.lastExitMultiSelectToken = exitMultiSelectToken
            uiViewController.exitMultiSelectModeIfNeeded()
        }

        if let request = pendingCommand {
            if context.coordinator.lastHandledCommandId != request.id {
                context.coordinator.lastHandledCommandId = request.id
                let command = request.command
                DispatchQueue.main.async {
                    uiViewController.apply(command: command)
                    self.pendingCommand = nil
                }
            }
        }
    }
}
#endif
