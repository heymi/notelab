import Foundation
#if canImport(UIKit)
import SwiftUI
import SwiftData

struct BlockEditorRepresentable: UIViewControllerRepresentable {
    @Binding var document: NoteDocument
    @Binding var selectedText: String
    @Binding var selectedRange: NSRange
    @Binding var selectedBlockIds: [UUID]
    @Binding var pendingCommand: EditorCommandRequest?
    @Binding var exitMultiSelectToken: UUID
    @Binding var title: String
    var titleFocusBridge: TitleFocusBridge
    var linkBlocks: [LinkedNoteBlock]
    var sentHighlightBlockIds: Set<UUID>
    var isWhiteboard: Bool
    var topInset: CGFloat
    var bottomInset: CGFloat
    var onOpenNote: (UUID) -> Void
    var onDocumentChange: (NoteDocument) -> Void
    
    // Attachment storage context
    var modelContext: ModelContext?
    var ownerId: UUID?
    var noteId: UUID?

    final class Coordinator {
        var lastHandledCommandId: UUID?
        var lastExitMultiSelectToken: UUID?
        var lastSentHighlightIds: Set<UUID>?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> BlockEditorViewController {
        let controller = BlockEditorViewController(document: document)
        controller.modelContext = modelContext
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
        // Update attachment storage context
        uiViewController.modelContext = modelContext
        uiViewController.ownerId = ownerId
        uiViewController.noteId = noteId
        uiViewController.updateContentInsets(top: topInset, bottom: bottomInset)
        uiViewController.updateHeader(title: $title, linkBlocks: linkBlocks, isWhiteboard: isWhiteboard, focusBridge: titleFocusBridge, onOpenNote: onOpenNote)

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