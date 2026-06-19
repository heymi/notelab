import CoreData
import Foundation

@objc(UserProfileEntity)
final class UserProfileEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var appleUserHash: String
    @NSManaged var displayEmail: String?
    @NSManaged var displayName: String?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var isLocked: Bool
}

@objc(NotebookEntity)
final class NotebookEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var profileId: String
    @NSManaged var title: String
    @NSManaged var colorRaw: String
    @NSManaged var iconName: String
    @NSManaged var notebookDescription: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var deletedAt: Date?
    @NSManaged var isPinned: Bool
    @NSManaged var localRevision: Int64
    @NSManaged var lastSyncedHash: String?
    @NSManaged var deviceId: String
}

@objc(NoteEntity)
final class NoteEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var profileId: String
    @NSManaged var notebookId: String
    @NSManaged var title: String
    @NSManaged var summary: String
    @NSManaged var paragraphCount: Int64
    @NSManaged var bulletCount: Int64
    @NSManaged var hasAdditionalContext: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var deletedAt: Date?
    @NSManaged var version: Int64
    @NSManaged var contentRTF: Data?
    @NSManaged var content: String
    @NSManaged var isPinned: Bool
    @NSManaged var conflictParentId: String?
    @NSManaged var localRevision: Int64
    @NSManaged var lastSyncedHash: String?
    @NSManaged var deviceId: String
}

@objc(AttachmentEntity)
final class AttachmentEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var profileId: String
    @NSManaged var noteId: String
    @NSManaged var storagePath: String
    @NSManaged var fileName: String
    @NSManaged var mimeType: String
    @NSManaged var fileSize: Int64
    @NSManaged var originalPath: String?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var deletedAt: Date?
    @NSManaged var missingLocalFile: Bool
    @NSManaged var isUploaded: Bool
    @NSManaged var localRevision: Int64
    @NSManaged var lastSyncedHash: String?
    @NSManaged var deviceId: String
}

@objc(VoiceNoteEntity)
final class VoiceNoteEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var profileId: String
    @NSManaged var noteId: String
    @NSManaged var notebookId: String
    @NSManaged var audioAttachmentId: String
    @NSManaged var audioStoragePath: String
    @NSManaged var audioFileName: String
    @NSManaged var duration: Double
    @NSManaged var statusRaw: String
    @NSManaged var rawTranscript: String
    @NSManaged var errorMessage: String?
    @NSManaged var retryCount: Int64
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

@objc(SyncOutboxEntity)
final class SyncOutboxEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var profileId: String
    @NSManaged var entityType: String
    @NSManaged var entityId: String
    @NSManaged var operation: String
    @NSManaged var payload: Data?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var retryCount: Int64
    @NSManaged var lastError: String?
    @NSManaged var status: String
}

@objc(SyncStateEntity)
final class SyncStateEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var profileId: String
    @NSManaged var iCloudAccountHash: String
    @NSManaged var zoneName: String
    @NSManaged var changeTokenData: Data?
    @NSManaged var updatedAt: Date
}

@objc(TombstoneEntity)
final class TombstoneEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var profileId: String
    @NSManaged var entityType: String
    @NSManaged var entityId: String
    @NSManaged var deletedAt: Date
    @NSManaged var expiresAt: Date
    @NSManaged var localRevision: Int64
}

extension UserProfileEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<UserProfileEntity> {
        NSFetchRequest<UserProfileEntity>(entityName: "UserProfileEntity")
    }
}

extension NotebookEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<NotebookEntity> {
        NSFetchRequest<NotebookEntity>(entityName: "NotebookEntity")
    }
}

extension NoteEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<NoteEntity> {
        NSFetchRequest<NoteEntity>(entityName: "NoteEntity")
    }
}

extension AttachmentEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AttachmentEntity> {
        NSFetchRequest<AttachmentEntity>(entityName: "AttachmentEntity")
    }
}

extension VoiceNoteEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<VoiceNoteEntity> {
        NSFetchRequest<VoiceNoteEntity>(entityName: "VoiceNoteEntity")
    }
}

extension SyncOutboxEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SyncOutboxEntity> {
        NSFetchRequest<SyncOutboxEntity>(entityName: "SyncOutboxEntity")
    }
}

extension SyncStateEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SyncStateEntity> {
        NSFetchRequest<SyncStateEntity>(entityName: "SyncStateEntity")
    }
}

extension TombstoneEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TombstoneEntity> {
        NSFetchRequest<TombstoneEntity>(entityName: "TombstoneEntity")
    }
}
