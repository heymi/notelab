import Foundation
#if os(macOS)
import SwiftUI
import AppKit

struct BlockEditorRepresentableMac: NSViewControllerRepresentable {
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
    
    func makeNSViewController(context: Context) -> BlockEditorViewControllerMac {
        let controller = BlockEditorViewControllerMac(document: document)
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
    
    func updateNSViewController(_ nsViewController: BlockEditorViewControllerMac, context: Context) {
        if nsViewController.document != document {
            nsViewController.updateDocument(document)
        }
        
        nsViewController.ownerId = ownerId
        nsViewController.noteId = noteId
        
        // Update header
        nsViewController.updateHeader(
            title: $title,
            metadata: headerMetadata,
            linkBlocks: linkBlocks,
            presentationMode: presentationMode,
            isWhiteboard: isWhiteboard,
            focusBridge: titleFocusBridge,
            onOpenNote: onOpenNote
        )
        nsViewController.updatePresentationMode(presentationMode)

        if context.coordinator.lastBodyFocusToken != bodyFocusToken {
            context.coordinator.lastBodyFocusToken = bodyFocusToken
            if presentationMode.isEditing {
                DispatchQueue.main.async {
                    nsViewController.focusPreferredTextBlock()
                }
            }
        }
        
        // Update sent highlight
        if context.coordinator.lastSentHighlightIds != sentHighlightBlockIds {
            context.coordinator.lastSentHighlightIds = sentHighlightBlockIds
            nsViewController.updateSentHighlightBlockIds(sentHighlightBlockIds)
        }
        
        // Handle pending command
        if let request = pendingCommand {
            if context.coordinator.lastHandledCommandId != request.id {
                context.coordinator.lastHandledCommandId = request.id
                nsViewController.apply(command: request.command)
            }
        }
    }
}

#endif
