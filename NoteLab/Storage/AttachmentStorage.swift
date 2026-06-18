@preconcurrency import CloudKit
import Combine
import Foundation
import SwiftData

enum AttachmentCache {
    nonisolated(unsafe) private static let cacheDirectory: URL = {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = cachesDir.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated static func localCacheURL(for attachmentId: UUID, fileName: String) -> URL {
        let ext = (fileName as NSString).pathExtension
        let name = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
        return cacheDirectory.appendingPathComponent(name)
    }

    @discardableResult
    nonisolated static func save(data: Data, attachmentId: UUID, fileName: String) -> URL? {
        let url = localCacheURL(for: attachmentId, fileName: fileName)
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            print("AttachmentCache: Failed to save \(attachmentId): \(error)")
            return nil
        }
    }

    nonisolated static func load(attachmentId: UUID, fileName: String) -> Data? {
        try? Data(contentsOf: localCacheURL(for: attachmentId, fileName: fileName))
    }

    nonisolated static func exists(attachmentId: UUID, fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: localCacheURL(for: attachmentId, fileName: fileName).path)
    }

    nonisolated static func delete(attachmentId: UUID, fileName: String) {
        try? FileManager.default.removeItem(at: localCacheURL(for: attachmentId, fileName: fileName))
    }

    nonisolated static func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    nonisolated static func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

final class AttachmentStorage: ObservableObject {
    static let shared = AttachmentStorage()

    @Published private(set) var uploadingIds: Set<UUID> = []
    @Published private(set) var downloadingIds: Set<UUID> = []

    private init() {}

    @MainActor
    func saveNewAttachmentV3(
        data: Data,
        attachmentId: UUID,
        ownerId: UUID,
        noteId: UUID,
        fileName: String,
        mimeType: String
    ) throws -> AttachmentRecord {
        try AttachmentRepository().saveAttachment(
            data: data,
            attachmentId: attachmentId,
            profileId: ownerId,
            noteId: noteId,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    @MainActor
    func uploadAndUpsertMetadataV3(attachment: AttachmentRecord) async {
        guard attachment.deletedAt == nil,
              let data = AttachmentFileStore.loadOriginal(
                attachmentId: attachment.id,
                fileName: attachment.fileName,
                originalPath: attachment.originalPath
              ) else { return }
        do {
            try await uploadToCloudKit(
                snapshot: AttachmentSnapshot(
                    id: attachment.id,
                    ownerId: attachment.profileId,
                    noteId: attachment.noteId,
                    storagePath: attachment.storagePath,
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType,
                    fileSize: attachment.fileSize,
                    deletedAt: attachment.deletedAt
                ),
                data: data
            )
            try AttachmentRepository().markUploaded(profileId: attachment.profileId, id: attachment.id, syncedHash: nil)
        } catch {
            print("Failed to upload iCloud attachment \(attachment.id): \(error)")
        }
    }

    nonisolated func localCacheURL(for attachmentId: UUID, fileName: String) -> URL {
        AttachmentCache.localCacheURL(for: attachmentId, fileName: fileName)
    }

    nonisolated func saveToCache(data: Data, attachmentId: UUID, fileName: String) throws -> URL {
        guard let url = AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName) else {
            throw NSError(domain: "AttachmentStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save to cache"])
        }
        return url
    }

    nonisolated func loadFromCache(attachmentId: UUID, fileName: String) -> Data? {
        AttachmentCache.load(attachmentId: attachmentId, fileName: fileName)
    }

    nonisolated func cacheExists(attachmentId: UUID, fileName: String) -> Bool {
        AttachmentCache.exists(attachmentId: attachmentId, fileName: fileName)
    }

    nonisolated func deleteFromCache(attachmentId: UUID, fileName: String) {
        AttachmentCache.delete(attachmentId: attachmentId, fileName: fileName)
    }

    func upload(
        data: Data,
        attachmentId: UUID,
        ownerId: UUID,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        let storagePath = CloudKitSchema.storagePath(ownerId: ownerId, attachmentId: attachmentId, fileName: fileName)
        try await uploadToCloudKit(
            snapshot: AttachmentSnapshot(
                id: attachmentId,
                ownerId: ownerId,
                noteId: nil,
                storagePath: storagePath,
                fileName: fileName,
                mimeType: mimeType,
                fileSize: Int64(data.count),
                deletedAt: nil
            ),
            data: data
        )
        return storagePath
    }

    func download(storagePath: String, attachmentId: UUID, fileName: String) async throws -> Data {
        try await loadAttachmentData(attachmentId: attachmentId, storagePath: storagePath, fileName: fileName)
    }

    func delete(storagePath: String) async throws {
        guard let attachmentId = CloudKitSchema.attachmentId(from: storagePath) else { return }
        try await CloudKitBridge.ensurePrivateZone()
        let recordID = CloudKitSchema.recordID(type: CloudKitSchema.RecordType.attachment, id: attachmentId)
        let record = try await CloudKitBridge.fetchRecord(recordID) ?? CKRecord(recordType: CloudKitSchema.RecordType.attachment, recordID: recordID)
        let now = Date()
        record[date: CloudKitSchema.Field.deletedAt] = now
        record[date: CloudKitSchema.Field.updatedAt] = now
        _ = try await CloudKitBridge.save(record: record)
    }

    func getSignedURL(storagePath: String) async throws -> URL {
        guard let attachmentId = CloudKitSchema.attachmentId(from: storagePath) else {
            throw NSError(domain: "AttachmentStorage", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效的 iCloud 附件路径"])
        }
        try await CloudKitBridge.ensurePrivateZone()
        let recordID = CloudKitSchema.recordID(type: CloudKitSchema.RecordType.attachment, id: attachmentId)
        guard let record = try await CloudKitBridge.fetchRecord(recordID),
              let fileName = record[string: CloudKitSchema.Field.fileName],
              let asset = record[asset: CloudKitSchema.Field.asset],
              let sourceURL = asset.fileURL else {
            throw NSError(domain: "AttachmentStorage", code: 3, userInfo: [NSLocalizedDescriptionKey: "附件尚未同步到 iCloud"])
        }
        let targetURL = AttachmentCache.localCacheURL(for: attachmentId, fileName: fileName)
        if !FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        }
        return targetURL
    }

    func loadAttachmentData(
        attachmentId: UUID,
        storagePath: String,
        fileName: String
    ) async throws -> Data {
        if let ownerId = CloudKitSchema.ownerId(from: storagePath),
           let attachment = try? await MainActor.run(body: {
               try AttachmentRepository().find(profileId: ownerId, id: attachmentId)
           }),
           let original = AttachmentFileStore.loadOriginal(
               attachmentId: attachmentId,
               fileName: fileName,
               originalPath: attachment.originalPath
           ) {
            print("[AttachmentStorage] source=original attachmentId=\(attachmentId.uuidString.lowercased()) fileName=\(fileName)")
            return original
        }

        if let cached = AttachmentCache.load(attachmentId: attachmentId, fileName: fileName) {
            print("[AttachmentStorage] source=cache attachmentId=\(attachmentId.uuidString.lowercased()) fileName=\(fileName)")
            return cached
        }

        await MainActor.run { downloadingIds.insert(attachmentId) }
        defer { Task { @MainActor in self.downloadingIds.remove(attachmentId) } }

        try await CloudKitBridge.ensurePrivateZone()
        let recordID = CloudKitSchema.recordID(type: CloudKitSchema.RecordType.attachment, id: attachmentId)
        guard let record = try await CloudKitBridge.fetchRecord(recordID),
              let asset = record[asset: CloudKitSchema.Field.asset],
              let sourceURL = asset.fileURL else {
            throw NSError(domain: "AttachmentStorage", code: 4, userInfo: [NSLocalizedDescriptionKey: "附件尚未同步到 iCloud"])
        }
        let data = try Data(contentsOf: sourceURL)
        AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName)
        print("[AttachmentStorage] source=icloud attachmentId=\(attachmentId.uuidString.lowercased()) storagePath=\(storagePath)")
        return data
    }

    func saveNewAttachment(
        data: Data,
        attachmentId: UUID,
        ownerId: UUID,
        noteId: UUID,
        fileName: String,
        mimeType: String,
        context: ModelContext
    ) async throws -> LocalAttachment {
        guard let cacheURL = AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName) else {
            throw NSError(domain: "AttachmentStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save to cache"])
        }

        let storagePath = CloudKitSchema.storagePath(ownerId: ownerId, attachmentId: attachmentId, fileName: fileName)
        let attachment = LocalAttachment(
            id: attachmentId,
            ownerId: ownerId,
            noteId: noteId,
            storagePath: storagePath,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: Int64(data.count),
            createdAt: Date(),
            remoteUpdatedAt: Date(),
            localCachePath: cacheURL.path,
            isDirty: true,
            isUploaded: false
        )
        await MainActor.run {
            context.insert(attachment)
        }
        return attachment
    }

    func uploadPendingAttachments(context: ModelContext, ownerId: UUID) async throws {
        let pending = try await MainActor.run {
            let pred = #Predicate<LocalAttachment> { att in
                att.ownerId == ownerId && att.isUploaded == false && att.deletedAt == nil
            }
            return try context.fetch(FetchDescriptor<LocalAttachment>(predicate: pred))
        }

        for attachment in pending {
            if Task.isCancelled { return }
            let snapshot = await MainActor.run { self.snapshot(from: attachment) }
            guard let data = AttachmentCache.load(attachmentId: snapshot.id, fileName: snapshot.fileName) else {
                continue
            }
            do {
                try await uploadToCloudKit(snapshot: snapshot, data: data)
                await MainActor.run {
                    if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                        liveAttachment.isUploaded = true
                        liveAttachment.isDirty = false
                        liveAttachment.remoteUpdatedAt = Date()
                    }
                }
            } catch {
                await MainActor.run {
                    if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                        liveAttachment.isUploaded = false
                        liveAttachment.isDirty = true
                    }
                    try? context.save()
                }
                print("Failed to upload attachment \(snapshot.id): \(error)")
            }
        }
    }

    func uploadAndUpsertMetadata(attachment: LocalAttachment, context: ModelContext) async {
        let snapshot = await MainActor.run { self.snapshot(from: attachment) }
        guard snapshot.deletedAt == nil,
              let data = AttachmentCache.load(attachmentId: snapshot.id, fileName: snapshot.fileName) else {
            return
        }

        do {
            try await uploadToCloudKit(snapshot: snapshot, data: data)
            await MainActor.run {
                if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                    liveAttachment.isUploaded = true
                    liveAttachment.isDirty = false
                    liveAttachment.remoteUpdatedAt = Date()
                    try? context.save()
                }
            }
        } catch {
            await MainActor.run {
                if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                    liveAttachment.isDirty = true
                    liveAttachment.isUploaded = false
                    try? context.save()
                }
            }
            print("Failed to upload iCloud attachment \(snapshot.id): \(error)")
        }
    }

    nonisolated func clearCache() {
        AttachmentCache.clearAll()
    }

    nonisolated func cacheSize() -> Int64 {
        AttachmentCache.totalSize()
    }
}

extension AttachmentStorage {
    static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }

    static func attachmentType(from mimeType: String) -> AttachmentType {
        if mimeType.hasPrefix("image/") {
            return .image
        } else if mimeType == "application/pdf" {
            return .pdf
        }
        return .image
    }
}

private extension AttachmentStorage {
    struct AttachmentSnapshot {
        let id: UUID
        let ownerId: UUID
        let noteId: UUID?
        let storagePath: String
        let fileName: String
        let mimeType: String
        let fileSize: Int64
        let deletedAt: Date?
    }

    func snapshot(from attachment: LocalAttachment) -> AttachmentSnapshot {
        AttachmentSnapshot(
            id: attachment.id,
            ownerId: attachment.ownerId,
            noteId: attachment.noteId,
            storagePath: attachment.storagePath,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            fileSize: attachment.fileSize,
            deletedAt: attachment.deletedAt
        )
    }

    func fetchAttachment(id: UUID, context: ModelContext) -> LocalAttachment? {
        let pred = #Predicate<LocalAttachment> { att in
            att.id == id
        }
        var fetch = FetchDescriptor<LocalAttachment>(predicate: pred)
        fetch.fetchLimit = 1
        return try? context.fetch(fetch).first
    }

    func uploadToCloudKit(snapshot: AttachmentSnapshot, data: Data) async throws {
        await MainActor.run { uploadingIds.insert(snapshot.id) }
        defer { Task { @MainActor in self.uploadingIds.remove(snapshot.id) } }

        try await CloudKitBridge.ensurePrivateZone()
        guard let assetURL = AttachmentCache.save(data: data, attachmentId: snapshot.id, fileName: snapshot.fileName) else {
            throw NSError(domain: "AttachmentStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save attachment before iCloud upload"])
        }

        let recordID = CloudKitSchema.recordID(type: CloudKitSchema.RecordType.attachment, id: snapshot.id)
        let record = try await CloudKitBridge.fetchRecord(recordID) ?? CKRecord(recordType: CloudKitSchema.RecordType.attachment, recordID: recordID)
        let now = Date()
        record[string: CloudKitSchema.Field.id] = snapshot.id.uuidString
        record[string: CloudKitSchema.Field.ownerId] = snapshot.ownerId.uuidString
        record[string: CloudKitSchema.Field.noteId] = snapshot.noteId?.uuidString
        record[string: CloudKitSchema.Field.storagePath] = snapshot.storagePath
        record[string: CloudKitSchema.Field.fileName] = snapshot.fileName
        record[string: CloudKitSchema.Field.mimeType] = snapshot.mimeType
        record[int64: CloudKitSchema.Field.fileSize] = snapshot.fileSize
        record[date: CloudKitSchema.Field.createdAt] = record[date: CloudKitSchema.Field.createdAt] ?? now
        record[date: CloudKitSchema.Field.updatedAt] = now
        record[date: CloudKitSchema.Field.deletedAt] = snapshot.deletedAt
        record[asset: CloudKitSchema.Field.asset] = CKAsset(fileURL: assetURL)
        _ = try await CloudKitBridge.save(record: record)
    }
}
