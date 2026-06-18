@preconcurrency import CloudKit
import Combine
import CoreData
import Foundation
import os

protocol CloudSyncing: ObservableObject {
    var isSyncing: Bool { get }
    var lastSyncAt: Date? { get }
    var lastError: String? { get }
    func configure(profileId: UUID)
    func resetForSignOut()
    func syncNow() async
}

@MainActor
final class SyncEngine: ObservableObject, CloudSyncing {
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?

    private var profileId: UUID?
    private let notebookRepository = NotebookRepository()
    private let attachmentRepository = AttachmentRepository()
    private let syncStateRepository = SyncStateRepository()
    private let transport = CloudKitTransport()
    private let storage = StorageController.shared
    private let logger = Logger(subsystem: "NoteLab", category: "CloudKitSync")

    func configure(profileId: UUID) {
        self.profileId = profileId
    }

    func resetForSignOut() {
        profileId = nil
        isSyncing = false
        lastSyncAt = nil
        lastError = nil
    }

    func syncNow() async {
        guard let profileId else { return }

        let canSync = SubscriptionManager.shared.canUseSync()
        if !canSync {
            lastError = "云同步为付费功能，请升级订阅"
            NotificationCenter.default.post(name: .showPaywall, object: PaywallTrigger.syncAttempt)
            return
        }

        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let status = try await CloudKitSchema.container.accountStatus()
            guard status == .available else {
                lastError = "当前设备未开启 iCloud，同步已暂停，本地数据仍可继续使用"
                return
            }

            let iCloudAccountHash = try await transport.iCloudAccountHash()
            try await transport.ensureInfrastructure()
            try await pushOutbox(profileId: profileId)
            try await pullChanges(profileId: profileId, iCloudAccountHash: iCloudAccountHash)

            lastSyncAt = Date()
            lastError = nil
        } catch {
            logger.error("sync failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    private func pushOutbox(profileId: UUID) async throws {
        let items = try notebookRepository.pendingOutbox(profileId: profileId)
        for item in items {
            if Task.isCancelled { return }
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
                    let request = AttachmentEntity.fetchRequest() as! NSFetchRequest<AttachmentEntity>
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
            } catch {
                try? notebookRepository.markOutboxFailed(item, error: error)
                logger.error("outbox item failed \(item.entityType.rawValue, privacy: .public)/\(item.entityId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func pullChanges(profileId: UUID, iCloudAccountHash: String) async throws {
        let tokenData = try syncStateRepository.changeToken(
            profileId: profileId,
            iCloudAccountHash: iCloudAccountHash,
            zoneName: CloudKitSchema.zoneName
        )
        let previousToken = CloudKitTransport.decodeToken(tokenData)
        let changes: CloudKitChangeBatch
        do {
            changes = try await transport.fetchChanges(since: previousToken)
        } catch let error as CKError where error.code == .changeTokenExpired {
            logger.warning("change token expired; running full reconciliation")
            changes = try await transport.fetchChanges(since: nil)
        }

        let expectedProfileHash = CloudKitTransport.hash(profileId.uuidString.lowercased())
        for notebook in changes.notebooks where notebook.profileIdHash == expectedProfileHash {
            try notebookRepository.applyRemoteNotebook(profileId: profileId, record: notebook)
        }
        for note in changes.notes where note.profileIdHash == expectedProfileHash {
            try notebookRepository.applyRemoteNote(profileId: profileId, record: note)
        }
        for attachment in changes.attachments where attachment.profileIdHash == expectedProfileHash {
            try attachmentRepository.applyRemote(profileId: profileId, record: attachment)
        }
        try storage.saveMainContext()

        try syncStateRepository.setChangeToken(
            CloudKitTransport.encodeToken(changes.serverChangeToken),
            profileId: profileId,
            iCloudAccountHash: iCloudAccountHash,
            zoneName: CloudKitSchema.zoneName
        )
    }
}
