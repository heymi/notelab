import CoreData
import CryptoKit
import Foundation
import os

enum SyncEntityType: String, Codable {
    case notebook = "Notebook"
    case note = "Note"
    case attachment = "Attachment"
}

enum SyncOperation: String, Codable {
    case upsert
    case delete
}

enum OutboxStatus: String {
    case pending
    case syncing
    case failed
    case done
}

struct ProfileScope: Equatable, Hashable {
    let profileId: UUID
    let displayEmail: String?
    let displayName: String?

    var key: String {
        profileId.uuidString.lowercased()
    }
}

struct AttachmentRecord: Hashable {
    let id: UUID
    let profileId: UUID
    let noteId: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let originalPath: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let missingLocalFile: Bool
    let isUploaded: Bool
}

struct OutboxItem {
    let id: UUID
    let profileId: UUID
    let entityType: SyncEntityType
    let entityId: UUID
    let operation: SyncOperation
    let retryCount: Int
}

@MainActor
final class ProfileRepository {
    private let storage: StorageController
    private let logger = Logger(subsystem: "NoteLab", category: "ProfileRepository")

    init(storage: StorageController = .shared) {
        self.storage = storage
    }

    func ensureProfile(account: AppleAccount) throws -> ProfileScope {
        if let error = storage.openError {
            throw StorageError.storeOpenFailed(error.localizedDescription)
        }

        let context = storage.mainContext
        let profileId = account.localUserId.uuidString.lowercased()
        let request = UserProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", profileId)
        request.fetchLimit = 1

        let now = Date()
        let existing = try context.fetch(request).first
        let entity = existing ?? UserProfileEntity(context: context)
        if existing == nil {
            entity.id = profileId
            entity.createdAt = now
        }
        entity.appleUserHash = Self.hash(account.appleUserId)
        entity.displayEmail = account.email
        entity.displayName = account.displayName
        entity.updatedAt = now
        entity.isLocked = false
        try storage.saveMainContext()
        logger.info("profile ready \(profileId, privacy: .public)")
        return ProfileScope(profileId: account.localUserId, displayEmail: account.email, displayName: account.displayName)
    }

    func lockProfile(profileId: UUID) throws {
        let context = storage.mainContext
        let request = UserProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", profileId.uuidString.lowercased())
        request.fetchLimit = 1
        if let entity = try context.fetch(request).first {
            entity.isLocked = true
            entity.updatedAt = Date()
            try storage.saveMainContext()
        }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class NotebookRepository {
    private let storage: StorageController
    private let logger = Logger(subsystem: "NoteLab", category: "NotebookRepository")

    init(storage: StorageController = .shared) {
        self.storage = storage
    }

    func loadNotebooks(profileId: UUID) throws -> [Notebook] {
        if let error = storage.openError {
            throw StorageError.storeOpenFailed(error.localizedDescription)
        }

        let context = storage.mainContext
        let profileKey = profileId.uuidString.lowercased()
        let notebooksRequest = NotebookEntity.fetchRequest()
        notebooksRequest.predicate = NSPredicate(format: "profileId == %@ AND deletedAt == nil", profileKey)
        notebooksRequest.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        let localNotebooks = try context.fetch(notebooksRequest)

        let notesRequest = NoteEntity.fetchRequest()
        notesRequest.predicate = NSPredicate(format: "profileId == %@ AND deletedAt == nil", profileKey)
        notesRequest.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        let localNotes = try context.fetch(notesRequest)
        let notesByNotebook = Dictionary(grouping: localNotes, by: \.notebookId)

        return localNotebooks.map { notebook in
            let color = NotebookColor(rawValue: notebook.colorRaw) ?? .lime
            let notes = (notesByNotebook[notebook.id] ?? []).map { $0.domainNote }
            return Notebook(
                id: UUID(uuidString: notebook.id) ?? UUID(),
                title: notebook.title,
                color: color,
                iconName: notebook.iconName,
                createdAt: notebook.createdAt,
                notes: notes,
                isPinned: notebook.isPinned,
                notebookDescription: notebook.notebookDescription
            )
        }
    }

    @discardableResult
    func createNotebook(profileId: UUID, title: String, color: NotebookColor, iconName: String) throws -> Notebook {
        let now = Date()
        let id = UUID()
        let entity = NotebookEntity(context: storage.mainContext)
        entity.id = id.uuidString.lowercased()
        entity.profileId = profileId.uuidString.lowercased()
        entity.title = title
        entity.colorRaw = color.rawValue
        entity.iconName = iconName
        entity.notebookDescription = ""
        entity.createdAt = now
        entity.updatedAt = now
        entity.deletedAt = nil
        entity.isPinned = false
        entity.localRevision = 1
        entity.lastSyncedHash = nil
        entity.deviceId = DeviceIdentity.getOrCreateDeviceId()
        try enqueue(.notebook, id: id, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
        return Notebook(id: id, title: title, color: color, iconName: iconName, createdAt: now, notes: [])
    }

    func updateNotebook(profileId: UUID, id: UUID, title: String?, color: NotebookColor?, description: String?, iconName: String? = nil) throws {
        guard let entity = try fetchNotebook(profileId: profileId, id: id) else { return }
        if let title { entity.title = title }
        if let color { entity.colorRaw = color.rawValue }
        if let description { entity.notebookDescription = description }
        if let iconName { entity.iconName = iconName }
        markChanged(entity)
        try enqueue(.notebook, id: id, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
    }

    func setNotebookPinned(profileId: UUID, id: UUID, isPinned: Bool) throws {
        guard let entity = try fetchNotebook(profileId: profileId, id: id) else { return }
        entity.isPinned = isPinned
        markChanged(entity)
        try enqueue(.notebook, id: id, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
    }

    func deleteNotebook(profileId: UUID, id: UUID) throws {
        guard let entity = try fetchNotebook(profileId: profileId, id: id) else { return }
        let now = Date()
        entity.deletedAt = now
        markChanged(entity, now: now)

        let notes = try fetchNotes(profileId: profileId, notebookId: id)
        for note in notes {
            note.deletedAt = now
            markChanged(note, now: now)
            try enqueue(.note, id: UUID(uuidString: note.id) ?? UUID(), profileId: profileId, operation: .delete)
            try upsertTombstone(profileId: profileId, entityType: .note, entityId: note.id, deletedAt: now)
        }
        try enqueue(.notebook, id: id, profileId: profileId, operation: .delete)
        try upsertTombstone(profileId: profileId, entityType: .notebook, entityId: id.uuidString.lowercased(), deletedAt: now)
        try storage.saveMainContext()
    }

    @discardableResult
    func createNote(profileId: UUID, notebookId: UUID, note: Note) throws -> Note {
        guard try fetchNotebook(profileId: profileId, id: notebookId) != nil else { return note }
        let entity = NoteEntity(context: storage.mainContext)
        apply(note: note, to: entity, profileId: profileId, notebookId: notebookId, version: 1)
        try enqueue(.note, id: note.id, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
        return note
    }

    func updateNote(profileId: UUID, notebookId: UUID? = nil, note: Note) throws {
        guard let entity = try fetchNote(profileId: profileId, id: note.id) else { return }
        let targetNotebookId = notebookId?.uuidString.lowercased() ?? entity.notebookId
        apply(note: note, to: entity, profileId: profileId, notebookIdString: targetNotebookId, version: entity.version)
        markChanged(entity, now: note.updatedAt)
        try enqueue(.note, id: note.id, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
    }

    func moveNote(profileId: UUID, noteId: UUID, targetNotebookId: UUID) throws {
        guard let entity = try fetchNote(profileId: profileId, id: noteId) else { return }
        entity.notebookId = targetNotebookId.uuidString.lowercased()
        markChanged(entity)
        try enqueue(.note, id: noteId, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
    }

    func setNotePinned(profileId: UUID, noteId: UUID, isPinned: Bool) throws {
        guard let entity = try fetchNote(profileId: profileId, id: noteId) else { return }
        entity.isPinned = isPinned
        markChanged(entity)
        try enqueue(.note, id: noteId, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
    }

    func deleteNote(profileId: UUID, noteId: UUID) throws {
        guard let entity = try fetchNote(profileId: profileId, id: noteId) else { return }
        let now = Date()
        entity.deletedAt = now
        markChanged(entity, now: now)
        try enqueue(.note, id: noteId, profileId: profileId, operation: .delete)
        try upsertTombstone(profileId: profileId, entityType: .note, entityId: noteId.uuidString.lowercased(), deletedAt: now)
        try storage.saveMainContext()
    }

    func applyRemoteNotebook(profileId: UUID, record: NotebookRemoteRecord) throws {
        let entity = try fetchNotebook(profileId: profileId, id: record.id) ?? NotebookEntity(context: storage.mainContext)
        entity.id = record.id.uuidString.lowercased()
        entity.profileId = profileId.uuidString.lowercased()
        entity.title = record.title
        entity.colorRaw = record.colorRaw
        entity.iconName = record.iconName
        entity.notebookDescription = record.notebookDescription
        entity.createdAt = record.createdAt
        entity.updatedAt = record.updatedAt
        entity.deletedAt = record.deletedAt
        entity.isPinned = record.isPinned
        entity.localRevision = max(entity.localRevision, record.localRevision)
        entity.lastSyncedHash = record.lastSyncedHash
        entity.deviceId = record.deviceId
    }

    func applyRemoteNote(profileId: UUID, record: NoteRemoteRecord) throws {
        if let existing = try fetchNote(profileId: profileId, id: record.id),
           existing.deviceId != record.deviceId,
           try hasPendingOutbox(profileId: profileId, type: .note, id: record.id) {
            let conflict = existing.domainNote.conflictCopy()
            _ = try createNote(profileId: profileId, notebookId: UUID(uuidString: existing.notebookId) ?? record.notebookId, note: conflict)
        }

        let entity = try fetchNote(profileId: profileId, id: record.id) ?? NoteEntity(context: storage.mainContext)
        entity.id = record.id.uuidString.lowercased()
        entity.profileId = profileId.uuidString.lowercased()
        entity.notebookId = record.notebookId.uuidString.lowercased()
        entity.title = record.title
        entity.summary = record.summary
        entity.paragraphCount = Int64(record.paragraphCount)
        entity.bulletCount = Int64(record.bulletCount)
        entity.hasAdditionalContext = record.hasAdditionalContext
        entity.createdAt = record.createdAt
        entity.updatedAt = record.updatedAt
        entity.deletedAt = record.deletedAt
        entity.version = Int64(max(record.version, 1))
        entity.contentRTF = record.contentRTF
        entity.content = record.content
        entity.isPinned = record.isPinned
        entity.conflictParentId = record.conflictParentId?.uuidString.lowercased()
        entity.localRevision = max(entity.localRevision, record.localRevision)
        entity.lastSyncedHash = record.lastSyncedHash
        entity.deviceId = record.deviceId
    }

    func applyRemoteHardDelete(profileId: UUID, entityType: SyncEntityType, id: UUID) throws {
        let now = Date()
        switch entityType {
        case .notebook:
            if let entity = try fetchNotebook(profileId: profileId, id: id) {
                entity.deletedAt = entity.deletedAt ?? now
                markChanged(entity, now: entity.deletedAt ?? now)
            }
            try upsertTombstone(profileId: profileId, entityType: .notebook, entityId: id.uuidString.lowercased(), deletedAt: now)
        case .note:
            if let entity = try fetchNote(profileId: profileId, id: id) {
                entity.deletedAt = entity.deletedAt ?? now
                markChanged(entity, now: entity.deletedAt ?? now)
            }
            try upsertTombstone(profileId: profileId, entityType: .note, entityId: id.uuidString.lowercased(), deletedAt: now)
        case .attachment:
            return
        }
    }

    func markOutboxDone(_ item: OutboxItem) throws {
        let request = SyncOutboxEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", item.id.uuidString.lowercased())
        request.fetchLimit = 1
        if let entity = try storage.mainContext.fetch(request).first {
            storage.mainContext.delete(entity)
        }
        try storage.saveMainContext()
    }

    func markOutboxFailed(_ item: OutboxItem, error: Error) throws {
        let request = SyncOutboxEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", item.id.uuidString.lowercased())
        request.fetchLimit = 1
        if let entity = try storage.mainContext.fetch(request).first {
            entity.status = OutboxStatus.failed.rawValue
            entity.retryCount += 1
            entity.updatedAt = Date()
            entity.lastError = error.localizedDescription
        }
        try storage.saveMainContext()
    }

    func pendingOutbox(profileId: UUID, limit: Int = 50) throws -> [OutboxItem] {
        let request = SyncOutboxEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "profileId == %@ AND status IN %@",
            profileId.uuidString.lowercased(),
            [OutboxStatus.pending.rawValue, OutboxStatus.failed.rawValue]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchLimit = limit
        return try storage.mainContext.fetch(request).compactMap { entity in
            guard let id = UUID(uuidString: entity.id),
                  let profile = UUID(uuidString: entity.profileId),
                  let entityType = SyncEntityType(rawValue: entity.entityType),
                  let entityId = UUID(uuidString: entity.entityId),
                  let operation = SyncOperation(rawValue: entity.operation) else { return nil }
            return OutboxItem(id: id, profileId: profile, entityType: entityType, entityId: entityId, operation: operation, retryCount: Int(entity.retryCount))
        }
    }

    private func hasPendingOutbox(profileId: UUID, type: SyncEntityType, id: UUID) throws -> Bool {
        let request = SyncOutboxEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "profileId == %@ AND entityType == %@ AND entityId == %@ AND status IN %@",
            profileId.uuidString.lowercased(),
            type.rawValue,
            id.uuidString.lowercased(),
            [OutboxStatus.pending.rawValue, OutboxStatus.failed.rawValue]
        )
        request.fetchLimit = 1
        return try storage.mainContext.count(for: request) > 0
    }

    func notebookEntity(profileId: UUID, id: UUID) throws -> NotebookEntity? {
        try fetchNotebook(profileId: profileId, id: id)
    }

    func noteEntity(profileId: UUID, id: UUID) throws -> NoteEntity? {
        try fetchNote(profileId: profileId, id: id)
    }

    private func fetchNotebook(profileId: UUID, id: UUID) throws -> NotebookEntity? {
        let request = NotebookEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND id == %@", profileId.uuidString.lowercased(), id.uuidString.lowercased())
        request.fetchLimit = 1
        return try storage.mainContext.fetch(request).first
    }

    private func fetchNote(profileId: UUID, id: UUID) throws -> NoteEntity? {
        let request = NoteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND id == %@", profileId.uuidString.lowercased(), id.uuidString.lowercased())
        request.fetchLimit = 1
        return try storage.mainContext.fetch(request).first
    }

    private func fetchNotes(profileId: UUID, notebookId: UUID) throws -> [NoteEntity] {
        let request = NoteEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND notebookId == %@", profileId.uuidString.lowercased(), notebookId.uuidString.lowercased())
        return try storage.mainContext.fetch(request)
    }

    private func apply(note: Note, to entity: NoteEntity, profileId: UUID, notebookId: UUID, version: Int64) {
        apply(note: note, to: entity, profileId: profileId, notebookIdString: notebookId.uuidString.lowercased(), version: version)
    }

    private func apply(note: Note, to entity: NoteEntity, profileId: UUID, notebookIdString: String, version: Int64) {
        entity.id = note.id.uuidString.lowercased()
        entity.profileId = profileId.uuidString.lowercased()
        entity.notebookId = notebookIdString
        entity.title = note.title
        entity.summary = note.summary
        entity.paragraphCount = Int64(note.paragraphCount)
        entity.bulletCount = Int64(note.bulletCount)
        entity.hasAdditionalContext = note.hasAdditionalContext
        entity.createdAt = note.createdAt
        entity.updatedAt = note.updatedAt
        entity.deletedAt = nil
        entity.version = max(version, 1)
        entity.contentRTF = note.contentRTF
        entity.content = note.content
        entity.isPinned = note.isPinned
        entity.localRevision = max(entity.localRevision, 0) + 1
        entity.deviceId = DeviceIdentity.getOrCreateDeviceId()
    }

    private func markChanged(_ entity: NotebookEntity, now: Date = Date()) {
        entity.updatedAt = now
        entity.localRevision += 1
        entity.deviceId = DeviceIdentity.getOrCreateDeviceId()
    }

    private func markChanged(_ entity: NoteEntity, now: Date = Date()) {
        entity.updatedAt = now
        entity.localRevision += 1
        entity.deviceId = DeviceIdentity.getOrCreateDeviceId()
    }

    private func enqueue(_ type: SyncEntityType, id: UUID, profileId: UUID, operation: SyncOperation) throws {
        let now = Date()
        let item = SyncOutboxEntity(context: storage.mainContext)
        item.id = UUID().uuidString.lowercased()
        item.profileId = profileId.uuidString.lowercased()
        item.entityType = type.rawValue
        item.entityId = id.uuidString.lowercased()
        item.operation = operation.rawValue
        item.payload = nil
        item.createdAt = now
        item.updatedAt = now
        item.retryCount = 0
        item.lastError = nil
        item.status = OutboxStatus.pending.rawValue
    }

    private func upsertTombstone(profileId: UUID, entityType: SyncEntityType, entityId: String, deletedAt: Date) throws {
        let request = TombstoneEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "profileId == %@ AND entityType == %@ AND entityId == %@",
            profileId.uuidString.lowercased(),
            entityType.rawValue,
            entityId
        )
        request.fetchLimit = 1
        let tombstone = try storage.mainContext.fetch(request).first ?? TombstoneEntity(context: storage.mainContext)
        tombstone.id = "\(profileId.uuidString.lowercased()):\(entityType.rawValue):\(entityId)"
        tombstone.profileId = profileId.uuidString.lowercased()
        tombstone.entityType = entityType.rawValue
        tombstone.entityId = entityId
        tombstone.deletedAt = deletedAt
        tombstone.expiresAt = Calendar.current.date(byAdding: .day, value: 90, to: deletedAt) ?? deletedAt.addingTimeInterval(90 * 86_400)
        tombstone.localRevision += 1
    }
}

@MainActor
final class AttachmentRepository {
    private let storage: StorageController

    init(storage: StorageController = .shared) {
        self.storage = storage
    }

    @discardableResult
    func saveAttachment(
        data: Data,
        attachmentId: UUID,
        profileId: UUID,
        noteId: UUID,
        fileName: String,
        mimeType: String
    ) throws -> AttachmentRecord {
        let originalURL = try AttachmentFileStore.saveOriginal(data: data, attachmentId: attachmentId, fileName: fileName)
        let storagePath = AttachmentPathFactory.storagePath(ownerId: profileId, attachmentId: attachmentId, fileName: fileName)
        let now = Date()
        let entity = try fetchAttachment(profileId: profileId, id: attachmentId) ?? AttachmentEntity(context: storage.mainContext)
        entity.id = attachmentId.uuidString.lowercased()
        entity.profileId = profileId.uuidString.lowercased()
        entity.noteId = noteId.uuidString.lowercased()
        entity.storagePath = storagePath
        entity.fileName = fileName
        entity.mimeType = mimeType
        entity.fileSize = Int64(data.count)
        entity.originalPath = originalURL.path
        entity.createdAt = entity.createdAtOr(now)
        entity.updatedAt = now
        entity.deletedAt = nil
        entity.missingLocalFile = false
        entity.isUploaded = false
        entity.localRevision += 1
        entity.lastSyncedHash = nil
        entity.deviceId = DeviceIdentity.getOrCreateDeviceId()

        try enqueueAttachment(id: attachmentId, profileId: profileId, operation: .upsert)
        try storage.saveMainContext()
        return entity.record
    }

    func pendingUploads(profileId: UUID, limit: Int = 20) throws -> [AttachmentRecord] {
        let request = AttachmentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND isUploaded == NO AND deletedAt == nil", profileId.uuidString.lowercased())
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchLimit = limit
        return try storage.mainContext.fetch(request).map(\.record)
    }

    func markUploaded(profileId: UUID, id: UUID, syncedHash: String?) throws {
        guard let entity = try fetchAttachment(profileId: profileId, id: id) else { return }
        entity.isUploaded = true
        entity.lastSyncedHash = syncedHash
        entity.updatedAt = Date()
        try storage.saveMainContext()
    }

    func find(profileId: UUID, id: UUID) throws -> AttachmentRecord? {
        try fetchAttachment(profileId: profileId, id: id)?.record
    }

    func applyRemote(profileId: UUID, record: AttachmentRemoteRecord) throws {
        let entity = try fetchAttachment(profileId: profileId, id: record.id) ?? AttachmentEntity(context: storage.mainContext)
        entity.id = record.id.uuidString.lowercased()
        entity.profileId = profileId.uuidString.lowercased()
        entity.noteId = record.noteId.uuidString.lowercased()
        entity.storagePath = record.storagePath
        entity.fileName = record.fileName
        entity.mimeType = record.mimeType
        entity.fileSize = record.fileSize
        entity.createdAt = record.createdAt
        entity.updatedAt = record.updatedAt
        entity.deletedAt = record.deletedAt
        entity.isUploaded = true
        entity.localRevision = max(entity.localRevision, record.localRevision)
        entity.lastSyncedHash = record.lastSyncedHash
        entity.deviceId = record.deviceId
    }

    func applyRemoteHardDelete(profileId: UUID, id: UUID) throws {
        guard let entity = try fetchAttachment(profileId: profileId, id: id) else { return }
        entity.deletedAt = entity.deletedAt ?? Date()
        entity.updatedAt = entity.deletedAt ?? Date()
        entity.isUploaded = true
    }

    private func fetchAttachment(profileId: UUID, id: UUID) throws -> AttachmentEntity? {
        let request = AttachmentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "profileId == %@ AND id == %@", profileId.uuidString.lowercased(), id.uuidString.lowercased())
        request.fetchLimit = 1
        return try storage.mainContext.fetch(request).first
    }

    private func enqueueAttachment(id: UUID, profileId: UUID, operation: SyncOperation) throws {
        let now = Date()
        let item = SyncOutboxEntity(context: storage.mainContext)
        item.id = UUID().uuidString.lowercased()
        item.profileId = profileId.uuidString.lowercased()
        item.entityType = SyncEntityType.attachment.rawValue
        item.entityId = id.uuidString.lowercased()
        item.operation = operation.rawValue
        item.createdAt = now
        item.updatedAt = now
        item.retryCount = 0
        item.status = OutboxStatus.pending.rawValue
    }
}

@MainActor
final class SyncStateRepository {
    private let storage: StorageController

    init(storage: StorageController = .shared) {
        self.storage = storage
    }

    func changeToken(profileId: UUID, iCloudAccountHash: String, zoneName: String) throws -> Data? {
        try fetch(profileId: profileId, iCloudAccountHash: iCloudAccountHash, zoneName: zoneName)?.changeTokenData
    }

    func setChangeToken(_ data: Data?, profileId: UUID, iCloudAccountHash: String, zoneName: String) throws {
        let entity = try fetch(profileId: profileId, iCloudAccountHash: iCloudAccountHash, zoneName: zoneName) ?? SyncStateEntity(context: storage.mainContext)
        entity.id = key(profileId: profileId, iCloudAccountHash: iCloudAccountHash, zoneName: zoneName)
        entity.profileId = profileId.uuidString.lowercased()
        entity.iCloudAccountHash = iCloudAccountHash
        entity.zoneName = zoneName
        entity.changeTokenData = data
        entity.updatedAt = Date()
        try storage.saveMainContext()
    }

    private func fetch(profileId: UUID, iCloudAccountHash: String, zoneName: String) throws -> SyncStateEntity? {
        let request = SyncStateEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", key(profileId: profileId, iCloudAccountHash: iCloudAccountHash, zoneName: zoneName))
        request.fetchLimit = 1
        return try storage.mainContext.fetch(request).first
    }

    private func key(profileId: UUID, iCloudAccountHash: String, zoneName: String) -> String {
        "\(profileId.uuidString.lowercased()):\(iCloudAccountHash):\(zoneName)"
    }
}

enum AttachmentFileStore {
    static func saveOriginal(data: Data, attachmentId: UUID, fileName: String) throws -> URL {
        let directory = StorageController.attachmentsOriginalsURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = originalURL(attachmentId: attachmentId, fileName: fileName)
        try data.write(to: url, options: [.atomic])
        AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName)
        return url
    }

    static func originalURL(attachmentId: UUID, fileName: String) -> URL {
        let ext = (fileName as NSString).pathExtension
        let name = ext.isEmpty ? attachmentId.uuidString.lowercased() : "\(attachmentId.uuidString.lowercased()).\(ext)"
        return StorageController.attachmentsOriginalsURL.appendingPathComponent(name)
    }

    static func loadOriginal(attachmentId: UUID, fileName: String, originalPath: String?) -> Data? {
        if let originalPath, let data = try? Data(contentsOf: URL(fileURLWithPath: originalPath)) {
            return data
        }
        return try? Data(contentsOf: originalURL(attachmentId: attachmentId, fileName: fileName))
    }
}

private extension NoteEntity {
    var domainNote: Note {
        Note(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            summary: summary,
            paragraphCount: Int(paragraphCount),
            bulletCount: Int(bulletCount),
            hasAdditionalContext: hasAdditionalContext,
            createdAt: createdAt,
            updatedAt: updatedAt,
            contentRTF: contentRTF,
            content: content,
            isPinned: isPinned
        )
    }
}

private extension AttachmentEntity {
    var record: AttachmentRecord {
        AttachmentRecord(
            id: UUID(uuidString: id) ?? UUID(),
            profileId: UUID(uuidString: profileId) ?? UUID(),
            noteId: UUID(uuidString: noteId) ?? UUID(),
            storagePath: storagePath,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: fileSize,
            originalPath: originalPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            missingLocalFile: missingLocalFile,
            isUploaded: isUploaded
        )
    }

    func createdAtOr(_ fallback: Date) -> Date {
        value(forKey: "createdAt") as? Date ?? fallback
    }
}

private extension Note {
    func conflictCopy() -> Note {
        Note(
            id: UUID(),
            title: title + "（冲突副本）",
            summary: summary,
            paragraphCount: paragraphCount,
            bulletCount: bulletCount,
            hasAdditionalContext: hasAdditionalContext,
            createdAt: Date(),
            updatedAt: Date(),
            contentRTF: contentRTF,
            content: content,
            isPinned: isPinned
        )
    }
}
