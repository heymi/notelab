import Foundation

struct MemorySnippet: Identifiable, Hashable {
    let id: UUID
    let noteId: UUID
    let noteTitle: String
    let notebookTitle: String
    let excerpt: String
    let imageData: Data?
    let createdAt: Date
}

struct MessyNoteCandidate: Identifiable, Hashable {
    let id: UUID
    let noteId: UUID
    let noteTitle: String
    let notebookTitle: String
    let reason: String
}

struct NoteConnection: Identifiable, Hashable, Codable {
    let id: UUID
    let sourceNoteId: UUID
    let targetNoteId: UUID
    let sourceTitle: String
    let targetTitle: String
    let reason: String
}
