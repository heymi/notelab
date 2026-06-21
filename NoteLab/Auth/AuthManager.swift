import AuthenticationServices
import CloudKit
import Combine
import CryptoKit
import Foundation
import Security

enum ICloudAccountState: Equatable {
    case unknown
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable

    var canSync: Bool {
        self == .available
    }

    var message: String? {
        switch self {
        case .unknown:
            return nil
        case .available:
            return "iCloud 同步已开启"
        case .noAccount:
            return "当前设备未登录 iCloud，云同步已暂停"
        case .restricted:
            return "当前 iCloud 账户受限，云同步已暂停"
        case .couldNotDetermine:
            return "暂时无法确认 iCloud 状态，云同步稍后重试"
        case .temporarilyUnavailable:
            return "iCloud 暂时不可用，云同步稍后重试"
        }
    }
}

struct AppleAccount: Codable, Equatable {
    let appleUserId: String
    let email: String?
    let displayName: String?
    let localUserId: UUID

    var isSimulatorLocalAccount: Bool {
        appleUserId.hasPrefix("simulator-local-")
    }
}

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var account: AppleAccount?
    @Published private(set) var iCloudState: ICloudAccountState = .unknown
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    var isAuthenticated: Bool {
        account != nil
    }

    var userId: UUID? {
        account?.localUserId
    }

    var displayEmail: String? {
        account?.email ?? account?.displayName ?? "Apple 账号"
    }

    var iCloudStatusMessage: String? {
        iCloudState.message
    }

    init() {
        let storedAccount = Self.loadStoredAccount()
        if Self.shouldDiscardStoredAccountOnLaunch(
            hasStoredAccount: storedAccount != nil,
            hasInstallMarker: Self.hasInstallMarker,
            hasLocalInstallData: Self.hasLocalInstallData()
        ) {
            Self.deleteStoredAccount()
            account = nil
        } else {
            account = storedAccount
        }
        Self.markInstalled()
        Task {
            await refreshAppleCredentialState()
            await refreshICloudAccountState()
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        isLoading = true
        request.requestedScopes = [.fullName, .email]
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple 登录返回了无效凭证"
                return
            }

            let stored = Self.loadStoredAccount()
            let name = credential.fullName.flatMap(Self.displayName(from:))
            let nextAccount = AppleAccount(
                appleUserId: credential.user,
                email: credential.email ?? stored?.email,
                displayName: name ?? stored?.displayName,
                localUserId: Self.stableUUID(for: credential.user)
            )
            account = nextAccount
            Self.store(account: nextAccount)
            errorMessage = nil
            Task { await refreshICloudAccountState() }

        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        account = nil
        errorMessage = nil
        iCloudState = .unknown
        Self.deleteStoredAccount()
    }

    #if DEBUG && targetEnvironment(simulator)
    func signInForSimulatorLocalUse() {
        let simulatorUserId = "simulator-local-\(Bundle.main.bundleIdentifier ?? "NoteLab")"
        let nextAccount = AppleAccount(
            appleUserId: simulatorUserId,
            email: nil,
            displayName: "Simulator Local",
            localUserId: Self.stableUUID(for: simulatorUserId)
        )
        account = nextAccount
        errorMessage = nil
        Self.store(account: nextAccount)
        Task { await refreshICloudAccountState() }
    }
    #endif

    func refreshICloudAccountState() async {
        iCloudState = await Self.currentICloudAccountState()
    }

    private func refreshAppleCredentialState() async {
        guard let account else { return }
        if account.isSimulatorLocalAccount { return }
        let state = await Self.credentialState(for: account.appleUserId)
        switch state {
        case .authorized, .transferred:
            return
        case .revoked, .notFound:
            signOut()
        @unknown default:
            return
        }
    }

    private static func currentICloudAccountState() async -> ICloudAccountState {
        await withCheckedContinuation { continuation in
            CloudKitSchema.container.accountStatus { status, _ in
                switch status {
                case .available:
                    continuation.resume(returning: .available)
                case .noAccount:
                    continuation.resume(returning: .noAccount)
                case .restricted:
                    continuation.resume(returning: .restricted)
                case .couldNotDetermine:
                    continuation.resume(returning: .couldNotDetermine)
                case .temporarilyUnavailable:
                    continuation.resume(returning: .temporarilyUnavailable)
                @unknown default:
                    continuation.resume(returning: .couldNotDetermine)
                }
            }
        }
    }

    private static func credentialState(for userId: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    private static func displayName(from components: PersonNameComponents) -> String? {
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func stableUUID(for appleUserId: String) -> UUID {
        StableIdentity.uuid(for: appleUserId)
    }
}

private extension AuthManager {
    static let keychainService = "com.psg.NoteLab.apple-auth"
    static let keychainAccount = "current-account"
    static let installMarkerKey = "AuthManager.didRecordInstall"

    static func loadStoredAccount() -> AppleAccount? {
        var query = baseKeychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AppleAccount.self, from: data)
    }

    static func store(account: AppleAccount) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        var query = baseKeychainQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteStoredAccount() {
        SecItemDelete(baseKeychainQuery() as CFDictionary)
    }

    static func baseKeychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }

    static var hasInstallMarker: Bool {
        UserDefaults.standard.bool(forKey: installMarkerKey)
    }

    static func markInstalled() {
        UserDefaults.standard.set(true, forKey: installMarkerKey)
    }

    static func hasLocalInstallData() -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: StorageController.appSupportURL,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return entries.contains { $0.lastPathComponent != ".DS_Store" }
    }
}

extension AuthManager {
    nonisolated static func shouldDiscardStoredAccountOnLaunch(
        hasStoredAccount: Bool,
        hasInstallMarker: Bool,
        hasLocalInstallData: Bool
    ) -> Bool {
        hasStoredAccount && !hasInstallMarker && !hasLocalInstallData
    }
}
