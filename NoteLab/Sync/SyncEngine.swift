@preconcurrency import CloudKit
import Combine
import CoreData
import Foundation
import os

protocol CloudSyncing: ObservableObject {
    var isSyncing: Bool { get }
    var lastSyncAt: Date? { get }
    var lastPushAt: Date? { get }
    var lastPullAt: Date? { get }
    var lastError: String? { get }
    var lastSummary: SyncSummary? { get }
    var pendingItemCount: Int { get }
    var lastCloudRecordCount: Int? { get }
    var canClearLocalData: Bool { get }
    func configure(profileId: UUID)
    func resetForSignOut()
    func syncNow() async
    func syncNow(reason: SyncReason) async -> SyncSummary
    func refreshPendingCount()
}

enum SyncReason: String, Equatable {
    case launch
    case sceneActive
    case remoteNotification
    case manual
    case backgroundRefresh

    var shouldShowPaywall: Bool {
        switch self {
        case .launch, .sceneActive, .manual:
            return true
        case .remoteNotification, .backgroundRefresh:
            return false
        }
    }
}

struct SyncSummary: Equatable {
    var reason: SyncReason
    var pushed: Int = 0
    var pulled: Int = 0
    var deleted: Int = 0
    var failed: Int = 0
    var skipped: Int = 0
    var message: String?

    var hasFailures: Bool {
        failed > 0 || message != nil
    }

    static func skipped(reason: SyncReason, message: String) -> SyncSummary {
        SyncSummary(reason: reason, skipped: 1, message: message)
    }

    mutating func merge(_ other: SyncSummary) {
        pushed += other.pushed
        pulled += other.pulled
        deleted += other.deleted
        failed += other.failed
        skipped += other.skipped
        if message == nil {
            message = other.message
        }
    }
}

@MainActor
final class SyncEngine: ObservableObject, CloudSyncing {
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastPushAt: Date?
    @Published private(set) var lastPullAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastSummary: SyncSummary?
    @Published private(set) var pendingItemCount: Int = 0
    @Published private(set) var lastCloudRecordCount: Int?

    private var profileId: UUID?
    private let notebookRepository = NotebookRepository()
    private let attachmentRepository = AttachmentRepository()
    private let syncStateRepository = SyncStateRepository()
    private let transport: CloudKitTransporting
    private let storage = StorageController.shared
    private let logger = Logger(subsystem: "NoteLab", category: "CloudKitSync")

    init(transport: CloudKitTransporting? = nil) {
        self.transport = transport ?? CloudKitTransport()
    }

    func configure(profileId: UUID) {
        self.profileId = profileId
        refreshPendingCount()
    }

    var canClearLocalData: Bool {
        pendingItemCount == 0 && lastSyncAt != nil
    }

    func resetForSignOut() {
        profileId = nil
        isSyncing = false
        lastSyncAt = nil
        lastPushAt = nil
        lastPullAt = nil
        lastError = nil
        lastSummary = nil
        pendingItemCount = 0
        lastCloudRecordCount = nil
    }

    func syncNow() async {
        _ = await syncNow(reason: .manual)
    }

    @discardableResult
    func syncNow(reason: SyncReason) async -> SyncSummary {
        guard let profileId else {
            let summary = SyncSummary.skipped(reason: reason, message: "当前账号尚未准备好")
            lastSummary = summary
            return summary
        }

        guard !isSyncing else {
            let summary = SyncSummary.skipped(reason: reason, message: "已有同步任务正在进行")
            lastSummary = summary
            return summary
        }
        isSyncing = true
        defer { isSyncing = false }

        var summary = SyncSummary(reason: reason)
        do {
            let status = try await CloudKitSchema.container.accountStatus()
            guard status == .available else {
                let message = "当前设备未开启 iCloud，同步已暂停，本地数据仍可继续使用"
                lastError = message
                summary.message = message
                lastSummary = summary
                return summary
            }

            let iCloudAccountHash = try await transport.iCloudAccountHash()
            try await transport.ensureInfrastructure()
            if reason == .manual {
                _ = try notebookRepository.enqueueFullUpload(profileId: profileId)
                _ = try attachmentRepository.enqueueFullUpload(profileId: profileId)
            }
            summary.merge(try await pushOutbox(profileId: profileId))
            summary.merge(try await pullChanges(profileId: profileId, iCloudAccountHash: iCloudAccountHash, reason: reason))
            refreshPendingCount()

            lastSyncAt = Date()
            if summary.pushed > 0 { lastPushAt = lastSyncAt }
            if summary.pulled > 0 || summary.deleted > 0 || lastCloudRecordCount != nil { lastPullAt = lastSyncAt }
            lastError = summary.hasFailures ? summary.message ?? "部分内容同步失败，稍后会自动重试" : nil
            lastSummary = summary
            return summary
        } catch {
            logger.error("sync failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            summary.failed += 1
            summary.message = error.localizedDescription
            lastSummary = summary
            refreshPendingCount()
            return summary
        }
    }

    func refreshPendingCount() {
        guard let profileId else {
            pendingItemCount = 0
            return
        }
        pendingItemCount = (try? notebookRepository.pendingOutbox(profileId: profileId, limit: 1_000).count) ?? 0
    }

    private func pushOutbox(profileId: UUID) async throws -> SyncSummary {
        var summary = SyncSummary(reason: .manual)
        let items = try notebookRepository.pendingOutbox(profileId: profileId)
        for item in items {
            if Task.isCancelled { return summary }
            do {
                switch item.entityType {
                case .notebook:
                    if let entity = try notebookRepository.notebookEntity(profileId: profileId, id: item.entityId) {
                        let hash = try await transport.pushNotebook(entity, profileId: profileId)
                        entity.lastSyncedHash = hash
                    }
                case .note:
                    if let entity = try notebookRepository.noteEntity(profileId: profileId, id: item.entityId) {
                        let hash = try await transport.pushNote(entity, profileId: profileId)
                        entity.lastSyncedHash = hash
                    }
                case .attachment:
                    let request = AttachmentEntity.fetchRequest()
                    request.predicate = NSPredicate(
                        format: "profileId == %@ AND id == %@",
                        profileId.uuidString.lowercased(),
                        item.entityId.uuidString.lowercased()
                    )
                    request.fetchLimit = 1
                    if let entity = try storage.mainContext.fetch(request).first {
                        let hash = try await transport.pushAttachment(entity, profileId: profileId)
                        entity.lastSyncedHash = hash
                        entity.isUploaded = true
                    }
                }

                try storage.saveMainContext()
                try notebookRepository.markOutboxDone(item)
                summary.pushed += 1
            } catch {
                try? notebookRepository.markOutboxFailed(item, error: error)
                summary.failed += 1
                if summary.message == nil {
                    summary.message = "部分内容同步失败，稍后会自动重试"
                }
                logger.error("outbox item failed \(item.entityType.rawValue, privacy: .public)/\(item.entityId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return summary
    }

    private func pullChanges(profileId: UUID, iCloudAccountHash: String, reason: SyncReason) async throws -> SyncSummary {
        let tokenData = try syncStateRepository.changeToken(
            profileId: profileId,
            iCloudAccountHash: iCloudAccountHash,
            zoneName: CloudKitSchema.zoneName
        )
        // ponytail: manual sync is a full reconcile; optimize when data volume proves it needs paging UI.
        let previousToken = reason == .manual ? nil : CloudKitTransport.decodeToken(tokenData)
        let changes: CloudKitChangeBatch
        var summary = SyncSummary(reason: .manual)
        do {
            changes = try await transport.fetchChanges(since: previousToken)
        } catch let error as CKError where error.code == .changeTokenExpired {
            logger.warning("change token expired; running full reconciliation")
            changes = try await transport.fetchChanges(since: nil)
        }

        let expectedProfileHash = CloudKitTransport.hash(profileId.uuidString.lowercased())
        for notebook in changes.notebooks where notebook.profileIdHash == expectedProfileHash {
            try notebookRepository.applyRemoteNotebook(profileId: profileId, record: notebook)
            summary.pulled += 1
        }
        for note in changes.notes where note.profileIdHash == expectedProfileHash {
            try notebookRepository.applyRemoteNote(profileId: profileId, record: note)
            summary.pulled += 1
        }
        for attachment in changes.attachments where attachment.profileIdHash == expectedProfileHash {
            try attachmentRepository.applyRemote(profileId: profileId, record: attachment)
            summary.pulled += 1
        }
        for deleted in changes.deletedRecords where deleted.profileId == profileId {
            switch deleted.entityType {
            case .notebook:
                try notebookRepository.applyRemoteHardDelete(profileId: profileId, entityType: .notebook, id: deleted.id)
            case .note:
                try notebookRepository.applyRemoteHardDelete(profileId: profileId, entityType: .note, id: deleted.id)
            case .attachment:
                try attachmentRepository.applyRemoteHardDelete(profileId: profileId, id: deleted.id)
            }
            summary.deleted += 1
        }
        lastCloudRecordCount = changes.notebooks.count + changes.notes.count + changes.attachments.count
        try storage.saveMainContext()

        try syncStateRepository.setChangeToken(
            CloudKitTransport.encodeToken(changes.serverChangeToken),
            profileId: profileId,
            iCloudAccountHash: iCloudAccountHash,
            zoneName: CloudKitSchema.zoneName
        )
        return summary
    }
}
