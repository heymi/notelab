import Foundation

struct NoteUndoSnapshot: Codable, Equatable {
    let title: String?
    let content: String
    let createdAt: Date
}

enum NoteUndoSnapshotStore {
    static func load(noteId: UUID) -> NoteUndoSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(for: noteId)) else { return nil }
        return try? JSONDecoder().decode(NoteUndoSnapshot.self, from: data)
    }

    static func save(noteId: UUID, title: String?, content: String) {
        let snapshot = NoteUndoSnapshot(title: title, content: content, createdAt: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key(for: noteId))
        }
    }

    static func clear(noteId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: noteId))
    }

    private static func key(for noteId: UUID) -> String {
        "note.undo.snapshot.\(noteId.uuidString)"
    }
}
