import Foundation

struct LinkedNoteBlock: Identifiable, Codable, Hashable {
    let id: UUID
    let noteId: UUID
    let notebookId: UUID
    let title: String
    let sourceRangeLocation: Int?
    let sourceRangeLength: Int?
    let sourceBlockIds: [UUID]?
}
