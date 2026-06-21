@preconcurrency import CloudKit
import CryptoKit
import Foundation

struct NotebookRemoteRecord {
    let id: UUID
    let profileIdHash: String
    let title: String
    let colorRaw: String
    let iconName: String
    let notebookDescription: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let isPinned: Bool
    let localRevision: Int64
    let lastSyncedHash: String?
    let deviceId: String
}

struct NoteRemoteRecord {
    let id: UUID
    let profileIdHash: String
    let notebookId: UUID
    let title: String
    let summary: String
    let paragraphCount: Int
    let bulletCount: Int
    let hasAdditionalContext: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let version: Int
    let contentRTF: Data?
    let content: String
    let isPinned: Bool
    let conflictParentId: UUID?
    let localRevision: Int64
    let lastSyncedHash: String?
    let deviceId: String
}

struct AttachmentRemoteRecord {
    let id: UUID
    let profileIdHash: String
    let noteId: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let localRevision: Int64
    let lastSyncedHash: String?
    let deviceId: String
}

struct CloudKitDeletedRecord {
    let entityType: SyncEntityType
    let profileId: UUID
    let id: UUID
}

struct CloudKitChangeBatch {
    let notebooks: [NotebookRemoteRecord]
    let notes: [NoteRemoteRecord]
    let attachments: [AttachmentRemoteRecord]
    let deletedRecordIDs: [CKRecord.ID]
    let deletedRecords: [CloudKitDeletedRecord]
    let serverChangeToken: CKServerChangeToken?
}

@MainActor
protocol CloudKitTransporting: AnyObject {
    func iCloudAccountHash() async throws -> String
    func ensureInfrastructure() async throws
    func pushNotebook(_ entity: NotebookEntity, profileId: UUID) async throws -> String
    func pushNote(_ entity: NoteEntity, profileId: UUID) async throws -> String
    func pushAttachment(_ entity: AttachmentEntity, profileId: UUID) async throws -> String
    func fetchChanges(since token: CKServerChangeToken?) async throws -> CloudKitChangeBatch
    func cloudRecordCount(profileId: UUID) async throws -> Int
}

final class CloudKitTransport: CloudKitTransporting {
    private let database: CKDatabase

    init(container: CKContainer = CloudKitSchema.container) {
        database = container.privateCloudDatabase
    }

    func iCloudAccountHash() async throws -> String {
        let id = try await CloudKitSchema.container.userRecordID()
        return Self.hash(id.recordName)
    }

    func ensureInfrastructure() async throws {
        let zone = CKRecordZone(zoneID: CloudKitSchema.zoneID)
        _ = try await save(zone: zone)
        try await ensureSubscription()
    }

    func pushNotebook(_ entity: NotebookEntity, profileId: UUID) async throws -> String {
        let recordID = recordID(type: CloudKitSchema.RecordType.notebook, profileId: profileId, id: entity.id)
        let record = try await fetch(recordID) ?? CKRecord(recordType: CloudKitSchema.RecordType.notebook, recordID: recordID)
        record[string: CloudKitSchema.Field.id] = entity.id
        record[string: CloudKitSchema.Field.ownerId] = profileId.uuidString
        record[string: CloudKitSchema.Field.profileIdHash] = Self.hash(profileId.uuidString.lowercased())
        record[string: CloudKitSchema.Field.deviceId] = entity.deviceId
        record[int64: CloudKitSchema.Field.localRevision] = entity.localRevision
        record[string: CloudKitSchema.Field.title] = entity.title
        record[string: CloudKitSchema.Field.color] = entity.colorRaw
        record[string: CloudKitSchema.Field.iconName] = entity.iconName
        record[string: CloudKitSchema.Field.notebookDescription] = entity.notebookDescription
        record[bool: CloudKitSchema.Field.isPinned] = entity.isPinned
        record[date: CloudKitSchema.Field.createdAt] = entity.createdAt
        record[date: CloudKitSchema.Field.updatedAt] = entity.updatedAt
        record[date: CloudKitSchema.Field.deletedAt] = entity.deletedAt
        record[string: CloudKitSchema.Field.lastSyncedHash] = Self.recordHash(record)
        let saved = try await save(record: record)
        return Self.recordHash(saved)
    }

    func pushNote(_ entity: NoteEntity, profileId: UUID) async throws -> String {
        let recordID = recordID(type: CloudKitSchema.RecordType.note, profileId: profileId, id: entity.id)
        let record = try await fetch(recordID) ?? CKRecord(recordType: CloudKitSchema.RecordType.note, recordID: recordID)
        record[string: CloudKitSchema.Field.id] = entity.id
        record[string: CloudKitSchema.Field.ownerId] = profileId.uuidString
        record[string: CloudKitSchema.Field.profileIdHash] = Self.hash(profileId.uuidString.lowercased())
        record[string: CloudKitSchema.Field.deviceId] = entity.deviceId
        record[int64: CloudKitSchema.Field.localRevision] = entity.localRevision
        record[string: CloudKitSchema.Field.notebookId] = entity.notebookId
        record[string: CloudKitSchema.Field.title] = entity.title
        record[string: CloudKitSchema.Field.summary] = entity.summary
        record[string: CloudKitSchema.Field.content] = entity.content
        record[data: CloudKitSchema.Field.contentRTF] = entity.contentRTF
        record[int: CloudKitSchema.Field.paragraphCount] = Int(entity.paragraphCount)
        record[int: CloudKitSchema.Field.bulletCount] = Int(entity.bulletCount)
        record[bool: CloudKitSchema.Field.hasAdditionalContext] = entity.hasAdditionalContext
        record[bool: CloudKitSchema.Field.isPinned] = entity.isPinned
        record[int: CloudKitSchema.Field.version] = Int(max(entity.version, 1))
        record[date: CloudKitSchema.Field.createdAt] = entity.createdAt
        record[date: CloudKitSchema.Field.updatedAt] = entity.updatedAt
        record[date: CloudKitSchema.Field.deletedAt] = entity.deletedAt
        if let conflictParentId = entity.conflictParentId {
            record[CloudKitSchema.Field.conflictParentId] = conflictParentId as CKRecordValue
        } else {
            record[CloudKitSchema.Field.conflictParentId] = nil
        }
        record[string: CloudKitSchema.Field.lastSyncedHash] = Self.recordHash(record)
        let saved = try await save(record: record)
        return Self.recordHash(saved)
    }

    func pushAttachment(_ entity: AttachmentEntity, profileId: UUID) async throws -> String {
        let recordID = recordID(type: CloudKitSchema.RecordType.attachment, profileId: profileId, id: entity.id)
        let record = try await fetch(recordID) ?? CKRecord(recordType: CloudKitSchema.RecordType.attachment, recordID: recordID)
        record[string: CloudKitSchema.Field.id] = entity.id
        record[string: CloudKitSchema.Field.ownerId] = profileId.uuidString
        record[string: CloudKitSchema.Field.profileIdHash] = Self.hash(profileId.uuidString.lowercased())
        record[string: CloudKitSchema.Field.deviceId] = entity.deviceId
        record[int64: CloudKitSchema.Field.localRevision] = entity.localRevision
        record[string: CloudKitSchema.Field.noteId] = entity.noteId
        record[string: CloudKitSchema.Field.storagePath] = entity.storagePath
        record[string: CloudKitSchema.Field.fileName] = entity.fileName
        record[string: CloudKitSchema.Field.mimeType] = entity.mimeType
        record[int64: CloudKitSchema.Field.fileSize] = entity.fileSize
        record[date: CloudKitSchema.Field.createdAt] = entity.createdAt
        record[date: CloudKitSchema.Field.updatedAt] = entity.updatedAt
        record[date: CloudKitSchema.Field.deletedAt] = entity.deletedAt
        if entity.deletedAt == nil {
            guard let data = AttachmentFileStore.loadOriginal(
                attachmentId: UUID(uuidString: entity.id) ?? UUID(),
                fileName: entity.fileName,
                originalPath: entity.originalPath
            ) else {
                throw NSError(domain: "CloudKitTransport", code: 11, userInfo: [NSLocalizedDescriptionKey: "附件本地原件缺失，无法上传"])
            }
            let assetURL = try AttachmentFileStore.saveOriginal(data: data, attachmentId: UUID(uuidString: entity.id) ?? UUID(), fileName: entity.fileName)
            record[asset: CloudKitSchema.Field.asset] = CKAsset(fileURL: assetURL)
        }
        record[string: CloudKitSchema.Field.lastSyncedHash] = Self.recordHash(record)
        let saved = try await save(record: record)
        return Self.recordHash(saved)
    }

    func fetchChanges(since token: CKServerChangeToken?) async throws -> CloudKitChangeBatch {
        var changedRecords: [CKRecord] = []
        var deleted: [CKRecord.ID] = []
        var latest = token

        while true {
            let batch = try await fetchZoneChangesBatch(since: latest)
            changedRecords.append(contentsOf: batch.records)
            deleted.append(contentsOf: batch.deleted)
            latest = batch.token
            if !batch.moreComing { break }
        }

        return CloudKitChangeBatch(
            notebooks: changedRecords.compactMap(Self.notebookRecord(from:)),
            notes: changedRecords.compactMap(Self.noteRecord(from:)),
            attachments: changedRecords.compactMap(Self.attachmentRecord(from:)),
            deletedRecordIDs: deleted,
            deletedRecords: deleted.compactMap(Self.deletedRecord(from:)),
            serverChangeToken: latest
        )
    }

    func cloudRecordCount(profileId: UUID) async throws -> Int {
        let profileHash = Self.hash(profileId.uuidString.lowercased())
        let records = try await fetchRecords(type: CloudKitSchema.RecordType.notebook)
            + (try await fetchRecords(type: CloudKitSchema.RecordType.note))
            + (try await fetchRecords(type: CloudKitSchema.RecordType.attachment))
        return records.filter {
            $0[string: CloudKitSchema.Field.profileIdHash] == profileHash
                && $0[date: CloudKitSchema.Field.deletedAt] == nil
        }.count
    }

    static func encodeToken(_ token: CKServerChangeToken?) -> Data? {
        guard let token else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func decodeToken(_ data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func save(zone: CKRecordZone) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecordZone, Error>) in
            database.save(zone) { savedZone, error in
                if let error = error as? CKError, error.code == .serverRecordChanged {
                    continuation.resume(returning: zone)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: savedZone ?? zone)
                }
            }
        }
    }

    private func ensureSubscription() async throws {
        let subscriptionID = "notelab-private-zone-subscription"
        let existing = try? await fetchSubscription(subscriptionID)
        if existing != nil { return }

        let subscription = CKRecordZoneSubscription(zoneID: CloudKitSchema.zoneID, subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await save(subscription: subscription)
    }

    private func fetchSubscription(_ id: String) async throws -> CKSubscription? {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withSubscriptionID: id) { subscription, error in
                if let error = error as? CKError, error.code == .unknownItem {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: subscription)
                }
            }
        }
    }

    private func save(subscription: CKSubscription) async throws -> CKSubscription {
        try await withCheckedThrowingContinuation { continuation in
            database.save(subscription) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: saved ?? subscription)
                }
            }
        }
    }

    private func fetch(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
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

    private func fetchRecords(type: String) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
            var records: [CKRecord] = []
            let lock = NSLock()

            func run(_ operation: CKQueryOperation) {
                operation.zoneID = CloudKitSchema.zoneID
                operation.recordFetchedBlock = { record in
                    lock.lock()
                    records.append(record)
                    lock.unlock()
                }
                operation.queryCompletionBlock = { cursor, error in
                    if let error = error as? CKError, error.code == .unknownItem {
                        lock.lock()
                        let fetched = records
                        lock.unlock()
                        continuation.resume(returning: fetched)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else if let cursor {
                        run(CKQueryOperation(cursor: cursor))
                    } else {
                        lock.lock()
                        let fetched = records
                        lock.unlock()
                        continuation.resume(returning: fetched)
                    }
                }
                database.add(operation)
            }

            run(CKQueryOperation(query: query))
        }
    }

    private func save(record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let saved {
                    continuation.resume(returning: saved)
                } else {
                    continuation.resume(throwing: NSError(domain: "CloudKitTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "CloudKit did not return a saved record"]))
                }
            }
        }
    }

    private struct ZoneBatch {
        let records: [CKRecord]
        let deleted: [CKRecord.ID]
        let token: CKServerChangeToken?
        let moreComing: Bool
    }

    private func fetchZoneChangesBatch(since token: CKServerChangeToken?) async throws -> ZoneBatch {
        try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = token
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [CloudKitSchema.zoneID],
                configurationsByRecordZoneID: [CloudKitSchema.zoneID: config]
            )
            operation.fetchAllChanges = true

            var records: [CKRecord] = []
            var deleted: [CKRecord.ID] = []
            let lock = NSLock()

            operation.recordChangedBlock = { record in
                lock.lock()
                records.append(record)
                lock.unlock()
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                lock.lock()
                deleted.append(recordID)
                lock.unlock()
            }
            operation.recordZoneFetchCompletionBlock = { _, nextToken, _, moreComing, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                lock.lock()
                let currentRecords = records
                let currentDeleted = deleted
                lock.unlock()
                continuation.resume(returning: ZoneBatch(records: currentRecords, deleted: currentDeleted, token: nextToken, moreComing: moreComing))
            }
            database.add(operation)
        }
    }

    private func recordID(type: String, profileId: UUID, id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(profileId.uuidString.lowercased()):\(type):\(id.lowercased())", zoneID: CloudKitSchema.zoneID)
    }

    static func deletedRecord(from recordID: CKRecord.ID) -> CloudKitDeletedRecord? {
        let parts = recordID.recordName.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let profileId = UUID(uuidString: parts[0]),
              let entityType = SyncEntityType(rawValue: parts[1]),
              let id = UUID(uuidString: parts[2]) else {
            return nil
        }
        return CloudKitDeletedRecord(entityType: entityType, profileId: profileId, id: id)
    }

    private static func notebookRecord(from record: CKRecord) -> NotebookRemoteRecord? {
        guard record.recordType == CloudKitSchema.RecordType.notebook,
              let id = UUID(uuidString: record[string: CloudKitSchema.Field.id] ?? "") else { return nil }
        let createdAt = record[date: CloudKitSchema.Field.createdAt] ?? Date()
        return NotebookRemoteRecord(
            id: id,
            profileIdHash: record[string: CloudKitSchema.Field.profileIdHash] ?? "",
            title: record[string: CloudKitSchema.Field.title] ?? "未命名笔记本",
            colorRaw: record[string: CloudKitSchema.Field.color] ?? NotebookColor.lime.rawValue,
            iconName: record[string: CloudKitSchema.Field.iconName] ?? "book",
            notebookDescription: record[string: CloudKitSchema.Field.notebookDescription] ?? "",
            createdAt: createdAt,
            updatedAt: record[date: CloudKitSchema.Field.updatedAt] ?? createdAt,
            deletedAt: record[date: CloudKitSchema.Field.deletedAt],
            isPinned: record[bool: CloudKitSchema.Field.isPinned],
            localRevision: record[int64: CloudKitSchema.Field.localRevision],
            lastSyncedHash: record[string: CloudKitSchema.Field.lastSyncedHash],
            deviceId: record[string: CloudKitSchema.Field.deviceId] ?? ""
        )
    }

    private static func noteRecord(from record: CKRecord) -> NoteRemoteRecord? {
        guard record.recordType == CloudKitSchema.RecordType.note,
              let id = UUID(uuidString: record[string: CloudKitSchema.Field.id] ?? ""),
              let notebookId = UUID(uuidString: record[string: CloudKitSchema.Field.notebookId] ?? "") else { return nil }
        let createdAt = record[date: CloudKitSchema.Field.createdAt] ?? Date()
        let profileIdHash = record[string: CloudKitSchema.Field.profileIdHash] ?? ""
        let title = record[string: CloudKitSchema.Field.title] ?? "未命名笔记"
        let summary = record[string: CloudKitSchema.Field.summary] ?? ""
        let updatedAt = record[date: CloudKitSchema.Field.updatedAt] ?? createdAt
        let deletedAt = record[date: CloudKitSchema.Field.deletedAt]
        let contentRTF = record[data: CloudKitSchema.Field.contentRTF]
        let content = record[string: CloudKitSchema.Field.content] ?? ""
        let conflictParentId = UUID(uuidString: record[string: CloudKitSchema.Field.conflictParentId] ?? "")
        let lastSyncedHash = record[string: CloudKitSchema.Field.lastSyncedHash]
        let deviceId = record[string: CloudKitSchema.Field.deviceId] ?? ""
        return NoteRemoteRecord(
            id: id,
            profileIdHash: profileIdHash,
            notebookId: notebookId,
            title: title,
            summary: summary,
            paragraphCount: record[int: CloudKitSchema.Field.paragraphCount],
            bulletCount: record[int: CloudKitSchema.Field.bulletCount],
            hasAdditionalContext: record[bool: CloudKitSchema.Field.hasAdditionalContext],
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            version: max(record[int: CloudKitSchema.Field.version], 1),
            contentRTF: contentRTF,
            content: content,
            isPinned: record[bool: CloudKitSchema.Field.isPinned],
            conflictParentId: conflictParentId,
            localRevision: record[int64: CloudKitSchema.Field.localRevision],
            lastSyncedHash: lastSyncedHash,
            deviceId: deviceId
        )
    }

    private static func attachmentRecord(from record: CKRecord) -> AttachmentRemoteRecord? {
        guard record.recordType == CloudKitSchema.RecordType.attachment,
              let id = UUID(uuidString: record[string: CloudKitSchema.Field.id] ?? ""),
              let noteId = UUID(uuidString: record[string: CloudKitSchema.Field.noteId] ?? "") else { return nil }
        let fileName = record[string: CloudKitSchema.Field.fileName] ?? "attachment"
        let createdAt = record[date: CloudKitSchema.Field.createdAt] ?? Date()
        return AttachmentRemoteRecord(
            id: id,
            profileIdHash: record[string: CloudKitSchema.Field.profileIdHash] ?? "",
            noteId: noteId,
            storagePath: record[string: CloudKitSchema.Field.storagePath] ?? "",
            fileName: fileName,
            mimeType: record[string: CloudKitSchema.Field.mimeType] ?? "application/octet-stream",
            fileSize: record[int64: CloudKitSchema.Field.fileSize],
            createdAt: createdAt,
            updatedAt: record[date: CloudKitSchema.Field.updatedAt] ?? createdAt,
            deletedAt: record[date: CloudKitSchema.Field.deletedAt],
            localRevision: record[int64: CloudKitSchema.Field.localRevision],
            lastSyncedHash: record[string: CloudKitSchema.Field.lastSyncedHash],
            deviceId: record[string: CloudKitSchema.Field.deviceId] ?? ""
        )
    }

    private static func recordHash(_ record: CKRecord) -> String {
        var values: [String] = [record.recordType, record.recordID.recordName]
        for key in record.allKeys().sorted() {
            if key == CloudKitSchema.Field.asset { continue }
            if key == CloudKitSchema.Field.lastSyncedHash { continue }
            values.append("\(key)=\(String(describing: record[key]))")
        }
        return hash(values.joined(separator: "|"))
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}
