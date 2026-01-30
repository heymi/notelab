import Foundation
import Combine
import Supabase
import SwiftData

// MARK: - Attachment Cache (Thread-safe, no actor isolation)

/// Thread-safe local cache for attachment files
/// Using nonisolated to ensure these can be called from any context
enum AttachmentCache {
    nonisolated(unsafe) private static let cacheDirectory: URL = {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = cachesDir.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    /// Returns the local cache URL for an attachment
    nonisolated static func localCacheURL(for attachmentId: UUID, fileName: String) -> URL {
        let ext = (fileName as NSString).pathExtension
        let name = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
        return cacheDirectory.appendingPathComponent(name)
    }
    
    /// Save data to local cache
    @discardableResult
    nonisolated static func save(data: Data, attachmentId: UUID, fileName: String) -> URL? {
        let url = localCacheURL(for: attachmentId, fileName: fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            print("AttachmentCache: Failed to save \(attachmentId): \(error)")
            return nil
        }
    }
    
    /// Load data from local cache
    nonisolated static func load(attachmentId: UUID, fileName: String) -> Data? {
        let url = localCacheURL(for: attachmentId, fileName: fileName)
        return try? Data(contentsOf: url)
    }
    
    /// Check if local cache exists
    nonisolated static func exists(attachmentId: UUID, fileName: String) -> Bool {
        let url = localCacheURL(for: attachmentId, fileName: fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Delete from local cache
    nonisolated static func delete(attachmentId: UUID, fileName: String) {
        let url = localCacheURL(for: attachmentId, fileName: fileName)
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Clear all cached attachments
    nonisolated static func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Get total cache size
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

// MARK: - Attachment Storage (MainActor for Supabase operations)

/// Service for managing attachment file storage (Supabase Storage operations)
final class AttachmentStorage: ObservableObject {
    
    static let shared = AttachmentStorage()
    
    private let supabase: SupabaseClient
    private let bucketId = "attachments"
    
    @Published private(set) var uploadingIds: Set<UUID> = []
    @Published private(set) var downloadingIds: Set<UUID> = []
    
    private init(supabase: SupabaseClient = SupabaseManager.shared) {
        self.supabase = supabase
    }
    
    // MARK: - Local Cache (delegating to AttachmentCache)
    
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
    
    // MARK: - Supabase Storage Operations
    
    /// Upload attachment to Supabase Storage
    /// - Returns: The storage path on success
    func upload(
        data: Data,
        attachmentId: UUID,
        ownerId: UUID,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        await MainActor.run { uploadingIds.insert(attachmentId) }
        defer { Task { @MainActor in self.uploadingIds.remove(attachmentId) } }
        
        let ext = (fileName as NSString).pathExtension
        let storageName = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
        let storagePath = "\(ownerId.uuidString)/\(storageName)"
        
        _ = try await ensureValidSession(ownerId: ownerId)
        var lastError: Error?

        for attempt in 0..<2 {
            do {
                try await supabase.storage
                    .from(bucketId)
                    .upload(
                        storagePath,
                        data: data,
                        options: FileOptions(contentType: mimeType, upsert: true)
                    )
                return storagePath
            } catch {
                lastError = error
                if attempt == 0, isAuthError(error) {
                    _ = try? await supabase.auth.refreshSession()
                    _ = try? await ensureValidSession(ownerId: ownerId)
                    continue
                }
                break
            }
        }

        let latestSession = try? await supabase.auth.session
        let expired = latestSession?.isExpired ?? true
        let sessionUserId = latestSession?.user.id.uuidString ?? "nil"
        print("Attachment upload failed. userId=\(ownerId), sessionUserId=\(sessionUserId), path=\(storagePath), expired=\(expired), error=\(String(describing: lastError))")
        throw uploadError(from: lastError, ownerId: ownerId, sessionUserId: latestSession?.user.id)
        
    }
    
    /// Download attachment from Supabase Storage
    func download(storagePath: String, attachmentId: UUID, fileName: String) async throws -> Data {
        await MainActor.run { downloadingIds.insert(attachmentId) }
        defer { Task { @MainActor in self.downloadingIds.remove(attachmentId) } }
        
        let data = try await supabase.storage
            .from(bucketId)
            .download(path: storagePath)
        
        // Cache locally
        AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName)
        
        return data
    }
    
    /// Delete attachment from Supabase Storage
    func delete(storagePath: String) async throws {
        try await supabase.storage
            .from(bucketId)
            .remove(paths: [storagePath])
    }
    
    /// Get a signed URL for temporary access (valid for 1 hour)
    func getSignedURL(storagePath: String) async throws -> URL {
        try await supabase.storage
            .from(bucketId)
            .createSignedURL(path: storagePath, expiresIn: 3600)
    }
    
    // MARK: - Combined Operations
    
    /// Load attachment data: tries local cache first, then downloads from storage
    func loadAttachmentData(
        attachmentId: UUID,
        storagePath: String,
        fileName: String
    ) async throws -> Data {
        try await Task.detached(priority: .utility) { [supabase, bucketId] in
            if let cached = AttachmentCache.load(attachmentId: attachmentId, fileName: fileName) {
                return cached
            }
            let data = try await supabase.storage
                .from(bucketId)
                .download(path: storagePath)
            AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName)
            return data
        }.value
    }
    
    /// Save new attachment: saves to cache and creates local record
    func saveNewAttachment(
        data: Data,
        attachmentId: UUID,
        ownerId: UUID,
        noteId: UUID,
        fileName: String,
        mimeType: String,
        context: ModelContext
    ) async throws -> LocalAttachment {
        // 1. Save to local cache
        guard let cacheURL = AttachmentCache.save(data: data, attachmentId: attachmentId, fileName: fileName) else {
            throw NSError(domain: "AttachmentStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save to cache"])
        }
        
        // 2. Create local record (dirty, not uploaded yet)
        let ext = (fileName as NSString).pathExtension
        let storageName = ext.isEmpty ? attachmentId.uuidString : "\(attachmentId.uuidString).\(ext)"
        let storagePath = "\(ownerId.uuidString)/\(storageName)"
        
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
    
    // MARK: - Sync Support
    
    /// Upload all pending (not yet uploaded) attachments
    func uploadPendingAttachments(context: ModelContext, ownerId: UUID) async throws {
        let pending = try await MainActor.run {
            let pred = #Predicate<LocalAttachment> { att in
                att.ownerId == ownerId && att.isUploaded == false && att.deletedAt == nil
            }
            let fetch = FetchDescriptor<LocalAttachment>(predicate: pred)
            return try context.fetch(fetch)
        }
        if Task.isCancelled { return }
        
        for attachment in pending {
            if Task.isCancelled { return }
            let snapshot: AttachmentSnapshot = await MainActor.run {
                self.snapshot(from: attachment)
            }
            guard let data = AttachmentCache.load(attachmentId: snapshot.id, fileName: snapshot.fileName) else {
                continue
            }
            
            do {
                let path = try await upload(
                    data: data,
                    attachmentId: snapshot.id,
                    ownerId: snapshot.ownerId,
                    fileName: snapshot.fileName,
                    mimeType: snapshot.mimeType
                )
                await MainActor.run {
                    if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                        liveAttachment.storagePath = path
                        liveAttachment.isUploaded = true
                        liveAttachment.remoteUpdatedAt = Date()
                    }
                }
            } catch {
                // Continue with next, don't fail entire batch
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

    /// Upload a specific attachment immediately and upsert metadata.
    func uploadAndUpsertMetadata(attachment: LocalAttachment, context: ModelContext) async {
        let snapshot: AttachmentSnapshot = await MainActor.run {
            self.snapshot(from: attachment)
        }
        guard snapshot.deletedAt == nil else { return }
        guard let data = AttachmentCache.load(attachmentId: snapshot.id, fileName: snapshot.fileName) else {
            return
        }

        do {
            let path = try await upload(
                data: data,
                attachmentId: snapshot.id,
                ownerId: snapshot.ownerId,
                fileName: snapshot.fileName,
                mimeType: snapshot.mimeType
            )

            let payload = AttachmentMetadataUpsert(
                id: snapshot.id,
                userId: snapshot.ownerId,
                noteId: snapshot.noteId,
                storagePath: path,
                fileName: snapshot.fileName,
                mimeType: snapshot.mimeType,
                fileSize: snapshot.fileSize,
                deletedAt: snapshot.deletedAt
            )

            let returned: [AttachmentMetadataRow] = try await supabase
                .from("attachments")
                .upsert(payload)
                .select()
                .execute()
                .value

            await MainActor.run {
                if let row = returned.first {
                    if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                        liveAttachment.remoteUpdatedAt = row.updatedAtDate ?? liveAttachment.remoteUpdatedAt
                    }
                } else {
                    if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                        liveAttachment.remoteUpdatedAt = Date()
                    }
                }
                if let liveAttachment = fetchAttachment(id: snapshot.id, context: context) {
                    liveAttachment.storagePath = path
                    liveAttachment.isUploaded = true
                    liveAttachment.isDirty = false
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
            print("Failed to upload attachment metadata \(snapshot.id): \(error)")
        }
    }
    
    // MARK: - Cache Management (delegating to AttachmentCache)
    
    nonisolated func clearCache() {
        AttachmentCache.clearAll()
    }
    
    nonisolated func cacheSize() -> Int64 {
        AttachmentCache.totalSize()
    }
}

// MARK: - MIME Type Helpers

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
        return .image // default
    }
}

// MARK: - Attachment Metadata Types (local to AttachmentStorage)

private struct AttachmentMetadataRow: Decodable {
    let id: UUID
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
    }

    var updatedAtDate: Date? { AttachmentStorage.parseISO(updatedAt) }
}

private struct AttachmentMetadataUpsert: Encodable {
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

private extension AttachmentStorage {
    struct AttachmentSnapshot {
        let id: UUID
        let ownerId: UUID
        let noteId: UUID
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

    func ensureValidSession(ownerId: UUID) async throws -> Session {
        let session = try await supabase.auth.session
        if session.isExpired {
            throw NSError(domain: "AttachmentStorage", code: 401, userInfo: [NSLocalizedDescriptionKey: "登录已过期，请重新登录"])
        }
        if session.user.id != ownerId {
            throw NSError(domain: "AttachmentStorage", code: 403, userInfo: [NSLocalizedDescriptionKey: "当前登录账号与附件归属不一致"])
        }
        return session
    }

    func isAuthError(_ error: Error) -> Bool {
        if let storageError = error as? StorageError,
           let status = storageError.statusCode,
           status == "401" || status == "403" {
            return true
        }
        let message = String(describing: error).lowercased()
        return message.contains("unauthorized") || message.contains("forbidden")
    }

    func uploadError(from error: Error?, ownerId: UUID, sessionUserId: UUID?) -> Error {
        if let error {
            if let storageError = error as? StorageError,
               storageError.statusCode == "403" {
                return NSError(domain: "AttachmentStorage", code: 403, userInfo: [NSLocalizedDescriptionKey: "没有权限上传附件（RLS 拒绝）"])
            }
            if let storageError = error as? StorageError,
               storageError.statusCode == "401" {
                return NSError(domain: "AttachmentStorage", code: 401, userInfo: [NSLocalizedDescriptionKey: "登录已过期，请重新登录"])
            }
            if isAuthError(error) {
                return NSError(domain: "AttachmentStorage", code: 401, userInfo: [NSLocalizedDescriptionKey: "登录已过期，请重新登录"])
            }
            let message = String(describing: error).lowercased()
            if message.contains("row-level security") || message.contains("new row violates") || message.contains("rls") {
                return NSError(domain: "AttachmentStorage", code: 403, userInfo: [NSLocalizedDescriptionKey: "没有权限上传附件（RLS 拒绝）"])
            }
        }
        if let sessionUserId, sessionUserId != ownerId {
            return NSError(domain: "AttachmentStorage", code: 403, userInfo: [NSLocalizedDescriptionKey: "当前登录账号与附件归属不一致"])
        }
        return error ?? NSError(domain: "AttachmentStorage", code: 2, userInfo: [NSLocalizedDescriptionKey: "上传失败"])
    }

    static func parseISO(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: value) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: value)
    }
}
