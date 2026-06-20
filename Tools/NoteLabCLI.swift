#!/usr/bin/env swift
import CoreData
import Foundation

private let storeFileName = "NoteLabStorageV3.sqlite"
private let bundleIdentifier = "com.psg.NoteLab"

private struct CLIError: Error, CustomStringConvertible {
    let description: String
}

private struct GlobalOptions {
    var storePath: String?
    var serviceURL: String = "http://127.0.0.1:47719"
    var profileId: String?
    var query: String?
    var outputPath: String?
    var notebookId: String?
    var title: String?
    var content: String?
    var contentFile: String?
    var filePath: String?
    var mimeType: String?
    var color: String?
    var iconName: String?
    var notebookDescription: String?
    var agentToken: String?
    var limit: Int = 50
    var includeDeleted = false
    var write = false
    var appendMarkdown = true
}

private struct CommandLineParser {
    let command: [String]
    let options: GlobalOptions

    init(arguments: [String]) throws {
        var command: [String] = []
        var options = GlobalOptions(agentToken: ProcessInfo.processInfo.environment["NOTELAB_AGENT_TOKEN"])
        var index = 0

        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--store":
                options.storePath = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--service-url":
                options.serviceURL = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--profile":
                options.profileId = try Self.value(after: arg, arguments: arguments, index: &index).lowercased()
            case "--query", "-q":
                options.query = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--output", "-o":
                options.outputPath = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--notebook":
                options.notebookId = try Self.value(after: arg, arguments: arguments, index: &index).lowercased()
            case "--title":
                options.title = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--content":
                options.content = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--content-file":
                options.contentFile = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--file":
                options.filePath = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--mime-type":
                options.mimeType = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--color":
                options.color = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--icon":
                options.iconName = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--description":
                options.notebookDescription = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--agent-token":
                options.agentToken = try Self.value(after: arg, arguments: arguments, index: &index)
            case "--limit":
                let raw = try Self.value(after: arg, arguments: arguments, index: &index)
                guard let limit = Int(raw), limit > 0 else {
                    throw CLIError(description: "--limit must be a positive integer")
                }
                options.limit = limit
            case "--include-deleted":
                options.includeDeleted = true
            case "--write":
                options.write = true
            case "--no-append-markdown":
                options.appendMarkdown = false
            case "--json":
                break
            case "--help", "-h", "help":
                command = ["help"]
            default:
                command.append(arg)
            }
            index += 1
        }

        self.command = command.isEmpty ? ["help"] : command
        self.options = options
    }

    private static func value(after flag: String, arguments: [String], index: inout Int) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            throw CLIError(description: "\(flag) requires a value")
        }
        index = nextIndex
        return arguments[nextIndex]
    }
}

private struct ProfileDTO: Codable {
    let id: String
    let displayEmail: String?
    let displayName: String?
    let createdAt: String
    let updatedAt: String
    let isLocked: Bool
}

private struct NotebookDTO: Codable {
    let id: String
    let profileId: String
    let title: String
    let color: String
    let iconName: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let isPinned: Bool
    let noteCount: Int?
}

private struct NoteDTO: Codable {
    let id: String
    let profileId: String
    let notebookId: String
    let title: String
    let summary: String
    let content: String
    let paragraphCount: Int
    let bulletCount: Int
    let hasAdditionalContext: Bool
    let createdAt: String
    let updatedAt: String
    let isPinned: Bool
    let attachments: [AttachmentDTO]?
}

private struct AttachmentDTO: Codable {
    let id: String
    let profileId: String
    let noteId: String
    let storagePath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
    let originalPath: String?
    let createdAt: String
    let updatedAt: String
    let isUploaded: Bool
    let missingLocalFile: Bool
    let localFilePath: String?
}

private struct ResourceSummaryDTO: Codable {
    let storePath: String
    let profiles: Int
    let notebooks: Int
    let notes: Int
    let attachments: Int
}

private struct StoreCandidateDTO: Codable {
    let path: String
    let exists: Bool
}

private struct CreateNoteRequest: Encodable {
    let notebookId: String
    let profileId: String?
    let title: String?
    let content: String?
}

private struct AppendNoteRequest: Encodable {
    let profileId: String?
    let content: String
}

private struct AddAttachmentRequest: Encodable {
    let profileId: String?
    let fileName: String
    let mimeType: String?
    let dataBase64: String
    let appendMarkdown: Bool
}

private struct CreateNotebookRequest: Encodable {
    let profileId: String?
    let title: String
    let color: String?
    let iconName: String?
}

private struct UpdateNotebookRequest: Encodable {
    let profileId: String?
    let title: String?
    let color: String?
    let iconName: String?
    let description: String?
}

private struct UpdateNoteRequest: Encodable {
    let profileId: String?
    let notebookId: String?
    let title: String?
    let content: String?
}

private struct ContentUpdateRequest: Encodable {
    let profileId: String?
    let content: String
}

private struct ScopedWriteRequest: Encodable {
    let profileId: String?
}

private enum JSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func printValue<T: Encodable>(_ value: T) throws {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private struct AgentServiceUnavailable: Error {}

private final class AgentServiceClient {
    private let baseURL: URL

    init(baseURL: String) throws {
        guard let url = URL(string: baseURL) else {
            throw CLIError(description: "Invalid --service-url \(baseURL)")
        }
        self.baseURL = url
    }

    func run(command: [String], options: GlobalOptions) throws -> Bool {
        switch command {
        case ["profiles", "list"]:
            try printJSON(path: "/profiles", options: options)
        case ["notebooks", "list"]:
            try printJSON(path: "/notebooks", options: options)
        case ["notebooks", "create"]:
            try requireWrite(options)
            guard let title = options.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                throw CLIError(description: "notebooks create requires --title TEXT")
            }
            try printJSON(
                path: "/notebooks",
                options: options,
                body: CreateNotebookRequest(
                    profileId: options.profileId,
                    title: title,
                    color: options.color,
                    iconName: options.iconName
                )
            )
        case let command where command.count == 3 && command[0] == "notebooks" && command[1] == "read":
            try printJSON(path: "/notebooks/\(command[2])", options: options)
        case let command where command.count == 3 && command[0] == "notebooks" && command[1] == "update":
            try requireWrite(options)
            try printJSON(
                path: "/notebooks/\(command[2])/update",
                options: options,
                body: UpdateNotebookRequest(
                    profileId: options.profileId,
                    title: options.title,
                    color: options.color,
                    iconName: options.iconName,
                    description: options.notebookDescription
                )
            )
        case let command where command.count == 3 && command[0] == "notebooks" && command[1] == "delete":
            try requireWrite(options)
            try printJSON(path: "/notebooks/\(command[2])/delete", options: options, body: ScopedWriteRequest(profileId: options.profileId))
        case ["notes", "list"]:
            try printJSON(path: "/notes", options: options)
        case ["notes", "search"]:
            guard let query = options.query, !query.isEmpty else {
                throw CLIError(description: "notes search requires --query TEXT")
            }
            try printJSON(path: "/notes/search", options: options, extra: ["query": query])
        case ["notes", "create"]:
            try requireWrite(options)
            guard let notebookId = options.notebookId else {
                throw CLIError(description: "notes create requires --notebook NOTEBOOK_ID")
            }
            try printJSON(
                path: "/notes",
                options: options,
                body: CreateNoteRequest(
                    notebookId: notebookId,
                    profileId: options.profileId,
                    title: options.title,
                    content: try readContent(options)
                )
            )
        case let command where command.count == 3 && command[0] == "notes" && command[1] == "read":
            guard command.count == 3 else {
                throw CLIError(description: "notes read requires NOTE_ID")
            }
            try printJSON(path: "/notes/\(command[2])", options: options)
        case let command where command.count == 3 && command[0] == "notes" && command[1] == "update":
            try requireWrite(options)
            try printJSON(
                path: "/notes/\(command[2])/update",
                options: options,
                body: UpdateNoteRequest(
                    profileId: options.profileId,
                    notebookId: options.notebookId,
                    title: options.title,
                    content: options.contentFile != nil || options.content != nil ? try readContent(options) : nil
                )
            )
        case let command where command.count == 3 && command[0] == "notes" && command[1] == "append":
            try requireWrite(options)
            let content = try readContent(options)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError(description: "notes append requires --content TEXT or --content-file PATH")
            }
            try printJSON(
                path: "/notes/\(command[2])/append",
                options: options,
                body: AppendNoteRequest(profileId: options.profileId, content: content)
            )
        case let command where command.count == 3 && command[0] == "notes" && command[1] == "delete":
            try requireWrite(options)
            try printJSON(path: "/notes/\(command[2])/delete", options: options, body: ScopedWriteRequest(profileId: options.profileId))
        case let command where command.count == 3 && command[0] == "content" && command[1] == "read":
            try printJSON(path: "/notes/\(command[2])/content", options: options)
        case let command where command.count == 3 && command[0] == "content" && command[1] == "update":
            try requireWrite(options)
            try printJSON(
                path: "/notes/\(command[2])/content",
                options: options,
                body: ContentUpdateRequest(profileId: options.profileId, content: try readContent(options))
            )
        case let command where command.count == 3 && command[0] == "content" && command[1] == "append":
            try requireWrite(options)
            try printJSON(
                path: "/notes/\(command[2])/content/append",
                options: options,
                body: AppendNoteRequest(profileId: options.profileId, content: try readContent(options))
            )
        case let command where command.count == 3 && command[0] == "content" && command[1] == "clear":
            try requireWrite(options)
            try printJSON(path: "/notes/\(command[2])/content/delete", options: options, body: ScopedWriteRequest(profileId: options.profileId))
        case let command where command.count >= 2 && command[0] == "attachments" && command[1] == "list":
            try printJSON(path: "/attachments", options: options, extra: command.count >= 3 ? ["noteId": command[2]] : [:])
        case let command where command.count == 3 && command[0] == "attachments" && command[1] == "export":
            guard command.count == 3 else {
                throw CLIError(description: "attachments export requires ATTACHMENT_ID")
            }
            try exportAttachment(command[2], options: options)
        case let command where command.count == 3 && command[0] == "attachments" && command[1] == "add":
            try requireWrite(options)
            guard let filePath = options.filePath else {
                throw CLIError(description: "attachments add requires --file PATH")
            }
            let fileURL = URL(fileURLWithPath: NSString(string: filePath).expandingTildeInPath)
            let data = try Data(contentsOf: fileURL)
            try printJSON(
                path: "/notes/\(command[2])/attachments",
                options: options,
                body: AddAttachmentRequest(
                    profileId: options.profileId,
                    fileName: fileURL.lastPathComponent,
                    mimeType: options.mimeType,
                    dataBase64: data.base64EncodedString(),
                    appendMarkdown: options.appendMarkdown
                )
            )
        case ["resources", "list"]:
            try printJSON(path: "/resources", options: options)
        default:
            return false
        }
        return true
    }

    private func printJSON(path: String, options: GlobalOptions, extra: [String: String] = [:]) throws {
        let response = try request(path: path, options: options, extra: extra)
        FileHandle.standardOutput.write(response.data)
        if response.data.last != UInt8(ascii: "\n") {
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private func printJSON<T: Encodable>(path: String, options: GlobalOptions, body: T) throws {
        let bodyData = try JSON.encoder.encode(body)
        let response = try request(path: path, options: options, method: "POST", body: bodyData)
        FileHandle.standardOutput.write(response.data)
        if response.data.last != UInt8(ascii: "\n") {
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private func exportAttachment(_ id: String, options: GlobalOptions) throws {
        let response = try request(path: "/attachments/\(id)/data", options: options)
        let fileName = response.headers["X-NoteLab-Filename"] ?? "\(id).bin"
        let destination: URL
        if let outputPath = options.outputPath {
            let outputURL = URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                destination = outputURL.appendingPathComponent(fileName)
            } else {
                destination = outputURL
            }
        } else {
            destination = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try response.data.write(to: destination, options: [.atomic])
        try JSON.printValue(["id": id, "fileName": fileName, "path": destination.path])
    }

    private func request(
        path: String,
        options: GlobalOptions,
        extra: [String: String] = [:],
        method: String = "GET",
        body: Data? = nil
    ) throws -> (data: Data, headers: [String: String]) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = []
        if let profile = options.profileId {
            items.append(URLQueryItem(name: "profile", value: profile))
        }
        if let notebook = options.notebookId {
            items.append(URLQueryItem(name: "notebook", value: notebook))
        }
        if options.includeDeleted {
            items.append(URLQueryItem(name: "includeDeleted", value: "true"))
        }
        items.append(URLQueryItem(name: "limit", value: "\(options.limit)"))
        for (key, value) in extra {
            items.append(URLQueryItem(name: key, value: value))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw CLIError(description: "Could not build service URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = path.hasSuffix("/data") || method == "POST" ? 60 : 5
        if let token = options.agentToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-NoteLab-Agent-Key")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Data, HTTPURLResponse), Error>!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                result = .failure(CLIError(description: "Invalid response from NoteLab agent service"))
                return
            }
            result = .success((data, http))
        }.resume()
        semaphore.wait()

        do {
            let (data, http) = try result.get()
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw CLIError(description: "NoteLab agent service returned \(http.statusCode): \(body)")
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            return (data, headers)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            throw AgentServiceUnavailable()
        }
    }

    private func requireWrite(_ options: GlobalOptions) throws {
        guard options.write else {
            throw CLIError(description: "write commands require --write")
        }
    }

    private func readContent(_ options: GlobalOptions) throws -> String {
        if let contentFile = options.contentFile {
            let url = URL(fileURLWithPath: NSString(string: contentFile).expandingTildeInPath)
            return try String(contentsOf: url, encoding: .utf8)
        }
        return options.content ?? ""
    }
}

private final class NoteLabStore {
    private let container: NSPersistentContainer
    let storeURL: URL

    init(path: String?) throws {
        storeURL = try Self.resolveStoreURL(path: path)
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "NoteLabStorageV3", managedObjectModel: model)

        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let loadError {
            throw CLIError(description: "Failed to open NoteLab store at \(storeURL.path): \(loadError.localizedDescription)")
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = false
    }

    var context: NSManagedObjectContext {
        container.viewContext
    }

    static func storeCandidates() -> [URL] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = [
            home.appendingPathComponent("Library/Application Support/\(storeFileName)"),
            home.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/\(storeFileName)")
        ]

        let containersURL = home.appendingPathComponent("Library/Containers")
        if let entries = try? fileManager.contentsOfDirectory(at: containersURL, includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.contains("NoteLab") || entry.lastPathComponent.contains(bundleIdentifier) {
                candidates.append(entry.appendingPathComponent("Data/Library/Application Support/\(storeFileName)"))
            }
        }

        return Array(NSOrderedSet(array: candidates).compactMap { $0 as? URL })
    }

    private static func resolveStoreURL(path: String?) throws -> URL {
        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CLIError(description: "Store does not exist at \(url.path)")
            }
            return url
        }

        if let existing = storeCandidates().first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }

        let searched = storeCandidates().map(\.path).joined(separator: "\n")
        throw CLIError(description: "Could not find \(storeFileName). Run `Tools/notelab stores` or pass --store PATH.\nSearched:\n\(searched)")
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            userProfile(),
            notebook(),
            note(),
            attachment(),
            voiceNote(),
            outbox(),
            syncState(),
            tombstone()
        ]
        return model
    }

    private static func userProfile() -> NSEntityDescription {
        entity("UserProfileEntity", properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("appleUserHash", .stringAttributeType, optional: false),
            attr("displayEmail", .stringAttributeType),
            attr("displayName", .stringAttributeType),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("updatedAt", .dateAttributeType, optional: false),
            attr("isLocked", .booleanAttributeType, optional: false, defaultValue: false)
        ], uniqueness: [["id"]])
    }

    private static func notebook() -> NSEntityDescription {
        entity("NotebookEntity", properties: commonScopedProperties() + [
            attr("title", .stringAttributeType, optional: false),
            attr("colorRaw", .stringAttributeType, optional: false),
            attr("iconName", .stringAttributeType, optional: false),
            attr("notebookDescription", .stringAttributeType, optional: false, defaultValue: ""),
            attr("isPinned", .booleanAttributeType, optional: false, defaultValue: false)
        ], uniqueness: [["profileId", "id"]])
    }

    private static func note() -> NSEntityDescription {
        entity("NoteEntity", properties: commonScopedProperties() + [
            attr("notebookId", .stringAttributeType, optional: false, indexed: true),
            attr("title", .stringAttributeType, optional: false),
            attr("summary", .stringAttributeType, optional: false, defaultValue: ""),
            attr("paragraphCount", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("bulletCount", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("hasAdditionalContext", .booleanAttributeType, optional: false, defaultValue: false),
            attr("version", .integer64AttributeType, optional: false, defaultValue: 1),
            attr("contentRTF", .binaryDataAttributeType),
            attr("content", .stringAttributeType, optional: false, defaultValue: ""),
            attr("isPinned", .booleanAttributeType, optional: false, defaultValue: false),
            attr("conflictParentId", .stringAttributeType)
        ], uniqueness: [["profileId", "id"]])
    }

    private static func attachment() -> NSEntityDescription {
        entity("AttachmentEntity", properties: commonScopedProperties() + [
            attr("noteId", .stringAttributeType, optional: false, indexed: true),
            attr("storagePath", .stringAttributeType, optional: false),
            attr("fileName", .stringAttributeType, optional: false),
            attr("mimeType", .stringAttributeType, optional: false),
            attr("fileSize", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("originalPath", .stringAttributeType),
            attr("missingLocalFile", .booleanAttributeType, optional: false, defaultValue: false),
            attr("isUploaded", .booleanAttributeType, optional: false, defaultValue: false)
        ], uniqueness: [["profileId", "id"]])
    }

    private static func voiceNote() -> NSEntityDescription {
        entity("VoiceNoteEntity", properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("noteId", .stringAttributeType, optional: false, indexed: true),
            attr("notebookId", .stringAttributeType, optional: false, indexed: true),
            attr("audioAttachmentId", .stringAttributeType, optional: false, indexed: true),
            attr("audioStoragePath", .stringAttributeType, optional: false),
            attr("audioFileName", .stringAttributeType, optional: false),
            attr("duration", .doubleAttributeType, optional: false, defaultValue: 0),
            attr("statusRaw", .stringAttributeType, optional: false, indexed: true),
            attr("rawTranscript", .stringAttributeType, optional: false, defaultValue: ""),
            attr("errorMessage", .stringAttributeType),
            attr("retryCount", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("updatedAt", .dateAttributeType, optional: false)
        ], uniqueness: [["profileId", "id"], ["profileId", "noteId"]])
    }

    private static func outbox() -> NSEntityDescription {
        entity("SyncOutboxEntity", properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("entityType", .stringAttributeType, optional: false, indexed: true),
            attr("entityId", .stringAttributeType, optional: false, indexed: true),
            attr("operation", .stringAttributeType, optional: false),
            attr("payload", .binaryDataAttributeType),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("updatedAt", .dateAttributeType, optional: false),
            attr("retryCount", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("lastError", .stringAttributeType),
            attr("status", .stringAttributeType, optional: false, indexed: true)
        ], uniqueness: [["id"]])
    }

    private static func syncState() -> NSEntityDescription {
        entity("SyncStateEntity", properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("iCloudAccountHash", .stringAttributeType, optional: false),
            attr("zoneName", .stringAttributeType, optional: false),
            attr("changeTokenData", .binaryDataAttributeType),
            attr("updatedAt", .dateAttributeType, optional: false)
        ], uniqueness: [["id"]])
    }

    private static func tombstone() -> NSEntityDescription {
        entity("TombstoneEntity", properties: [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("entityType", .stringAttributeType, optional: false, indexed: true),
            attr("entityId", .stringAttributeType, optional: false, indexed: true),
            attr("deletedAt", .dateAttributeType, optional: false),
            attr("expiresAt", .dateAttributeType, optional: false),
            attr("localRevision", .integer64AttributeType, optional: false, defaultValue: 1)
        ], uniqueness: [["profileId", "entityType", "entityId"]])
    }

    private static func commonScopedProperties() -> [NSPropertyDescription] {
        [
            attr("id", .stringAttributeType, optional: false, indexed: true),
            attr("profileId", .stringAttributeType, optional: false, indexed: true),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("updatedAt", .dateAttributeType, optional: false, indexed: true),
            attr("deletedAt", .dateAttributeType),
            attr("localRevision", .integer64AttributeType, optional: false, defaultValue: 1),
            attr("lastSyncedHash", .stringAttributeType),
            attr("deviceId", .stringAttributeType, optional: false)
        ]
    }

    private static func entity(_ name: String, properties: [NSPropertyDescription], uniqueness: [[String]]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = properties
        entity.uniquenessConstraints = uniqueness
        return entity
    }

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = true,
        indexed: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        attr.setValue(indexed, forKey: "indexed")
        attr.defaultValue = defaultValue
        return attr
    }
}

private final class NoteLabReader {
    private let store: NoteLabStore
    private let context: NSManagedObjectContext

    init(store: NoteLabStore) {
        self.store = store
        self.context = store.context
    }

    func profiles() throws -> [ProfileDTO] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserProfileEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return try context.fetch(request).map { object in
            ProfileDTO(
                id: string(object, "id"),
                displayEmail: optionalString(object, "displayEmail"),
                displayName: optionalString(object, "displayName"),
                createdAt: isoDate(object, "createdAt"),
                updatedAt: isoDate(object, "updatedAt"),
                isLocked: bool(object, "isLocked")
            )
        }
    }

    func notebooks(options: GlobalOptions) throws -> [NotebookDTO] {
        let noteCounts = try countNotesByNotebook(options: options)
        let request = NSFetchRequest<NSManagedObject>(entityName: "NotebookEntity")
        request.predicate = scopedPredicate(options: options)
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.fetchLimit = options.limit
        return try context.fetch(request).map { object in
            NotebookDTO(
                id: string(object, "id"),
                profileId: string(object, "profileId"),
                title: string(object, "title"),
                color: string(object, "colorRaw"),
                iconName: string(object, "iconName"),
                description: string(object, "notebookDescription"),
                createdAt: isoDate(object, "createdAt"),
                updatedAt: isoDate(object, "updatedAt"),
                isPinned: bool(object, "isPinned"),
                noteCount: noteCounts[string(object, "id"), default: 0]
            )
        }
    }

    func notes(options: GlobalOptions, query: String? = nil, id: String? = nil) throws -> [NoteDTO] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "NoteEntity")
        request.predicate = notesPredicate(options: options, query: query, id: id)
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]
        request.fetchLimit = id == nil ? options.limit : 1
        let notes = try context.fetch(request)
        let attachmentsByNote = try attachmentsByNote(noteIds: Set(notes.map { string($0, "id") }), options: options)
        return notes.map { object in
            let noteId = string(object, "id")
            return NoteDTO(
                id: noteId,
                profileId: string(object, "profileId"),
                notebookId: string(object, "notebookId"),
                title: string(object, "title"),
                summary: string(object, "summary"),
                content: string(object, "content"),
                paragraphCount: int(object, "paragraphCount"),
                bulletCount: int(object, "bulletCount"),
                hasAdditionalContext: bool(object, "hasAdditionalContext"),
                createdAt: isoDate(object, "createdAt"),
                updatedAt: isoDate(object, "updatedAt"),
                isPinned: bool(object, "isPinned"),
                attachments: attachmentsByNote[noteId] ?? []
            )
        }
    }

    func attachments(options: GlobalOptions, noteId: String? = nil, attachmentId: String? = nil) throws -> [AttachmentDTO] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AttachmentEntity")
        request.predicate = attachmentsPredicate(options: options, noteId: noteId, attachmentId: attachmentId)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = attachmentId == nil ? options.limit : 1
        return try context.fetch(request).map(attachmentDTO)
    }

    func summary(options: GlobalOptions) throws -> ResourceSummaryDTO {
        ResourceSummaryDTO(
            storePath: store.storeURL.path,
            profiles: try count(entity: "UserProfileEntity", predicate: nil),
            notebooks: try count(entity: "NotebookEntity", predicate: scopedPredicate(options: options)),
            notes: try count(entity: "NoteEntity", predicate: scopedPredicate(options: options)),
            attachments: try count(entity: "AttachmentEntity", predicate: scopedPredicate(options: options))
        )
    }

    func exportAttachment(id: String, options: GlobalOptions) throws -> [String: String] {
        guard let attachment = try attachments(options: options, attachmentId: id.lowercased()).first else {
            throw CLIError(description: "Attachment not found: \(id)")
        }

        guard let source = localAttachmentURL(attachment: attachment) else {
            throw CLIError(description: "No local file found for attachment \(id). It may only exist in iCloud.")
        }

        let destination: URL
        if let outputPath = options.outputPath {
            let outputURL = URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                destination = outputURL.appendingPathComponent(attachment.fileName)
            } else {
                destination = outputURL
            }
        } else {
            destination = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(attachment.fileName)
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return [
            "id": attachment.id,
            "fileName": attachment.fileName,
            "path": destination.path
        ]
    }

    private func scopedPredicate(options: GlobalOptions) -> NSPredicate {
        var predicates: [NSPredicate] = []
        if let profileId = options.profileId {
            predicates.append(NSPredicate(format: "profileId == %@", profileId))
        }
        if !options.includeDeleted {
            predicates.append(NSPredicate(format: "deletedAt == nil"))
        }
        return predicates.isEmpty ? NSPredicate(value: true) : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func notesPredicate(options: GlobalOptions, query: String?, id: String?) -> NSPredicate {
        var predicates = [scopedPredicate(options: options)]
        if let id {
            predicates.append(NSPredicate(format: "id == %@", id.lowercased()))
        }
        if let notebookId = options.notebookId {
            predicates.append(NSPredicate(format: "notebookId == %@", notebookId))
        }
        if let query, !query.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "title CONTAINS[cd] %@", query),
                NSPredicate(format: "summary CONTAINS[cd] %@", query),
                NSPredicate(format: "content CONTAINS[cd] %@", query)
            ]))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func attachmentsPredicate(options: GlobalOptions, noteId: String?, attachmentId: String?) -> NSPredicate {
        var predicates = [scopedPredicate(options: options)]
        if let noteId {
            predicates.append(NSPredicate(format: "noteId == %@", noteId.lowercased()))
        }
        if let attachmentId {
            predicates.append(NSPredicate(format: "id == %@", attachmentId.lowercased()))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func attachmentsByNote(noteIds: Set<String>, options: GlobalOptions) throws -> [String: [AttachmentDTO]] {
        guard !noteIds.isEmpty else { return [:] }
        var predicates = [
            NSPredicate(format: "noteId IN %@", Array(noteIds)),
            scopedPredicate(options: options)
        ]
        if let profileId = options.profileId {
            predicates.append(NSPredicate(format: "profileId == %@", profileId))
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: "AttachmentEntity")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return Dictionary(grouping: try context.fetch(request).map(attachmentDTO), by: \.noteId)
    }

    private func countNotesByNotebook(options: GlobalOptions) throws -> [String: Int] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "NoteEntity")
        request.predicate = scopedPredicate(options: options)
        return Dictionary(grouping: try context.fetch(request), by: { string($0, "notebookId") }).mapValues(\.count)
    }

    private func count(entity: String, predicate: NSPredicate?) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
        request.predicate = predicate
        return try context.count(for: request)
    }

    private func attachmentDTO(_ object: NSManagedObject) -> AttachmentDTO {
        let dto = AttachmentDTO(
            id: string(object, "id"),
            profileId: string(object, "profileId"),
            noteId: string(object, "noteId"),
            storagePath: string(object, "storagePath"),
            fileName: string(object, "fileName"),
            mimeType: string(object, "mimeType"),
            fileSize: int64(object, "fileSize"),
            originalPath: optionalString(object, "originalPath"),
            createdAt: isoDate(object, "createdAt"),
            updatedAt: isoDate(object, "updatedAt"),
            isUploaded: bool(object, "isUploaded"),
            missingLocalFile: bool(object, "missingLocalFile"),
            localFilePath: nil
        )
        return AttachmentDTO(
            id: dto.id,
            profileId: dto.profileId,
            noteId: dto.noteId,
            storagePath: dto.storagePath,
            fileName: dto.fileName,
            mimeType: dto.mimeType,
            fileSize: dto.fileSize,
            originalPath: dto.originalPath,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            isUploaded: dto.isUploaded,
            missingLocalFile: dto.missingLocalFile,
            localFilePath: localAttachmentURL(attachment: dto)?.path
        )
    }

    private func localAttachmentURL(attachment: AttachmentDTO) -> URL? {
        if let originalPath = attachment.originalPath,
           FileManager.default.fileExists(atPath: originalPath) {
            return URL(fileURLWithPath: originalPath)
        }

        let ext = (attachment.fileName as NSString).pathExtension
        let originalName = ext.isEmpty ? attachment.id : "\(attachment.id).\(ext)"
        let appSupportOriginal = store.storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("Attachments/originals", isDirectory: true)
            .appendingPathComponent(originalName)
        if FileManager.default.fileExists(atPath: appSupportOriginal.path) {
            return appSupportOriginal
        }

        let cacheURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Attachments", isDirectory: true)
            .appendingPathComponent(originalName)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        return nil
    }
}

private func string(_ object: NSManagedObject, _ key: String) -> String {
    object.value(forKey: key) as? String ?? ""
}

private func optionalString(_ object: NSManagedObject, _ key: String) -> String? {
    object.value(forKey: key) as? String
}

private func bool(_ object: NSManagedObject, _ key: String) -> Bool {
    object.value(forKey: key) as? Bool ?? false
}

private func int(_ object: NSManagedObject, _ key: String) -> Int {
    if let value = object.value(forKey: key) as? Int { return value }
    if let value = object.value(forKey: key) as? Int64 { return Int(value) }
    return 0
}

private func int64(_ object: NSManagedObject, _ key: String) -> Int64 {
    if let value = object.value(forKey: key) as? Int64 { return value }
    if let value = object.value(forKey: key) as? Int { return Int64(value) }
    return 0
}

private func isoDate(_ object: NSManagedObject, _ key: String) -> String {
    guard let date = object.value(forKey: key) as? Date else { return "" }
    return ISO8601DateFormatter().string(from: date)
}

private func printHelp() {
    print("""
    NoteLab read-only CLI

    Commands:
      stores                                      List candidate Core Data stores.
      profiles list                              List local profiles.
      notebooks list                             List notebooks.
      notebooks create --write --title TEXT      Create a notebook.
      notebooks read NOTEBOOK_ID                 Read one notebook.
      notebooks update NOTEBOOK_ID --write       Update notebook metadata.
      notebooks delete NOTEBOOK_ID --write       Soft-delete a notebook.
      notes list                                 List notes.
      notes search --query TEXT                  Search note title, summary, and content.
      notes create --write --notebook ID [--title TEXT] [--content TEXT|--content-file PATH]
      notes read NOTE_ID                         Read one note with attachments.
      notes update NOTE_ID --write               Update title/content/notebook.
      notes append NOTE_ID --write --content TEXT
      notes delete NOTE_ID --write               Soft-delete a note.
      content read NOTE_ID                       Read only note content.
      content update NOTE_ID --write             Replace note content.
      content append NOTE_ID --write             Append note content.
      content clear NOTE_ID --write              Clear note content.
      attachments list [NOTE_ID]                 List attachments, optionally for one note.
      attachments export ATTACHMENT_ID --output PATH
      attachments add NOTE_ID --write --file PATH
      resources list                             Count readable resources.

    Global options:
      --store PATH                               Explicit NoteLabStorageV3.sqlite path.
      --service-url URL                          Default http://127.0.0.1:47719.
      --agent-token TOKEN                        Token for protected App-local/remote agent service.
      --profile PROFILE_ID                       Restrict reads to one profile.
      --notebook NOTEBOOK_ID                     Restrict notes to one notebook.
      --title TEXT                               Title for notes create.
      --content TEXT                             Content for notes create/append.
      --content-file PATH                        UTF-8 content file for notes create/append.
      --file PATH                                File for attachments add.
      --mime-type TYPE                           Optional MIME type for attachments add.
      --color COLOR                              Optional notebook color.
      --icon ICON                                Optional notebook icon name.
      --description TEXT                         Optional notebook description.
      --write                                    Required for write commands.
      --no-append-markdown                       Do not add attachment markdown to note content.
      --limit N                                  Default 50.
      --include-deleted                          Include soft-deleted rows.
      --json                                     Accepted for agent ergonomics; output is JSON by default.
    """)
}

private func run() throws {
    let parsed = try CommandLineParser(arguments: Array(CommandLine.arguments.dropFirst()))
    let command = parsed.command
    let options = parsed.options

    if command == ["help"] {
        printHelp()
        return
    }

    if command == ["stores"] {
        let candidates = NoteLabStore.storeCandidates().map {
            StoreCandidateDTO(path: $0.path, exists: FileManager.default.fileExists(atPath: $0.path))
        }
        try JSON.printValue(candidates)
        return
    }

    if isWriteCommand(command), options.storePath != nil {
        throw CLIError(description: "write commands must use the NoteLab agent service, not --store")
    }

    if options.storePath == nil {
        do {
            let handled = try AgentServiceClient(baseURL: options.serviceURL).run(command: command, options: options)
            if handled {
                return
            }
        } catch is AgentServiceUnavailable {
            if isWriteCommand(command) {
                throw CLIError(description: "NoteLab agent service is unavailable; write command was not run")
            }
            // Fall back to direct store access for non-sandbox stores and tests.
        }
    }

    if isWriteCommand(command) {
        throw CLIError(description: "write command is only available through the NoteLab agent service")
    }

    let store = try NoteLabStore(path: options.storePath)
    let reader = NoteLabReader(store: store)

    switch command {
    case ["profiles", "list"]:
        try JSON.printValue(reader.profiles())
    case ["notebooks", "list"]:
        try JSON.printValue(reader.notebooks(options: options))
    case ["notes", "list"]:
        try JSON.printValue(reader.notes(options: options))
    case ["notes", "search"]:
        guard let query = options.query, !query.isEmpty else {
            throw CLIError(description: "notes search requires --query TEXT")
        }
        try JSON.printValue(reader.notes(options: options, query: query))
    case let command where command.count == 3 && command[0] == "notes" && command[1] == "read":
        guard command.count == 3 else {
            throw CLIError(description: "notes read requires NOTE_ID")
        }
        guard let note = try reader.notes(options: options, id: command[2]).first else {
            throw CLIError(description: "Note not found: \(command[2])")
        }
        try JSON.printValue(note)
    case let command where command.count >= 2 && command[0] == "attachments" && command[1] == "list":
        try JSON.printValue(reader.attachments(options: options, noteId: command.count >= 3 ? command[2] : nil))
    case let command where command.count == 3 && command[0] == "attachments" && command[1] == "export":
        guard command.count == 3 else {
            throw CLIError(description: "attachments export requires ATTACHMENT_ID")
        }
        try JSON.printValue(reader.exportAttachment(id: command[2], options: options))
    case ["resources", "list"]:
        try JSON.printValue(reader.summary(options: options))
    default:
        throw CLIError(description: "Unknown command: \(command.joined(separator: " "))")
    }
}

private func isWriteCommand(_ command: [String]) -> Bool {
    command == ["notebooks", "create"] ||
        command == ["notes", "create"] ||
        (command.count == 3 && command[0] == "notebooks" && ["update", "delete"].contains(command[1])) ||
        (command.count == 3 && command[0] == "notes" && ["update", "delete"].contains(command[1])) ||
        (command.count == 3 && command[0] == "notes" && command[1] == "append") ||
        (command.count == 3 && command[0] == "content" && ["update", "append", "clear"].contains(command[1])) ||
        (command.count == 3 && command[0] == "attachments" && command[1] == "add")
}

do {
    try run()
} catch {
    let message = (error as? CLIError)?.description ?? error.localizedDescription
    FileHandle.standardError.write(Data("notelab: \(message)\n".utf8))
    exit(1)
}
