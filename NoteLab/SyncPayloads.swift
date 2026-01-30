import Foundation

struct PreferencesPayload: Codable, Hashable {
    var appearanceMode: Int?
    var launchPage: String?
    var aiProvider: String?
}

struct RecentFocusPayload: Codable, Hashable {
    var markdown: String?
    var updatedAt: Date?
}

struct UserProfilePayload: Codable, Hashable {
    var avatarOptions: AvatarOptions?
    var preferences: PreferencesPayload
    var recentFocus: RecentFocusPayload?

    static func empty() -> UserProfilePayload {
        UserProfilePayload(
            avatarOptions: nil,
            preferences: PreferencesPayload(appearanceMode: nil, launchPage: nil, aiProvider: nil),
            recentFocus: nil
        )
    }
}

struct WhiteboardPayload: Codable, Hashable {
    var title: String
    var content: String
    var contentRTFBase64: String?
    var linkBlocksJSON: String?
    var linkOffsetX: Double?
    var linkOffsetY: Double?

    var contentRTFData: Data? {
        guard let contentRTFBase64 else { return nil }
        return Data(base64Encoded: contentRTFBase64)
    }

    var linkBlocksData: Data? {
        guard let linkBlocksJSON else { return nil }
        return linkBlocksJSON.data(using: .utf8)
    }

    static func from(
        title: String,
        content: String,
        contentRTF: Data?,
        linkBlocksJSON: String?,
        linkOffsetX: Double?,
        linkOffsetY: Double?
    ) -> WhiteboardPayload {
        WhiteboardPayload(
            title: title,
            content: content,
            contentRTFBase64: contentRTF?.base64EncodedString(),
            linkBlocksJSON: linkBlocksJSON,
            linkOffsetX: linkOffsetX,
            linkOffsetY: linkOffsetY
        )
    }
}

struct LocalProfileCache: Codable {
    var payload: UserProfilePayload
    var updatedAt: Date
    var isDirty: Bool
}

struct LocalWhiteboardCache: Codable {
    var payload: WhiteboardPayload
    var updatedAt: Date
    var isDirty: Bool
}

enum SyncProfileCache {
    private static let profilePrefix = "sync.user_profile.cache."
    private static let whiteboardPrefix = "sync.whiteboard.cache."

    static func loadProfile(userId: UUID) -> LocalProfileCache? {
        guard let data = UserDefaults.standard.data(forKey: profileKey(userId)) else { return nil }
        return decode(LocalProfileCache.self, from: data)
    }

    static func saveProfile(userId: UUID, cache: LocalProfileCache) {
        if let data = encode(cache) {
            UserDefaults.standard.set(data, forKey: profileKey(userId))
        }
    }

    static func updateProfile(userId: UUID, update: (inout UserProfilePayload) -> Void) {
        var cache = loadProfile(userId: userId) ?? LocalProfileCache(
            payload: UserProfilePayload.empty(),
            updatedAt: Date.distantPast,
            isDirty: false
        )
        update(&cache.payload)
        cache.updatedAt = Date()
        cache.isDirty = true
        saveProfile(userId: userId, cache: cache)
    }

    static func loadWhiteboard(userId: UUID) -> LocalWhiteboardCache? {
        guard let data = UserDefaults.standard.data(forKey: whiteboardKey(userId)) else { return nil }
        return decode(LocalWhiteboardCache.self, from: data)
    }

    static func saveWhiteboard(userId: UUID, cache: LocalWhiteboardCache) {
        if let data = encode(cache) {
            UserDefaults.standard.set(data, forKey: whiteboardKey(userId))
        }
    }

    static func updateWhiteboard(userId: UUID, update: (inout WhiteboardPayload) -> Void) {
        var cache = loadWhiteboard(userId: userId) ?? LocalWhiteboardCache(
            payload: WhiteboardPayload(
                title: "白板",
                content: "",
                contentRTFBase64: nil,
                linkBlocksJSON: nil,
                linkOffsetX: nil,
                linkOffsetY: nil
            ),
            updatedAt: Date.distantPast,
            isDirty: false
        )
        update(&cache.payload)
        cache.updatedAt = Date()
        cache.isDirty = true
        saveWhiteboard(userId: userId, cache: cache)
    }

    private static func profileKey(_ userId: UUID) -> String {
        profilePrefix + userId.uuidString
    }

    private static func whiteboardKey(_ userId: UUID) -> String {
        whiteboardPrefix + userId.uuidString
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
