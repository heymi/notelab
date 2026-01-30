import Foundation

final class AIResponseCache {
    static let shared = AIResponseCache()
    private let defaults = UserDefaults.standard
    private let updatedSuffix = ".updatedAt"

    func load<T: Codable>(key: String, maxAge: TimeInterval) -> T? {
        guard let data = defaults.data(forKey: key),
              let updatedAt = defaults.object(forKey: key + updatedSuffix) as? TimeInterval,
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        let age = Date().timeIntervalSince1970 - updatedAt
        if age > maxAge {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: key + updatedSuffix)
            return nil
        }
        return value
    }

    func save<T: Codable>(key: String, value: T) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
            defaults.set(Date().timeIntervalSince1970, forKey: key + updatedSuffix)
        }
    }

    func updatedAt(key: String) -> Date? {
        let value = defaults.object(forKey: key + updatedSuffix) as? TimeInterval
        return value.map { Date(timeIntervalSince1970: $0) }
    }

    func isValid(key: String, maxAge: TimeInterval) -> Bool {
        guard defaults.data(forKey: key) != nil,
              let updatedAt = defaults.object(forKey: key + updatedSuffix) as? TimeInterval else {
            return false
        }
        let age = Date().timeIntervalSince1970 - updatedAt
        return age <= maxAge
    }

    func clear(key: String) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + updatedSuffix)
    }
}
