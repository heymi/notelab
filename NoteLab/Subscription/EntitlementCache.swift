//
//  EntitlementCache.swift
//  NoteLab
//
//  使用 Keychain 安全存储订阅权益缓存
//

import Foundation
import Security

/// 权益缓存管理器，使用 Keychain 安全存储
final class EntitlementCache {
    
    // MARK: - Constants
    
    private let service = "com.notelab.entitlement"
    private let tierKey = "subscription.tier"
    private let expirationKey = "subscription.expiration"
    private let lastVerifiedKey = "subscription.lastVerified"
    private let entitlementCredentialKey = "subscription.entitlementCredential"
    #if DEBUG
    private let debugSubscriptionTokenKey = "subscription.debugToken"
    #endif
    
    // MARK: - Singleton
    
    static let shared = EntitlementCache()
    
    private init() {}
    
    // MARK: - Public API
    
    /// 从缓存读取订阅等级
    var cachedTier: SubscriptionTier {
        guard let data = readKeychain(key: tierKey),
              let rawString = String(data: data, encoding: .utf8),
              let rawValue = Int(rawString),
              let tier = SubscriptionTier(rawValue: rawValue) else {
            return .free
        }
        
        // 检查是否过期
        if let expData = readKeychain(key: expirationKey),
           let expString = String(data: expData, encoding: .utf8),
           let expInterval = TimeInterval(expString) {
            let expDate = Date(timeIntervalSince1970: expInterval)
            if expDate < Date() {
                // 已过期，返回免费版
                return .free
            }
        }
        
        return tier
    }
    
    /// 缓存的过期时间
    var cachedExpiration: Date? {
        guard let data = readKeychain(key: expirationKey),
              let expString = String(data: data, encoding: .utf8),
              let expInterval = TimeInterval(expString) else {
            return nil
        }
        return Date(timeIntervalSince1970: expInterval)
    }
    
    /// 上次验证时间
    var lastVerifiedDate: Date? {
        guard let data = readKeychain(key: lastVerifiedKey),
              let dateString = String(data: data, encoding: .utf8),
              let interval = TimeInterval(dateString) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    var cachedEntitlementCredential: String? {
        guard cachedTier > .free,
              let data = readKeychain(key: entitlementCredentialKey),
              let credential = String(data: data, encoding: .utf8),
              !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return credential
    }
    
    /// 缓存订阅等级和过期时间
    func cacheTier(_ tier: SubscriptionTier, expiration: Date?) {
        // 存储等级
        let tierData = String(tier.rawValue).data(using: .utf8)!
        writeKeychain(key: tierKey, data: tierData)
        
        // 存储过期时间
        if let exp = expiration {
            let expData = String(exp.timeIntervalSince1970).data(using: .utf8)!
            writeKeychain(key: expirationKey, data: expData)
        } else {
            deleteKeychain(key: expirationKey)
        }
        
        // 更新验证时间
        let nowData = String(Date().timeIntervalSince1970).data(using: .utf8)!
        writeKeychain(key: lastVerifiedKey, data: nowData)
    }

    func cacheEntitlementCredential(_ credential: String?) {
        guard let credential,
              !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        writeKeychain(key: entitlementCredentialKey, data: Data(credential.utf8))
    }

    #if DEBUG
    var cachedDebugSubscriptionToken: String? {
        guard let data = readKeychain(key: debugSubscriptionTokenKey),
              let token = String(data: data, encoding: .utf8),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }

    func cacheDebugSubscriptionToken(_ token: String) {
        writeKeychain(key: debugSubscriptionTokenKey, data: Data(token.utf8))
    }
    #endif
    
    /// 清除所有缓存
    func clearCache() {
        deleteKeychain(key: tierKey)
        deleteKeychain(key: expirationKey)
        deleteKeychain(key: lastVerifiedKey)
        deleteKeychain(key: entitlementCredentialKey)
        #if DEBUG
        deleteKeychain(key: debugSubscriptionTokenKey)
        #endif
    }
    
    /// 检查是否需要重新验证（超过24小时）
    var needsRevalidation: Bool {
        guard let lastVerified = lastVerifiedDate else {
            return true
        }
        let hoursSinceVerification = Date().timeIntervalSince(lastVerified) / 3600
        return hoursSinceVerification > 24
    }
    
    // MARK: - Keychain Operations
    
    private func writeKeychain(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // 先删除已存在的项
        SecItemDelete(query as CFDictionary)
        
        // 添加新项
        var newQuery = query
        newQuery[kSecValueData as String] = data
        
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("EntitlementCache: Failed to write keychain key '\(key)', status: \(status)")
        }
    }
    
    private func readKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
    
    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
