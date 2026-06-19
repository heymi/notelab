import Foundation
import Combine

@MainActor
final class MaterialsLibraryModel: ObservableObject {
    @Published private(set) var groups: [MaterialGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false

    private let repository = AttachmentRepository()

    func refresh(profileId: UUID?, legacyProfileId: UUID?, notebooks: [Notebook]) {
        guard let profileId else {
            groups = []
            hasLoadedOnce = true
            return
        }
        isLoading = true
        let flatNotes = notebooks.flatMap(\.notes)
        let noteIds = Set(flatNotes.map(\.id))
        do {
            var profileIds = [profileId]
            if let legacyProfileId, legacyProfileId != profileId {
                profileIds.append(legacyProfileId)
            }
            let attachments = try repository.list(profileIds: profileIds, noteIds: noteIds)
            let computed = Self.buildGroups(attachments: attachments, notes: flatNotes)
            groups = computed
            isLoading = false
            hasLoadedOnce = true
        } catch {
            groups = []
            isLoading = false
            hasLoadedOnce = true
        }
    }

    private static func buildGroups(attachments: [AttachmentRecord], notes: [Note]) -> [MaterialGroup] {
        let noteLookup = notes
            .reduce(into: [UUID: Note]()) { $0[$1.id] = $1 }

        let validAttachments = attachments
            .filter { noteLookup[$0.noteId] != nil }
            .reduce(into: [UUID: AttachmentRecord]()) { result, attachment in
                if let existing = result[attachment.id], existing.updatedAt >= attachment.updatedAt {
                    return
                }
                result[attachment.id] = attachment
            }
            .map(\.value)

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
