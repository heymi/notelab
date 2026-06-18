import CoreData
import Foundation
import os
import SwiftData

enum SwiftDataV3MigrationService {
    private static let logger = Logger(subsystem: "NoteLab", category: "StorageMigration")

    static func migrateIfNeeded(profileId: UUID) async {
        let key = "NoteLab.StorageV3.migrated.\(profileId.uuidString.lowercased())"
        guard UserDefaults.standard.bool(forKey: key) == false else { return }
        guard FileManager.default.fileExists(atPath: PersistenceController.storeURL.path) else {
            UserDefaults.standard.set(StorageController.storageVersion, forKey: "NoteLab.StorageVersion")
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        do {
            try backupLegacyStore()
            let container = try PersistenceController.makeContainer()
            let context = ModelContext(container)
            let ownerId = profileId

            let notebookPredicate = #Predicate<LocalNotebook> { notebook in
                notebook.ownerId == ownerId
            }
            let legacyNotebooks = try context.fetch(FetchDescriptor<LocalNotebook>(predicate: notebookPredicate))

            let notePredicate = #Predicate<LocalNote> { note in
                note.ownerId == ownerId
            }
            let legacyNotes = try context.fetch(FetchDescriptor<LocalNote>(predicate: notePredicate))

            let attachmentPredicate = #Predicate<LocalAttachment> { attachment in
                attachment.ownerId == ownerId
            }
            let legacyAttachments = try context.fetch(FetchDescriptor<LocalAttachment>(predicate: attachmentPredicate))

            try await MainActor.run {
                try migrate(
                    profileId: profileId,
                    notebooks: legacyNotebooks,
                    notes: legacyNotes,
                    attachments: legacyAttachments
                )
            }

            UserDefaults.standard.set(StorageController.storageVersion, forKey: "NoteLab.StorageVersion")
            UserDefaults.standard.set(true, forKey: key)
            logger.info("migration completed notebooks=\(legacyNotebooks.count, privacy: .public) notes=\(legacyNotes.count, privacy: .public) attachments=\(legacyAttachments.count, privacy: .public)")
        } catch {
            logger.error("migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private static func migrate(
        profileId: UUID,
        notebooks: [LocalNotebook],
        notes: [LocalNote],
        attachments: [LocalAttachment]
    ) throws {
        let storage = StorageController.shared
        let context = storage.mainContext
        let profileKey = profileId.uuidString.lowercased()

        for legacy in notebooks {
            let entity = try fetchNotebook(context: context, profileKey: profileKey, id: legacy.id) ?? NotebookEntity(context: context)
            entity.id = legacy.id.uuidString.lowercased()
            entity.profileId = profileKey
            entity.title = legacy.title
            entity.colorRaw = legacy.colorRaw
            entity.iconName = legacy.iconName
            entity.notebookDescription = legacy.notebookDescription
            entity.createdAt = legacy.createdAt
            entity.updatedAt = legacy.remoteUpdatedAt
            entity.deletedAt = legacy.deletedAt
            entity.isPinned = legacy.isPinned
            entity.localRevision = max(entity.localRevision, 1)
            entity.deviceId = DeviceIdentity.getOrCreateDeviceId()
            if legacy.isDirty {
                enqueue(context: context, profileId: profileId, type: .notebook, id: legacy.id, operation: legacy.deletedAt == nil ? .upsert : .delete)
            }
        }

        for legacy in notes {
            guard let notebookId = legacy.notebook?.id else { continue }
            let entity = try fetchNote(context: context, profileKey: profileKey, id: legacy.id) ?? NoteEntity(context: context)
            entity.id = legacy.id.uuidString.lowercased()
            entity.profileId = profileKey
            entity.notebookId = notebookId.uuidString.lowercased()
            entity.title = legacy.title
            entity.summary = legacy.summary
            entity.paragraphCount = Int64(legacy.paragraphCount)
            entity.bulletCount = Int64(legacy.bulletCount)
            entity.hasAdditionalContext = legacy.hasAdditionalContext
            entity.createdAt = legacy.createdAt
            entity.updatedAt = legacy.remoteUpdatedAt
            entity.deletedAt = legacy.deletedAt
            entity.version = Int64(max(legacy.version, 1))
            entity.contentRTF = legacy.contentRTF
            entity.content = legacy.content
            entity.isPinned = legacy.isPinned
            entity.conflictParentId = legacy.conflictParentId?.uuidString.lowercased()
            entity.localRevision = max(entity.localRevision, 1)
            entity.deviceId = DeviceIdentity.getOrCreateDeviceId()
            if legacy.isDirty {
                enqueue(context: context, profileId: profileId, type: .note, id: legacy.id, operation: legacy.deletedAt == nil ? .upsert : .delete)
            }
        }

        for legacy in attachments {
            let entity = try fetchAttachment(context: context, profileKey: profileKey, id: legacy.id) ?? AttachmentEntity(context: context)
            entity.id = legacy.id.uuidString.lowercased()
            entity.profileId = profileKey
            entity.noteId = legacy.noteId.uuidString.lowercased()
            entity.storagePath = legacy.storagePath
            entity.fileName = legacy.fileName
            entity.mimeType = legacy.mimeType
            entity.fileSize = legacy.fileSize
            entity.createdAt = legacy.createdAt
            entity.updatedAt = legacy.remoteUpdatedAt
            entity.deletedAt = legacy.deletedAt
            entity.originalPath = durableOriginalPath(for: legacy)
            entity.missingLocalFile = entity.originalPath == nil
            entity.isUploaded = legacy.isUploaded
            entity.localRevision = max(entity.localRevision, 1)
            entity.deviceId = DeviceIdentity.getOrCreateDeviceId()
            if legacy.isDirty || !legacy.isUploaded {
                enqueue(context: context, profileId: profileId, type: .attachment, id: legacy.id, operation: legacy.deletedAt == nil ? .upsert : .delete)
            }
        }

        try storage.saveMainContext()
    }

    private static func durableOriginalPath(for legacy: LocalAttachment) -> String? {
        let candidates = [
            legacy.localCachePath.map(URL.init(fileURLWithPath:)),
            Optional(AttachmentCache.localCacheURL(for: legacy.id, fileName: legacy.fileName))
        ].compactMap { $0 }

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return try AttachmentFileStore.saveOriginal(data: data, attachmentId: legacy.id, fileName: legacy.fileName).path
            } catch {
                logger.error("attachment migration copy failed \(legacy.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    private static func backupLegacyStore() throws {
        let sourceBase = PersistenceController.storeURL
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: sourceBase.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let backup = source.deletingLastPathComponent()
                .appendingPathComponent("LegacyBackups", isDirectory: true)
                .appendingPathComponent(source.lastPathComponent + ".\(stamp).bak")
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.copyItem(at: source, to: backup)
            }
        }
    }

    private static func fetchNotebook(context: NSManagedObjectContext, profileKey: String, id: UUID) throws -> NotebookEntity? {
        let request = NotebookEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND id == %@", profileKey, id.uuidString.lowercased())
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func fetchNote(context: NSManagedObjectContext, profileKey: String, id: UUID) throws -> NoteEntity? {
        let request = NoteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND id == %@", profileKey, id.uuidString.lowercased())
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func fetchAttachment(context: NSManagedObjectContext, profileKey: String, id: UUID) throws -> AttachmentEntity? {
        let request = AttachmentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND id == %@", profileKey, id.uuidString.lowercased())
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func enqueue(context: NSManagedObjectContext, profileId: UUID, type: SyncEntityType, id: UUID, operation: SyncOperation) {
        let now = Date()
        let item = SyncOutboxEntity(context: context)
        item.id = UUID().uuidString.lowercased()
        item.profileId = profileId.uuidString.lowercased()
        item.entityType = type.rawValue
        item.entityId = id.uuidString.lowercased()
        item.operation = operation.rawValue
        item.createdAt = now
        item.updatedAt = now
        item.retryCount = 0
        item.status = OutboxStatus.pending.rawValue
    }
}
