import Foundation
import Supabase
import Security

enum SupabaseManager {
    // Clear corrupted session before initializing client
    private static let _cleanupOnce: Void = {
        clearCorruptedSessionIfNeeded()
    }()
    
    nonisolated(unsafe) static let shared: SupabaseClient = {
        _ = _cleanupOnce // Ensure cleanup runs first
        return SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()
    
    /// Clear corrupted Supabase session data from Keychain
    /// This prevents "Could not cast value of type 'Swift.Optional<Any>' to 'Swift.String'" crashes
    private static func clearCorruptedSessionIfNeeded() {
        // Check if we've already attempted a cleanup in this app version
        let cleanupKey = "supabase.session.cleanup.v2"
        if UserDefaults.standard.bool(forKey: cleanupKey) {
            return
        }
        
        // Delete all Supabase-related Keychain items
        let keychainQueries: [[String: Any]] = [
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "supabase.gotrue.swift"
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.supabase"
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "supabase.auth.token"
            ]
        ]
        
        var didClear = false
        for query in keychainQueries {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess {
                didClear = true
                print("SupabaseManager: Cleared corrupted Supabase session from Keychain")
            }
        }
        
        // Mark cleanup as done AFTER completing it
        UserDefaults.standard.set(true, forKey: cleanupKey)
        if didClear {
            // Force UserDefaults to sync immediately
            UserDefaults.standard.synchronize()
        }
    }
}

