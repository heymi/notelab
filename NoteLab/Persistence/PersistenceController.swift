import Foundation
import SwiftData

enum PersistenceController {
    private static let storeFileName = "NoteLab.store"
    private static let corruptionResetKey = "PersistenceController.didResetForCorruption"
    
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LocalNotebook.self,
            LocalNote.self,
            LocalAttachment.self,
            SyncMetadata.self
        ])

        // Stored on-device; SwiftData handles file location.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // If container creation fails, try to reset the store
            print("SwiftData container creation failed: \(error.localizedDescription)")
            print("Attempting to reset the store...")
            try? resetStore()
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    /// Lightweight validation to ensure the store can be read
    static func validateStore(container: ModelContainer) throws {
        let context = ModelContext(container)
        var fetch = FetchDescriptor<SyncMetadata>()
        fetch.fetchLimit = 1
        _ = try context.fetch(fetch)
    }
    
    /// Reset the SwiftData store by deleting the database files
    static func resetStore() throws {
        let fileManager = FileManager.default
        
        // Get the Application Support directory
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        // SwiftData stores files in Application Support/default.store by default
        let storeURL = appSupportURL.appendingPathComponent("default.store")
        
        // Delete all files related to the store
        if fileManager.fileExists(atPath: storeURL.path) {
            try fileManager.removeItem(at: storeURL)
            print("SwiftData store deleted at: \(storeURL.path)")
        }
        
        // Also try common variations
        let variations = [
            "default.store",
            "default.store-shm",
            "default.store-wal"
        ]
        
        for variation in variations {
            let url = appSupportURL.appendingPathComponent(variation)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }
    
    /// Check if the store needs to be reset (e.g., due to schema changes)
    static var shouldResetStore: Bool {
        get {
            UserDefaults.standard.bool(forKey: "PersistenceController.shouldResetStore")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "PersistenceController.shouldResetStore")
        }
    }
    
    static var didResetForCorruption: Bool {
        get {
            UserDefaults.standard.bool(forKey: corruptionResetKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: corruptionResetKey)
        }
    }
}

