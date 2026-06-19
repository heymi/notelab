import CloudKit
import CryptoKit
import Foundation

struct SyncProfileIdentity: Equatable {
    enum Source: Equatable {
        case cloudKit
        case localOnly
    }

    let profileId: UUID
    let legacyProfileId: UUID
    let iCloudAccountHash: String?
    let source: Source

    var isCloudBacked: Bool {
        source == .cloudKit
    }
}

enum StableIdentity {
    static func uuid(for value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum SyncProfileIdentityResolver {
    static func resolve(account: AppleAccount, container: CKContainer = CloudKitSchema.container) async -> SyncProfileIdentity {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                return localIdentity(for: account)
            }
            let userRecordID = try await container.userRecordID()
            let accountHash = CloudKitTransport.hash(userRecordID.recordName)
            let profileId = StableIdentity.uuid(for: "icloud:\(userRecordID.recordName)")
            return SyncProfileIdentity(
                profileId: profileId,
                legacyProfileId: account.localUserId,
                iCloudAccountHash: accountHash,
                source: .cloudKit
            )
        } catch {
            return localIdentity(for: account)
        }
    }

    static func localIdentity(for account: AppleAccount) -> SyncProfileIdentity {
        SyncProfileIdentity(
            profileId: account.localUserId,
            legacyProfileId: account.localUserId,
            iCloudAccountHash: nil,
            source: .localOnly
        )
    }
}
