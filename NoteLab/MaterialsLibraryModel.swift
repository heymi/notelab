import Foundation
import SwiftData
import Combine

final class MaterialsLibraryModel: ObservableObject {
    @Published private(set) var groups: [MaterialGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false

    private var refreshTask: Task<Void, Never>?

    func refresh(ownerId: UUID?, attachments: [LocalAttachment], notes: [LocalNote]) {
        refreshTask?.cancel()
        guard let ownerId else {
            groups = []
            hasLoadedOnce = true
            return
        }
        isLoading = true
        let attachmentsSnapshot = attachments
        let notesSnapshot = notes
        refreshTask = Task.detached(priority: .utility) {
            let computed = Self.buildGroups(attachments: attachmentsSnapshot, notes: notesSnapshot, ownerId: ownerId)
            await MainActor.run {
                self.groups = computed
                self.isLoading = false
                self.hasLoadedOnce = true
            }
        }
    }

    private static func buildGroups(attachments: [LocalAttachment], notes: [LocalNote], ownerId: UUID) -> [MaterialGroup] {
        let noteLookup = notes
            .filter { $0.ownerId == ownerId }
            .reduce(into: [UUID: LocalNote]()) { $0[$1.id] = $1 }

        let validAttachments = attachments
            .filter { $0.ownerId == ownerId }
            .filter { noteLookup[$0.noteId] != nil }

        let grouped = Dictionary(grouping: validAttachments, by: \.noteId)
        var results: [MaterialGroup] = []
        results.reserveCapacity(grouped.count)

        for (noteId, items) in grouped {
            guard let note = noteLookup[noteId] else { continue }
            let sorted = items.sorted { $0.createdAt > $1.createdAt }
            let newestAt = sorted.first?.createdAt ?? Date.distantPast
            results.append(
                MaterialGroup(
                    id: noteId,
                    noteId: noteId,
                    noteTitle: note.title.isEmpty ? "无标题" : note.title,
                    attachments: sorted,
                    newestAt: newestAt
                )
            )
        }

        return results.sorted { $0.newestAt > $1.newestAt }
    }
}
