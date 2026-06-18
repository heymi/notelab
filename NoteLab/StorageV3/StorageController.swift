import CoreData
import Foundation
import os

enum StorageError: LocalizedError {
    case storeOpenFailed(String)
    case missingProfile
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeOpenFailed(let message):
            return "本地数据库打开失败：\(message)"
        case .missingProfile:
            return "当前账号本地 profile 不存在"
        case .saveFailed(let message):
            return "本地保存失败：\(message)"
        }
    }
}
final class StorageController {
    static let shared = StorageController()

    static let storageVersion = 3
    static let storeFileName = "NoteLabStorageV3.sqlite"

    let container: NSPersistentContainer
    private(set) var openError: Error?

    private let logger = Logger(subsystem: "NoteLab", category: "StorageV3")

    var mainContext: NSManagedObjectContext {
        container.viewContext
    }

    var isAvailable: Bool {
        openError == nil
    }

    private init() {
        let model = StorageModelFactory.makeModel()
        container = NSPersistentContainer(name: "NoteLabStorageV3", managedObjectModel: model)

        let storeURL = Self.storeURL
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { [weak self] _, error in
            if let error {
                self?.openError = error
                self?.logger.error("Storage v3 open failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.logger.info("Storage v3 opened at \(storeURL.path, privacy: .public)")
            }
            semaphore.signal()
        }
        semaphore.wait()

        container.viewContext.name = "NoteLabStorageV3.main"
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    static var storeURL: URL {
        appSupportURL.appendingPathComponent(storeFileName)
    }

    static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var attachmentsOriginalsURL: URL {
        appSupportURL
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("originals", isDirectory: true)
    }

    func makeBackgroundContext(name: String = "NoteLabStorageV3.background") -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.name = name
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    func saveMainContext(file: StaticString = #fileID, line: UInt = #line) throws {
        let context = mainContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("main context save failed at \(String(describing: file), privacy: .public):\(line, privacy: .public) \(error.localizedDescription, privacy: .public)")
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }
}
