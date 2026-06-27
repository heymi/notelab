@preconcurrency import CloudKit
import Foundation

enum CloudKitSchema {
    static let containerIdentifier = "iCloud.com.psg.NoteLab"
    static let zoneName = "NoteLabPrivateZone"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    static var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    static var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    enum RecordType {
        static let notebook = "Notebook"
        static let note = "Note"
        static let attachment = "Attachment"
    }

    enum Field {
        static let id = "id"
        static let ownerId = "ownerId"
        static let profileIdHash = "profileIdHash"
        static let deviceId = "deviceId"
        static let localRevision = "localRevision"
        static let lastSyncedHash = "lastSyncedHash"
        static let notebookId = "notebookId"
        static let noteId = "noteId"
        static let title = "title"
        static let color = "color"
        static let iconName = "iconName"
        static let backgroundId = "backgroundId"
        static let notebookDescription = "notebookDescription"
        static let summary = "summary"
        static let content = "content"
        static let contentRTF = "contentRTF"
        static let conflictParentId = "conflictParentId"
        static let paragraphCount = "paragraphCount"
        static let bulletCount = "bulletCount"
        static let hasAdditionalContext = "hasAdditionalContext"
        static let isPinned = "isPinned"
        static let version = "version"
        static let fileName = "fileName"
        static let mimeType = "mimeType"
        static let fileSize = "fileSize"
        static let storagePath = "storagePath"
        static let asset = "asset"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let deletedAt = "deletedAt"
    }

    static func recordID(type: String, id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(type)-\(id.uuidString)", zoneID: zoneID)
    }

    static func recordID(type: String, profileId: UUID, id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(profileId.uuidString.lowercased()):\(type):\(id.uuidString.lowercased())", zoneID: zoneID)
    }

    static func storagePath(ownerId: UUID, attachmentId: UUID, fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        let storageName = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
        return "icloud/\(ownerId.uuidString)/\(storageName)"
    }

    static func attachmentId(from storagePath: String) -> UUID? {
        let parts = storagePath.split(separator: "/")
        guard let last = parts.last else { return nil }
        let stem = (String(last) as NSString).deletingPathExtension
        return UUID(uuidString: stem)
    }

    static func ownerId(from storagePath: String) -> UUID? {
        let parts = storagePath.split(separator: "/").map(String.init)
        if parts.count >= 3, parts[0] == "icloud" {
            return UUID(uuidString: parts[1])
        }
        if parts.count >= 2 {
            return UUID(uuidString: parts[0])
        }
        return nil
    }
}

enum CloudKitBridge {
    struct ZoneChanges {
        let changedRecords: [CKRecord]
        let deletedRecordIDs: [CKRecord.ID]
        let serverChangeToken: CKServerChangeToken?
    }

    static func ensurePrivateZone() async throws {
        let zone = CKRecordZone(zoneID: CloudKitSchema.zoneID)
        _ = try await save(zone: zone)
    }

    static func save(zone: CKRecordZone) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { continuation in
            CloudKitSchema.privateDatabase.save(zone) { savedZone, error in
                if let error = error as? CKError, error.code == .serverRecordChanged {
                    continuation.resume(returning: zone)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let savedZone {
                    continuation.resume(returning: savedZone)
                } else {
                    continuation.resume(throwing: NSError(domain: "CloudKitBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "CloudKit zone save returned no zone"]))
                }
            }
        }
    }

    static func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            CloudKitSchema.privateDatabase.fetch(withRecordID: recordID) { record, error in
                if let error = error as? CKError, error.code == .unknownItem {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: record)
                }
            }
        }
    }

    static func save(record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            CloudKitSchema.privateDatabase.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: NSError(domain: "CloudKitBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: "CloudKit record save returned no record"]))
                }
            }
        }
    }

    static func records(type: String, updatedAfter watermark: Date?) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate: NSPredicate
            if let watermark {
                predicate = NSPredicate(format: "%K > %@", CloudKitSchema.Field.updatedAt, watermark as NSDate)
            } else {
                predicate = NSPredicate(value: true)
            }
            let query = CKQuery(recordType: type, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: CloudKitSchema.Field.updatedAt, ascending: true)]
            var allRecords: [CKRecord] = []
            let lock = NSLock()

            func run(_ operation: CKQueryOperation) {
                operation.zoneID = CloudKitSchema.zoneID
                operation.recordFetchedBlock = { record in
                    lock.lock()
                    allRecords.append(record)
                    lock.unlock()
                }
                operation.queryCompletionBlock = { cursor, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let cursor {
                        run(CKQueryOperation(cursor: cursor))
                    } else {
                        lock.lock()
                        let records = allRecords
                        lock.unlock()
                        continuation.resume(returning: records)
                    }
                }
                CloudKitSchema.privateDatabase.add(operation)
            }

            run(CKQueryOperation(query: query))
        }
    }

    static func zoneChanges(since previousToken: CKServerChangeToken?) async throws -> ZoneChanges {
        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var latestToken = previousToken

        while true {
            let batch = try await zoneChangesBatch(since: latestToken)
            changedRecords.append(contentsOf: batch.changedRecords)
            deletedRecordIDs.append(contentsOf: batch.deletedRecordIDs)
            latestToken = batch.serverChangeToken

            if batch.moreComing == false {
                return ZoneChanges(
                    changedRecords: changedRecords,
                    deletedRecordIDs: deletedRecordIDs,
                    serverChangeToken: latestToken
                )
            }
        }
    }

    private struct ZoneChangesBatch {
        let changedRecords: [CKRecord]
        let deletedRecordIDs: [CKRecord.ID]
        let serverChangeToken: CKServerChangeToken?
        let moreComing: Bool
    }

    private static func zoneChangesBatch(since previousToken: CKServerChangeToken?) async throws -> ZoneChangesBatch {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = previousToken

            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [CloudKitSchema.zoneID],
                configurationsByRecordZoneID: [CloudKitSchema.zoneID: configuration]
            )
            operation.fetchAllChanges = true

            var changedRecords: [CKRecord] = []
            var deletedRecordIDs: [CKRecord.ID] = []
            let lock = NSLock()

            operation.recordChangedBlock = { record in
                lock.lock()
                changedRecords.append(record)
                lock.unlock()
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                lock.lock()
                deletedRecordIDs.append(recordID)
                lock.unlock()
            }
            operation.recordZoneFetchCompletionBlock = { _, token, _, moreComing, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                lock.lock()
                let records = changedRecords
                let deleted = deletedRecordIDs
                lock.unlock()
                continuation.resume(returning: ZoneChangesBatch(
                    changedRecords: records,
                    deletedRecordIDs: deleted,
                    serverChangeToken: token,
                    moreComing: moreComing
                ))
            }

            CloudKitSchema.privateDatabase.add(operation)
        }
    }
}

extension CKRecord {
    subscript(string key: String) -> String? {
        get { self[key] as? String }
        set { self[key] = newValue as CKRecordValue? }
    }

    subscript(date key: String) -> Date? {
        get { self[key] as? Date }
        set { self[key] = newValue as CKRecordValue? }
    }

    subscript(bool key: String) -> Bool {
        get { (self[key] as? NSNumber)?.boolValue ?? false }
        set { self[key] = NSNumber(value: newValue) }
    }

    subscript(int key: String) -> Int {
        get { (self[key] as? NSNumber)?.intValue ?? 0 }
        set { self[key] = NSNumber(value: newValue) }
    }

    subscript(int64 key: String) -> Int64 {
        get { (self[key] as? NSNumber)?.int64Value ?? 0 }
        set { self[key] = NSNumber(value: newValue) }
    }

    subscript(data key: String) -> Data? {
        get { self[key] as? Data }
        set { self[key] = newValue as CKRecordValue? }
    }

    subscript(asset key: String) -> CKAsset? {
        get { self[key] as? CKAsset }
        set { self[key] = newValue }
    }
}
