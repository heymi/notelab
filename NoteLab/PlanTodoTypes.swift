import Foundation

struct LocalTodoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let noteId: UUID
    let noteTitle: String
    let notebookId: UUID
    let notebookTitle: String
    let lineIndex: Int
    let isWhiteboard: Bool
}
