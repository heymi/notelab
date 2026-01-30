import Foundation
import SwiftData

@Model
final class LocalNotebook {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID
    var title: String
    var colorRaw: String
    var iconName: String
    var createdAt: Date
    var remoteUpdatedAt: Date
    var deletedAt: Date?
    var isDirty: Bool
    var isPinned: Bool
    /// 笔记本背景介绍，用于AI分析时提供上下文
    var notebookDescription: String

    @Relationship(deleteRule: .cascade, inverse: \LocalNote.notebook)
    var notes: [LocalNote]

    init(
        id: UUID,
        ownerId: UUID,
        title: String,
        colorRaw: String,
        iconName: String,
        createdAt: Date,
        remoteUpdatedAt: Date,
        deletedAt: Date? = nil,
        isDirty: Bool = true,
        isPinned: Bool = false,
        notebookDescription: String = "",
        notes: [LocalNote] = []
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.colorRaw = colorRaw
        self.iconName = iconName
        self.createdAt = createdAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.deletedAt = deletedAt
        self.isDirty = isDirty
        self.isPinned = isPinned
        self.notebookDescription = notebookDescription
        self.notes = notes
    }
}

@Model
final class LocalNote {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID

    var title: String
    var summary: String
    var paragraphCount: Int
    var bulletCount: Int
    var hasAdditionalContext: Bool

    var createdAt: Date
    var remoteUpdatedAt: Date
    var version: Int
    var deletedAt: Date?

    var contentRTF: Data?
    var content: String
    var isPinned: Bool

    var isDirty: Bool
    var conflictParentId: UUID?

    var notebook: LocalNotebook?

    init(
        id: UUID,
        ownerId: UUID,
        title: String,
        summary: String,
        paragraphCount: Int,
        bulletCount: Int,
        hasAdditionalContext: Bool,
        createdAt: Date,
        remoteUpdatedAt: Date,
        version: Int = 1,
        deletedAt: Date? = nil,
        contentRTF: Data? = nil,
        content: String,
        isPinned: Bool = false,
        isDirty: Bool = true,
        conflictParentId: UUID? = nil,
        notebook: LocalNotebook? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.summary = summary
        self.paragraphCount = paragraphCount
        self.bulletCount = bulletCount
        self.hasAdditionalContext = hasAdditionalContext
        self.createdAt = createdAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.version = version
        self.deletedAt = deletedAt
        self.contentRTF = contentRTF
        self.content = content
        self.isPinned = isPinned
        self.isDirty = isDirty
        self.conflictParentId = conflictParentId
        self.notebook = notebook
    }
}

@Model
final class SyncMetadata {
    /// Unique key: "\(ownerId.uuidString):\(entity)"
    @Attribute(.unique) var key: String
    var ownerId: UUID
    /// e.g. "notebooks" or "notes"
    @Attribute(originalName: "entity") var entityName: String
    /// last successfully pulled `updated_at` watermark (server time)
    var lastPulledAt: Date?

    init(ownerId: UUID, entity: String, lastPulledAt: Date? = nil) {
        self.ownerId = ownerId
        self.entityName = entity
        self.lastPulledAt = lastPulledAt
        self.key = "\(ownerId.uuidString):\(entity)"
    }
}

// MARK: - Local Attachment

@Model
final class LocalAttachment {
    @Attribute(.unique) var id: UUID
    var ownerId: UUID
    var noteId: UUID
    
    /// Storage path in Supabase Storage, e.g. "{user_id}/{attachment_id}.jpg"
    var storagePath: String
    var fileName: String
    var mimeType: String
    var fileSize: Int64
    
    var createdAt: Date
    var remoteUpdatedAt: Date
    var deletedAt: Date?
    
    /// Whether local file cache exists
    var localCachePath: String?
    
    /// Sync status
    var isDirty: Bool
    var isUploaded: Bool
    
    init(
        id: UUID,
        ownerId: UUID,
        noteId: UUID,
        storagePath: String,
        fileName: String,
        mimeType: String,
        fileSize: Int64,
        createdAt: Date,
        remoteUpdatedAt: Date,
        deletedAt: Date? = nil,
        localCachePath: String? = nil,
        isDirty: Bool = true,
        isUploaded: Bool = false
    ) {
        self.id = id
        self.ownerId = ownerId
        self.noteId = noteId
        self.storagePath = storagePath
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.deletedAt = deletedAt
        self.localCachePath = localCachePath
        self.isDirty = isDirty
        self.isUploaded = isUploaded
    }
}

