import Foundation
#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct BlockEditorRepresentableMac: NSViewControllerRepresentable {
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
    
    func makeNSViewController(context: Context) -> BlockEditorViewControllerMac {
        let controller = BlockEditorViewControllerMac(document: document)
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
    
    func updateNSViewController(_ nsViewController: BlockEditorViewControllerMac, context: Context) {
        if nsViewController.document != document {
            nsViewController.updateDocument(document)
        }
        
        // Update attachment storage context
        nsViewController.modelContext = modelContext
        nsViewController.ownerId = ownerId
        nsViewController.noteId = noteId
        
        // Update header
        nsViewController.updateHeader(
            title: $title,
            linkBlocks: linkBlocks,
            isWhiteboard: isWhiteboard,
            focusBridge: titleFocusBridge,
            onOpenNote: onOpenNote
        )
        
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
