import Foundation
import SwiftData
import CloudKit
import os

enum PersistenceController {
    // Note: "V2" store — intentionally renamed from "NoteLabCloudKitV1" to avoid
    // any stale iCloud daemon file-coordination locks that could cause ModelContainer
    // to hang on device. The old CloudKit-tagged store is left orphaned and cleaned
    // up by resetStore() when it gets a chance.
    private static let storeFileName = "NoteLabV2.store"
    private static let corruptionResetKey = "PersistenceController.didResetForCorruption"
    private static let logger = Logger(subsystem: "NoteLab", category: "Persistence")

    /// Exposed for diagnostic logging in ContentView.
    static var storeURL: URL {
        let directory = appSupportURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(storeFileName)
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            LocalNotebook.self,
            LocalNote.self,
            LocalAttachment.self,
            SyncMetadata.self
        ])

        // Explicitly disable CloudKit — the default is .automatic which picks up
        // the CloudKit entitlement and then fails because our schema uses
        // non-optional attributes, non-optional relationships, and unique
        // constraints, none of which CloudKit supports.
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        // Pre-flight: check whether the store directory is reachable.
        // A locked / unavailable ApplicationSupport directory is a hard failure.
        let storePath = storeURL.path
        logger.info("makeContainer: attempting store at \(storePath, privacy: .public)")
        let start = Date()

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            logger.info("makeContainer: success, elapsed=\(Date().timeIntervalSince(start), privacy: .public)s")
            return container
        } catch {
            logger.error("makeContainer: first attempt failed (\(error.localizedDescription, privacy: .public)), resetting store")
            do {
                try resetStore()
            } catch {
                logger.error("makeContainer: resetStore also failed (\(error.localizedDescription, privacy: .public))")
            }
            let retryStart = Date()
            let container = try ModelContainer(for: schema, configurations: [configuration])
            logger.info("makeContainer: retry success after reset, elapsed=\(Date().timeIntervalSince(retryStart), privacy: .public)s")
            return container
        }
    }

    nonisolated static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            LocalNotebook.self,
            LocalNote.self,
            LocalAttachment.self,
            SyncMetadata.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        logger.info("makeInMemoryContainer: creating in-memory container")
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Lightweight validation to ensure the store can be read
    static func validateStore(container: ModelContainer) throws {
        let context = ModelContext(container)
        var fetch = FetchDescriptor<SyncMetadata>()
        fetch.fetchLimit = 1
        _ = try context.fetch(fetch)
    }

    /// Reset the SwiftData store by deleting the database files.
    /// Logs every delete failure instead of silently skipping.
    static func resetStore() throws {
        let fileManager = FileManager.default

        for fileName in storeFileNamesToReset {
            let url = appSupportURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                    logger.info("resetStore: deleted \(fileName, privacy: .public)")
                } catch {
                    logger.error("resetStore: failed to delete \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    // Continue trying other files — don't let one stuck file block the others
                }
            } else {
                logger.debug("resetStore: \(fileName, privacy: .public) not present, skip")
            }
        }
    }

    private static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    /// File names to remove during a reset. Includes old CloudKit-tagged stores
    /// from prior app versions so they don't accumulate.
    private static var storeFileNamesToReset: [String] {
        [
            storeFileName,
            "\(storeFileName)-shm",
            "\(storeFileName)-wal",
            // Legacy stores from previous versions
            "NoteLabCloudKitV1.store",
            "NoteLabCloudKitV1.store-shm",
            "NoteLabCloudKitV1.store-wal",
            "default.store",
            "default.store-shm",
            "default.store-wal",
            "NoteLab.store",
            "NoteLab.store-shm",
            "NoteLab.store-wal"
        ]
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
