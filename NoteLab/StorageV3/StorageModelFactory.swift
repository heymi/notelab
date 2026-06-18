import CoreData
import Foundation

enum StorageModelFactory {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            userProfile(),
            notebook(),
            note(),
            attachment(),
            outbox(),
            syncState(),
            tombstone()
        ]
        return model
    }

    private static func userProfile() -> NSEntityDescription {
        entity(UserProfileEntity.self, properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("appleUserHash", .stringAttributeType, optional: false),
            attr("displayEmail", .stringAttributeType),
            attr("displayName", .stringAttributeType),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("updatedAt", .dateAttributeType, optional: false),
            attr("isLocked", .booleanAttributeType, optional: false, defaultValue: false)
        ], uniqueness: [["id"]])
    }

    private static func notebook() -> NSEntityDescription {
        entity(NotebookEntity.self, properties: commonScopedProperties() + [
            attr("title", .stringAttributeType, optional: false),
            attr("colorRaw", .stringAttributeType, optional: false),
            attr("iconName", .stringAttributeType, optional: false),
            attr("notebookDescription", .stringAttributeType, optional: false, defaultValue: ""),
            attr("isPinned", .booleanAttributeType, optional: false, defaultValue: false)
        ], uniqueness: [["profileId", "id"]])
    }

    private static func note() -> NSEntityDescription {
        entity(NoteEntity.self, properties: commonScopedProperties() + [
            attr("notebookId", .stringAttributeType, optional: false, indexed: true),
            attr("title", .stringAttributeType, optional: false),
            attr("summary", .stringAttributeType, optional: false, defaultValue: ""),
            attr("paragraphCount", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("bulletCount", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("hasAdditionalContext", .booleanAttributeType, optional: false, defaultValue: false),
            attr("version", .integer64AttributeType, optional: false, defaultValue: 1),
            attr("contentRTF", .binaryDataAttributeType),
            attr("content", .stringAttributeType, optional: false, defaultValue: ""),
            attr("isPinned", .booleanAttributeType, optional: false, defaultValue: false),
            attr("conflictParentId", .stringAttributeType)
        ], uniqueness: [["profileId", "id"]])
    }

    private static func attachment() -> NSEntityDescription {
        entity(AttachmentEntity.self, properties: commonScopedProperties() + [
            attr("noteId", .stringAttributeType, optional: false, indexed: true),
            attr("storagePath", .stringAttributeType, optional: false),
            attr("fileName", .stringAttributeType, optional: false),
            attr("mimeType", .stringAttributeType, optional: false),
            attr("fileSize", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("originalPath", .stringAttributeType),
            attr("missingLocalFile", .booleanAttributeType, optional: false, defaultValue: false),
            attr("isUploaded", .booleanAttributeType, optional: false, defaultValue: false)
        ], uniqueness: [["profileId", "id"]])
    }

    private static func outbox() -> NSEntityDescription {
        entity(SyncOutboxEntity.self, properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("entityType", .stringAttributeType, optional: false, indexed: true),
            attr("entityId", .stringAttributeType, optional: false, indexed: true),
            attr("operation", .stringAttributeType, optional: false),
            attr("payload", .binaryDataAttributeType),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("updatedAt", .dateAttributeType, optional: false),
            attr("retryCount", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("lastError", .stringAttributeType),
            attr("status", .stringAttributeType, optional: false, indexed: true)
        ], uniqueness: [["id"]])
    }

    private static func syncState() -> NSEntityDescription {
        entity(SyncStateEntity.self, properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("iCloudAccountHash", .stringAttributeType, optional: false),
            attr("zoneName", .stringAttributeType, optional: false),
            attr("changeTokenData", .binaryDataAttributeType),
            attr("updatedAt", .dateAttributeType, optional: false)
        ], uniqueness: [["id"]])
    }

    private static func tombstone() -> NSEntityDescription {
        entity(TombstoneEntity.self, properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("entityType", .stringAttributeType, optional: false, indexed: true),
            attr("entityId", .stringAttributeType, optional: false, indexed: true),
            attr("deletedAt", .dateAttributeType, optional: false),
            attr("expiresAt", .dateAttributeType, optional: false),
            attr("localRevision", .integer64AttributeType, optional: false, defaultValue: 1)
        ], uniqueness: [["profileId", "entityType", "entityId"]])
    }

    private static func commonScopedProperties() -> [NSPropertyDescription] {
        [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("updatedAt", .dateAttributeType, optional: false, indexed: true),
            attr("deletedAt", .dateAttributeType),
            attr("localRevision", .integer64AttributeType, optional: false, defaultValue: 1),
            attr("lastSyncedHash", .stringAttributeType),
            attr("deviceId", .stringAttributeType, optional: false)
        ]
    }

    private static func entity<T: NSManagedObject>(
        _ type: T.Type,
        properties: [NSPropertyDescription],
        uniqueness: [[String]]
    ) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = String(describing: type)
        entity.managedObjectClassName = NSStringFromClass(type)
        entity.properties = properties
        entity.uniquenessConstraints = uniqueness
        return entity
    }

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = true,
        indexed: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        attr.isIndexed = indexed
        attr.defaultValue = defaultValue
        return attr
    }
}
