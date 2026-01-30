import Foundation
import SwiftUI
import Combine

@MainActor
final class AvatarStore: ObservableObject {
    @Published private(set) var options: AvatarOptions
    private(set) var userId: UUID?

    init(userId: UUID? = nil) {
        self.userId = userId
        self.options = AvatarOptions.default(for: userId)
        load()
    }

    func updateUserId(_ userId: UUID?) {
        guard self.userId != userId else { return }
        self.userId = userId
        load()
    }

    func setAvatarId(_ avatarId: String) {
        options = AvatarOptions(avatarId: avatarId)
        save()
    }

    func resetToDefault() {
        options = AvatarOptions.default(for: userId)
        save()
    }

    private func load() {
        let key = storageKey(for: userId)
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AvatarOptions.self, from: data) {
            options = decoded
        } else {
            options = AvatarOptions.default(for: userId)
        }
    }

    private func save() {
        let key = storageKey(for: userId)
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: key)
        }
        if let userId {
            SyncProfileCache.updateProfile(userId: userId) { payload in
                payload.avatarOptions = options
            }
        }
    }

    var availableAvatarIds: [String] {
        AvatarOptions.allAvatarIds
    }

    private func storageKey(for userId: UUID?) -> String {
        if let userId {
            return "avatar.options.\(userId.uuidString)"
        }
        return "avatar.options.guest"
    }
}
