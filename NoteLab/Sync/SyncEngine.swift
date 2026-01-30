import Foundation
import Combine
import SwiftData
import Supabase

@MainActor
final class SyncEngine: ObservableObject {
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?

    private var ownerId: UUID?
    private var modelContext: ModelContext?
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseManager.shared) {
        self.supabase = supabase
    }

    func configure(ownerId: UUID, context: ModelContext) {
        self.ownerId = ownerId
        self.modelContext = context
    }

    func resetForSignOut() {
        ownerId = nil
        modelContext = nil
        isSyncing = false
        lastSyncAt = nil
        lastError = nil
    }

    func syncNow() async {
        guard let ownerId, let modelContext else { return }
        if isSyncing { return }
        if Task.isCancelled { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await pushDirty()
            if Task.isCancelled { return }
            await Task.yield()
            try await pushDirtyAttachments()
            if Task.isCancelled { return }
            await Task.yield()
            try await pullIncremental()
            if Task.isCancelled { return }
            await Task.yield()
            try await pullAttachments()
            if Task.isCancelled { return }
            await Task.yield()
            if modelContext.hasChanges {
                try modelContext.save()
                print("SyncEngine: modelContext saved")
            } else {
                print("SyncEngine: modelContext has no changes")
            }
            await Task.yield()
            lastSyncAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Pull

    private func pullIncremental() async throws {
        try await pullNotebooks()
        try await pullNotes()
    }

    private func pullNotebooks() async throws {
        guard let ownerId, let modelContext else { return }
        let watermark = try getWatermark(entity: "notebooks", ownerId: ownerId, context: modelContext)

        let rows: [RemoteNotebookRow]
        if let watermark {
            rows = try await supabase
                .from("notebooks")
                .select()
                .gt("updated_at", value: iso(watermark))
                .order("updated_at", ascending: true)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("notebooks")
                .select()
                .order("updated_at", ascending: true)
                .execute()
                .value
        }
        guard !rows.isEmpty else { return }
        print("SyncEngine: pullNotebooks count=\(rows.count) lastId=\(rows.last?.id.uuidString ?? "nil")")

        for (index, row) in rows.enumerated() {
            upsertLocalNotebook(from: row, ownerId: ownerId, context: modelContext)
            if index % 10 == 0 {
                await Task.yield()
            }
        }

        if let maxUpdatedAt = rows.compactMap({ $0.updatedAtDate }).max() {
            try setWatermark(entity: "notebooks", ownerId: ownerId, context: modelContext, date: maxUpdatedAt)
        }
    }

    private func pullNotes() async throws {
        guard let ownerId, let modelContext else { return }
        let watermark = try getWatermark(entity: "notes", ownerId: ownerId, context: modelContext)

        let rows: [RemoteNoteRow]
        if let watermark {
            rows = try await supabase
                .from("notes")
                .select()
                .gt("updated_at", value: iso(watermark))
                .order("updated_at", ascending: true)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("notes")
                .select()
                .order("updated_at", ascending: true)
                .execute()
                .value
        }
        guard !rows.isEmpty else { return }
        print("SyncEngine: pullNotes count=\(rows.count) lastId=\(rows.last?.id.uuidString ?? "nil")")

        for (index, row) in rows.enumerated() {
            upsertLocalNote(from: row, ownerId: ownerId, context: modelContext)
            if index % 10 == 0 {
                await Task.yield()
            }
        }

        if let maxUpdatedAt = rows.compactMap({ $0.updatedAtDate }).max() {
            try setWatermark(entity: "notes", ownerId: ownerId, context: modelContext, date: maxUpdatedAt)
        }
    }

    // MARK: - Push

    private func pushDirty() async throws {
        try await pushDirtyNotebooks()
        try await pushDirtyNotes()
    }

    private func pushDirtyNotebooks() async throws {
        guard let ownerId, let modelContext else { return }

        let pred = #Predicate<LocalNotebook> { nb in
            nb.ownerId == ownerId && nb.isDirty == true
        }
        let fetch = FetchDescriptor<LocalNotebook>(predicate: pred)
        let dirty = try modelContext.fetch(fetch)

        for local in dirty {
            let payload = NotebookUpsert(
                id: local.id,
                userId: ownerId,
                title: local.title,
                color: local.colorRaw,
                iconName: local.iconName,
                deletedAt: local.deletedAt
            )
            let returned: [RemoteNotebookRow] = try await supabase
                .from("notebooks")
                .upsert(payload)
                .select()
                .execute()
                .value

            if let row = returned.first {
                local.remoteUpdatedAt = row.updatedAtDate ?? local.remoteUpdatedAt
            } else {
                local.remoteUpdatedAt = Date()
            }
            local.isDirty = false
        }
    }

    private func pushDirtyNotes() async throws {
        guard let ownerId, let modelContext else { return }

        let pred = #Predicate<LocalNote> { n in
            n.ownerId == ownerId && n.isDirty == true
        }
        let fetch = FetchDescriptor<LocalNote>(predicate: pred)
        let dirty = try modelContext.fetch(fetch)

        for local in dirty {
            guard let notebookId = local.notebook?.id else { continue }

            // 1) Try optimistic-lock update: id + expected version.
            let updatePayload = NoteUpdatePayload(
                notebookId: notebookId,
                title: local.title,
                summary: local.summary,
                content: local.content,
                paragraphCount: local.paragraphCount,
                bulletCount: local.bulletCount,
                hasAdditionalContext: local.hasAdditionalContext,
                deletedAt: local.deletedAt
            )

            let updated: [RemoteNoteRow] = try await supabase
                .from("notes")
                .update(updatePayload)
                .eq("id", value: local.id.uuidString)
                .eq("version", value: local.version)
                .select()
                .execute()
                .value

            if let row = updated.first {
                local.remoteUpdatedAt = row.updatedAtDate ?? local.remoteUpdatedAt
                local.version = row.version ?? local.version
                local.isDirty = false
                continue
            }

            // 2) If nothing updated, distinguish between (a) not exists (create) vs (b) conflict (duplicate).
            let remoteRows: [RemoteNoteRow] = try await supabase
                .from("notes")
                .select()
                .eq("id", value: local.id.uuidString)
                .limit(1)
                .execute()
                .value

            if remoteRows.isEmpty {
                // Not on server yet → create via upsert.
                let payload = NoteUpsert(
                    id: local.id,
                    userId: ownerId,
                    notebookId: notebookId,
                    title: local.title,
                    summary: local.summary,
                    content: local.content,
                    paragraphCount: local.paragraphCount,
                    bulletCount: local.bulletCount,
                    hasAdditionalContext: local.hasAdditionalContext,
                    deletedAt: local.deletedAt
                )

                let inserted: [RemoteNoteRow] = try await supabase
                    .from("notes")
                    .upsert(payload)
                    .select()
                    .execute()
                    .value

                if let row = inserted.first {
                    local.remoteUpdatedAt = row.updatedAtDate ?? local.remoteUpdatedAt
                    local.version = row.version ?? local.version
                } else {
                    local.remoteUpdatedAt = Date()
                }
                local.isDirty = false
                continue
            }

            // Conflict: server has a different version.
            guard let remote = remoteRows.first else { continue }

            // Snapshot local unsynced changes for conflict copy.
            let snapshot = NoteSnapshot(
                title: local.title,
                summary: local.summary,
                content: local.content,
                paragraphCount: local.paragraphCount,
                bulletCount: local.bulletCount,
                hasAdditionalContext: local.hasAdditionalContext,
                deletedAt: local.deletedAt
            )

            // Apply server version to original note (accept remote).
            local.title = remote.title
            local.summary = remote.summary
            local.content = remote.content
            local.paragraphCount = remote.paragraphCount
            local.bulletCount = remote.bulletCount
            local.hasAdditionalContext = remote.hasAdditionalContext
            local.deletedAt = remote.deletedAtDate
            local.remoteUpdatedAt = remote.updatedAtDate ?? local.remoteUpdatedAt
            local.version = remote.version ?? local.version
            local.isDirty = false

            // Create a "conflict copy" note with the local snapshot.
            let conflictNote = LocalNote(
                id: UUID(),
                ownerId: ownerId,
                title: snapshot.title + " (冲突副本)",
                summary: snapshot.summary,
                paragraphCount: snapshot.paragraphCount,
                bulletCount: snapshot.bulletCount,
                hasAdditionalContext: snapshot.hasAdditionalContext,
                createdAt: Date(),
                remoteUpdatedAt: Date(),
                version: 1,
                deletedAt: snapshot.deletedAt,
                contentRTF: nil,
                content: snapshot.content,
                isDirty: true,
                conflictParentId: local.id,
                notebook: local.notebook
            )
            modelContext.insert(conflictNote)
            // Note: SwiftData automatically manages inverse relationships,
            // no need to manually append to notebook.notes
        }
    }

    // MARK: - Attachment Sync
    
    private func pushDirtyAttachments() async throws {
        guard let ownerId, let modelContext else { return }
        
        // Upload pending attachments to Supabase Storage
        try await AttachmentStorage.shared.uploadPendingAttachments(context: modelContext, ownerId: ownerId)
        
        // Now push metadata to attachments table
        let pred = #Predicate<LocalAttachment> { att in
            att.ownerId == ownerId && att.isDirty == true && att.isUploaded == true
        }
        let fetch = FetchDescriptor<LocalAttachment>(predicate: pred)
        let dirty = try modelContext.fetch(fetch)
        
        for local in dirty {
            let payload = AttachmentUpsert(
                id: local.id,
                userId: ownerId,
                noteId: local.noteId,
                storagePath: local.storagePath,
                fileName: local.fileName,
                mimeType: local.mimeType,
                fileSize: local.fileSize,
                deletedAt: local.deletedAt
            )
            
            let returned: [RemoteAttachmentRow] = try await supabase
                .from("attachments")
                .upsert(payload)
                .select()
                .execute()
                .value
            
            if let row = returned.first {
                local.remoteUpdatedAt = row.updatedAtDate ?? local.remoteUpdatedAt
            } else {
                local.remoteUpdatedAt = Date()
            }
            local.isDirty = false
        }
    }
    
    private func pullAttachments() async throws {
        guard let ownerId, let modelContext else { return }
        let watermark = try getWatermark(entity: "attachments", ownerId: ownerId, context: modelContext)
        
        let rows: [RemoteAttachmentRow]
        if let watermark {
            rows = try await supabase
                .from("attachments")
                .select()
                .gt("updated_at", value: iso(watermark))
                .order("updated_at", ascending: true)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("attachments")
                .select()
                .order("updated_at", ascending: true)
                .execute()
                .value
        }
        guard !rows.isEmpty else { return }
        print("SyncEngine: pullAttachments count=\(rows.count) lastId=\(rows.last?.id.uuidString ?? "nil")")
        
        for row in rows {
            upsertLocalAttachment(from: row, ownerId: ownerId, context: modelContext)
        }
        
        if let maxUpdatedAt = rows.compactMap({ $0.updatedAtDate }).max() {
            try setWatermark(entity: "attachments", ownerId: ownerId, context: modelContext, date: maxUpdatedAt)
        }
    }
    
    private func upsertLocalAttachment(from row: RemoteAttachmentRow, ownerId: UUID, context: ModelContext) {
        guard row.isValid else {
            print("SyncEngine: skipping attachment with invalid id")
            return
        }
        let id = row.id
        let pred = #Predicate<LocalAttachment> { att in
            att.ownerId == ownerId && att.id == id
        }
        
        do {
            let fetch = FetchDescriptor<LocalAttachment>(predicate: pred)
            if let existing = try context.fetch(fetch).first {
                if existing.isDirty { return } // avoid overwriting local unsynced edits
                existing.storagePath = row.storagePath
                existing.fileName = row.fileName
                existing.mimeType = row.mimeType
                existing.fileSize = row.fileSize
                existing.deletedAt = row.deletedAtDate
                if let updatedAt = row.updatedAtDate { existing.remoteUpdatedAt = updatedAt }
                return
            }
            
            let createdAt = row.createdAtDate ?? Date()
            let updatedAt = row.updatedAtDate ?? createdAt
            let local = LocalAttachment(
                id: id,
                ownerId: ownerId,
                noteId: row.noteId,
                storagePath: row.storagePath,
                fileName: row.fileName,
                mimeType: row.mimeType,
                fileSize: row.fileSize,
                createdAt: createdAt,
                remoteUpdatedAt: updatedAt,
                deletedAt: row.deletedAtDate,
                localCachePath: nil,
                isDirty: false,
                isUploaded: true
            )
            context.insert(local)
        } catch {
            // ignore
        }
    }

    // MARK: - Local upsert helpers

    private func upsertLocalNotebook(from row: RemoteNotebookRow, ownerId: UUID, context: ModelContext) {
        guard row.isValid else {
            print("SyncEngine: skipping notebook with invalid id")
            return
        }
        let id = row.id
        let pred = #Predicate<LocalNotebook> { nb in
            nb.ownerId == ownerId && nb.id == id
        }

        do {
            let fetch = FetchDescriptor<LocalNotebook>(predicate: pred)
            if let existing = try context.fetch(fetch).first {
                if existing.isDirty { return } // avoid overwriting local unsynced edits
                
                // Prevent "resurrection" of locally deleted items:
                // If local is deleted but remote is not, preserve local deletion ONLY if local is dirty.
                if existing.deletedAt != nil && row.deletedAtDate == nil {
                    if existing.isDirty {
                        return
                    }
                    existing.deletedAt = nil
                }
                
                existing.title = row.title
                existing.colorRaw = row.color
                existing.iconName = row.iconName
                existing.deletedAt = row.deletedAtDate
                if let updatedAt = row.updatedAtDate { existing.remoteUpdatedAt = updatedAt }
                return
            }

            let createdAt = row.createdAtDate ?? Date()
            let updatedAt = row.updatedAtDate ?? createdAt
            let local = LocalNotebook(
                id: id,
                ownerId: ownerId,
                title: row.title,
                colorRaw: row.color,
                iconName: row.iconName,
                createdAt: createdAt,
                remoteUpdatedAt: updatedAt,
                deletedAt: row.deletedAtDate,
                isDirty: false,
                notes: []
            )
            context.insert(local)
        } catch {
            // ignore
        }
    }

    private func upsertLocalNote(from row: RemoteNoteRow, ownerId: UUID, context: ModelContext) {
        guard row.isValid else {
            print("SyncEngine: skipping note with invalid id or notebookId")
            return
        }
        let id = row.id
        let notebookId = row.notebookId

        do {
            // Ensure notebook exists (notes may arrive before notebooks on fresh sync).
            let nbPred = #Predicate<LocalNotebook> { nb in
                nb.ownerId == ownerId && nb.id == notebookId
            }
            let nbFetch = FetchDescriptor<LocalNotebook>(predicate: nbPred)
            let notebook = try context.fetch(nbFetch).first

            let pred = #Predicate<LocalNote> { n in
                n.ownerId == ownerId && n.id == id
            }
            let fetch = FetchDescriptor<LocalNote>(predicate: pred)

            if let existing = try context.fetch(fetch).first {
                if existing.isDirty { return } // avoid overwriting local unsynced edits
                
                // Prevent "resurrection" of locally deleted items:
                // If local is deleted but remote is not, preserve local deletion ONLY if local is dirty.
                if existing.deletedAt != nil && row.deletedAtDate == nil {
                    if existing.isDirty {
                        return
                    }
                    existing.deletedAt = nil
                }
                
                existing.title = row.title
                existing.summary = row.summary
                existing.content = row.content
                existing.paragraphCount = row.paragraphCount
                existing.bulletCount = row.bulletCount
                existing.hasAdditionalContext = row.hasAdditionalContext
                existing.deletedAt = row.deletedAtDate
                if let updatedAt = row.updatedAtDate { existing.remoteUpdatedAt = updatedAt }
                if let version = row.version { existing.version = version }
                existing.notebook = notebook
                return
            }

            let createdAt = row.createdAtDate ?? Date()
            let updatedAt = row.updatedAtDate ?? createdAt
            let local = LocalNote(
                id: id,
                ownerId: ownerId,
                title: row.title,
                summary: row.summary,
                paragraphCount: row.paragraphCount,
                bulletCount: row.bulletCount,
                hasAdditionalContext: row.hasAdditionalContext,
                createdAt: createdAt,
                remoteUpdatedAt: updatedAt,
                version: row.version ?? 1,
                deletedAt: row.deletedAtDate,
                contentRTF: nil,
                content: row.content,
                isDirty: false,
                conflictParentId: nil,
                notebook: notebook
            )
            context.insert(local)
            // Note: SwiftData automatically manages inverse relationships,
            // no need to manually append to notebook.notes
        } catch {
            // ignore
        }
    }

    // MARK: - Watermark

    private func getWatermark(entity: String, ownerId: UUID, context: ModelContext) throws -> Date? {
        let key = "\(ownerId.uuidString):\(entity)"
        let pred = #Predicate<SyncMetadata> { meta in
            meta.key == key
        }
        let fetch = FetchDescriptor<SyncMetadata>(predicate: pred)
        return try context.fetch(fetch).first?.lastPulledAt
    }

    private func setWatermark(entity: String, ownerId: UUID, context: ModelContext, date: Date) throws {
        let key = "\(ownerId.uuidString):\(entity)"
        let pred = #Predicate<SyncMetadata> { meta in
            meta.key == key
        }
        let fetch = FetchDescriptor<SyncMetadata>(predicate: pred)
        if let existing = try context.fetch(fetch).first {
            existing.lastPulledAt = date
        } else {
            context.insert(SyncMetadata(ownerId: ownerId, entity: entity, lastPulledAt: date))
        }
    }

    // MARK: - ISO8601

    private func iso(_ date: Date) -> String {
        // Use a stable format for PostgREST filters.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

// MARK: - Remote types

private struct RemoteNotebookRow: Decodable {
    let id: UUID
    let title: String
    let color: String
    let iconName: String
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let isValid: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case color
        case iconName = "icon_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decodeIfPresent(UUID.self, forKey: .id)
        let title = (try container.decodeIfPresent(String.self, forKey: .title))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = (try container.decodeIfPresent(String.self, forKey: .color))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconName = (try container.decodeIfPresent(String.self, forKey: .iconName))?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.id = decodedId ?? UUID()
        self.title = title?.isEmpty == false ? title! : "未命名笔记本"
        self.color = color?.isEmpty == false ? color! : NotebookColor.lime.rawValue
        self.iconName = iconName?.isEmpty == false ? iconName! : "book"
        self.isValid = decodedId != nil
    }

    var createdAtDate: Date? { parseISO(createdAt) }
    var updatedAtDate: Date? { parseISO(updatedAt) }
    var deletedAtDate: Date? { parseISO(deletedAt) }
}

private struct RemoteNoteRow: Decodable {
    let id: UUID
    let notebookId: UUID
    let title: String
    let summary: String
    let content: String
    let paragraphCount: Int
    let bulletCount: Int
    let hasAdditionalContext: Bool
    let version: Int?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let isValid: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case notebookId = "notebook_id"
        case title
        case summary
        case content
        case paragraphCount = "paragraph_count"
        case bulletCount = "bullet_count"
        case hasAdditionalContext = "has_additional_context"
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decodeIfPresent(UUID.self, forKey: .id)
        let decodedNotebookId = try container.decodeIfPresent(UUID.self, forKey: .notebookId)
        let title = (try container.decodeIfPresent(String.self, forKey: .title))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (try container.decodeIfPresent(String.self, forKey: .summary))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (try container.decodeIfPresent(String.self, forKey: .content))
        self.paragraphCount = try container.decodeIfPresent(Int.self, forKey: .paragraphCount) ?? 0
        self.bulletCount = try container.decodeIfPresent(Int.self, forKey: .bulletCount) ?? 0
        self.hasAdditionalContext = try container.decodeIfPresent(Bool.self, forKey: .hasAdditionalContext) ?? false
        self.version = try container.decodeIfPresent(Int.self, forKey: .version)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.id = decodedId ?? UUID()
        self.notebookId = decodedNotebookId ?? UUID()
        self.title = title?.isEmpty == false ? title! : "未命名笔记"
        self.summary = summary ?? ""
        self.content = content ?? ""
        self.isValid = decodedId != nil && decodedNotebookId != nil
    }

    var createdAtDate: Date? { parseISO(createdAt) }
    var updatedAtDate: Date? { parseISO(updatedAt) }
    var deletedAtDate: Date? { parseISO(deletedAt) }
}

private struct NotebookUpsert: Encodable {
    let id: UUID
    let userId: UUID
    let title: String
    let color: String
    let iconName: String
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case color
        case iconName = "icon_name"
        case deletedAt = "deleted_at"
    }
}

private struct NoteUpsert: Encodable {
    let id: UUID
    let userId: UUID
    let notebookId: UUID
    let title: String
    let summary: String
    let content: String
    let paragraphCount: Int
    let bulletCount: Int
    let hasAdditionalContext: Bool
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case notebookId = "notebook_id"
        case title
        case summary
        case content
        case paragraphCount = "paragraph_count"
        case bulletCount = "bullet_count"
        case hasAdditionalContext = "has_additional_context"
        case deletedAt = "deleted_at"
    }
}

private struct NoteUpdatePayload: Encodable {
    let notebookId: UUID
    let title: String
    let summary: String
    let content: String
    let paragraphCount: Int
    let bulletCount: Int
    let hasAdditionalContext: Bool
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case notebookId = "notebook_id"
        case title
        case summary
        case content
        case paragraphCount = "paragraph_count"
        case bulletCount = "bullet_count"
        case hasAdditionalContext = "has_additional_context"
        case deletedAt = "deleted_at"
    }
}

private struct NoteSnapshot {
    let title: String
    let summary: String
    let content: String
    let paragraphCount: Int
    let bulletCount: Int
    let hasAdditionalContext: Bool
    let deletedAt: Date?
}

// MARK: - Attachment Remote Types

private struct RemoteAttachmentRow: Decodable {
    let id: UUID
    let noteId: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let isValid: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case storagePath = "storage_path"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decodeIfPresent(UUID.self, forKey: .id)
        let decodedNoteId = try container.decodeIfPresent(UUID.self, forKey: .noteId)
        let storagePath = (try container.decodeIfPresent(String.self, forKey: .storagePath))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (try container.decodeIfPresent(String.self, forKey: .fileName))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mimeType = (try container.decodeIfPresent(String.self, forKey: .mimeType))?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.id = decodedId ?? UUID()
        self.noteId = decodedNoteId ?? UUID()
        self.storagePath = storagePath ?? ""
        self.fileName = fileName ?? ""
        self.mimeType = mimeType ?? "application/octet-stream"
        self.isValid = decodedId != nil && decodedNoteId != nil
    }
    
    var createdAtDate: Date? { parseISO(createdAt) }
    var updatedAtDate: Date? { parseISO(updatedAt) }
    var deletedAtDate: Date? { parseISO(deletedAt) }
}

private struct AttachmentUpsert: Encodable {
    let id: UUID
    let userId: UUID
    let noteId: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let deletedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case noteId = "note_id"
        case storagePath = "storage_path"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case deletedAt = "deleted_at"
    }
}

private func parseISO(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: value) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: value)
}

