import Foundation
import Combine

struct AvatarOptions: Codable, Hashable {
    var avatarId: String
}

extension AvatarOptions {
    static func `default`(for userId: UUID?) -> AvatarOptions {
        if let userId, !allAvatarIds.isEmpty {
            let index = stableIndex(for: userId, modulo: allAvatarIds.count)
            return AvatarOptions(avatarId: allAvatarIds[index])
        }
        return AvatarOptions(avatarId: AvatarOptions.allAvatarIds.first ?? "avatar_01")
    }
}

extension AvatarOptions {
    static let allAvatarIds: [String] = [
        "avatar_01",
        "avatar_02",
        "avatar_03",
        "avatar_04",
        "avatar_05",
        "avatar_06",
        "avatar_07",
        "avatar_08",
        "avatar_09",
        "avatar_10",
        "avatar_11",
        "avatar_12"
    ]
}

extension AvatarOptions {
    static let emojiAvatars: [String] = [
        "😀",
        "😺",
        "🐶",
        "🦊",
        "🐼",
        "🐸",
        "🐵",
        "🐰",
        "🐨",
        "🐯",
        "🐷",
        "🐻"
    ]

    static func emoji(for avatarId: String) -> String? {
        guard let index = allAvatarIds.firstIndex(of: avatarId),
              index < emojiAvatars.count else {
            return nil
        }
        return emojiAvatars[index]
    }

    private static func stableIndex(for userId: UUID, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        var hash = 0
        for scalar in userId.uuidString.unicodeScalars {
            hash = (hash * 31 + Int(scalar.value)) % modulo
        }
        return hash
    }
}
