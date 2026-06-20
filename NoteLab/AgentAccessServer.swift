#if os(macOS)
import CoreData
import Foundation
import Network
import os

final class AgentAccessServer {
    static let shared = AgentAccessServer()

    private let logger = Logger(subsystem: "NoteLab", category: "AgentAccess")
    private let port: NWEndpoint.Port = 47719
    private var listener: NWListener?

    private init() {}

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)

            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.logger.error("Agent access server failed: \(error.localizedDescription, privacy: .public)")
                    self?.listener = nil
                }
            }
            listener.start(queue: DispatchQueue(label: "notelab.agent-access"))
            self.listener = listener
            logger.info("Agent access server listening on 127.0.0.1:47719")
        } catch {
            logger.error("Agent access server start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "notelab.agent-access.connection"))
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                self.sendJSON(["error": error.localizedDescription], status: 500, connection: connection)
                return
            }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            if HTTPRequest.needsMoreData(nextBuffer) {
                self.receiveRequest(connection, buffer: nextBuffer)
                return
            }
            guard let request = HTTPRequest(data: nextBuffer) else {
                self.sendJSON(["error": "Bad request"], status: 400, connection: connection)
                return
            }
            self.route(request, connection: connection)
        }
    }

    private func route(_ request: HTTPRequest, connection: NWConnection) {
        do {
            guard isAuthorized(request) else {
                sendJSON(["error": "Unauthorized"], status: 401, connection: connection)
                return
            }

            let reader = AgentAccessReader()
            if request.method == "POST" {
                guard isWriteEnabled else {
                    sendJSON(["error": "Agent write access is disabled"], status: 403, connection: connection)
                    return
                }
                let writer = AgentAccessWriter()
                switch request.path {
                case "/notebooks":
                    let payload = try request.decode(AgentCreateNotebookRequest.self)
                    sendJSON(try writer.createNotebook(payload), status: 201, connection: connection)
                case let path where path.hasPrefix("/notebooks/") && path.hasSuffix("/update"):
                    let id = String(path.dropFirst("/notebooks/".count).dropLast("/update".count))
                    let payload = try request.decode(AgentUpdateNotebookRequest.self)
                    sendJSON(try writer.updateNotebook(id: id, payload: payload), connection: connection)
                case let path where path.hasPrefix("/notebooks/") && path.hasSuffix("/delete"):
                    let id = String(path.dropFirst("/notebooks/".count).dropLast("/delete".count))
                    let payload = try request.decode(AgentScopedWriteRequest.self)
                    sendJSON(try writer.deleteNotebook(id: id, payload: payload), connection: connection)
                case "/notes":
                    let payload = try request.decode(AgentCreateNoteRequest.self)
                    sendJSON(try writer.createNote(payload), status: 201, connection: connection)
                case let path where path.hasPrefix("/notes/") && path.hasSuffix("/update"):
                    let id = String(path.dropFirst("/notes/".count).dropLast("/update".count))
                    let payload = try request.decode(AgentUpdateNoteRequest.self)
                    sendJSON(try writer.updateNote(id: id, payload: payload), connection: connection)
                case let path where path.hasPrefix("/notes/") && path.hasSuffix("/content/append"):
                    let id = String(path.dropFirst("/notes/".count).dropLast("/content/append".count))
                    let payload = try request.decode(AgentAppendNoteRequest.self)
                    sendJSON(try writer.appendNote(id: id, payload: payload), connection: connection)
                case let path where path.hasPrefix("/notes/") && path.hasSuffix("/content/delete"):
                    let id = String(path.dropFirst("/notes/".count).dropLast("/content/delete".count))
                    let payload = try request.decode(AgentScopedWriteRequest.self)
                    sendJSON(try writer.clearContent(id: id, payload: payload), connection: connection)
                case let path where path.hasPrefix("/notes/") && path.hasSuffix("/content"):
                    let id = String(path.dropFirst("/notes/".count).dropLast("/content".count))
                    let payload = try request.decode(AgentContentUpdateRequest.self)
                    sendJSON(try writer.updateContent(id: id, payload: payload), connection: connection)
                case let path where path.hasPrefix("/notes/") && path.hasSuffix("/append"):
                    let id = String(path.dropFirst("/notes/".count).dropLast("/append".count))
                    let payload = try request.decode(AgentAppendNoteRequest.self)
                    sendJSON(try writer.appendNote(id: id, payload: payload), connection: connection)
                case let path where path.hasPrefix("/notes/") && path.hasSuffix("/delete"):
                    let id = String(path.dropFirst("/notes/".count).dropLast("/delete".count))
                    let payload = try request.decode(AgentScopedWriteRequest.self)
                    sendJSON(try writer.deleteNote(id: id, payload: payload), connection: connection)
                case let path where path.hasPrefix("/notes/") && path.hasSuffix("/attachments"):
                    let id = String(path.dropFirst("/notes/".count).dropLast("/attachments".count))
                    let payload = try request.decode(AgentAddAttachmentRequest.self)
                    sendJSON(try writer.addAttachment(noteId: id, payload: payload), status: 201, connection: connection)
                default:
                    sendJSON(["error": "Not found"], status: 404, connection: connection)
                }
                return
            }

            switch request.path {
            case "/health":
                sendJSON(AgentHealthDTO(ok: true, service: "notelab-agent-access"), connection: connection)
            case "/profiles":
                sendJSON(try reader.profiles(), connection: connection)
            case "/notebooks":
                sendJSON(try reader.notebooks(query: request.query), connection: connection)
            case let path where path.hasPrefix("/notebooks/"):
                let id = String(path.dropFirst("/notebooks/".count))
                guard let notebook = try reader.notebook(id: id, query: request.query) else {
                    sendJSON(["error": "Notebook not found"], status: 404, connection: connection)
                    return
                }
                sendJSON(notebook, connection: connection)
            case "/notes":
                sendJSON(try reader.notes(query: request.query), connection: connection)
            case "/notes/search":
                sendJSON(try reader.notes(query: request.query), connection: connection)
            case "/resources":
                sendJSON(try reader.resources(query: request.query), connection: connection)
            case let path where path.hasPrefix("/notes/") && path.hasSuffix("/content"):
                let id = String(path.dropFirst("/notes/".count).dropLast("/content".count))
                guard let content = try reader.content(id: id, query: request.query) else {
                    sendJSON(["error": "Note not found"], status: 404, connection: connection)
                    return
                }
                sendJSON(content, connection: connection)
            case let path where path.hasPrefix("/notes/"):
                let id = String(path.dropFirst("/notes/".count))
                guard let note = try reader.note(id: id, query: request.query) else {
                    sendJSON(["error": "Note not found"], status: 404, connection: connection)
                    return
                }
                sendJSON(note, connection: connection)
            case "/attachments":
                sendJSON(try reader.attachments(query: request.query), connection: connection)
            case let path where path.hasPrefix("/attachments/") && path.hasSuffix("/data"):
                let raw = path.dropFirst("/attachments/".count).dropLast("/data".count)
                guard let result = try reader.attachmentData(id: String(raw), query: request.query) else {
                    sendJSON(["error": "Attachment file not found"], status: 404, connection: connection)
                    return
                }
                send(data: result.data, contentType: result.mimeType, fileName: result.fileName, connection: connection)
            default:
                sendJSON(["error": "Not found"], status: 404, connection: connection)
            }
        } catch {
            sendJSON(["error": error.localizedDescription], status: 500, connection: connection)
        }
    }

    private var isWriteEnabled: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: "AgentWriteEnabled")
        #endif
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let expected = UserDefaults.standard.string(forKey: "AgentAccessToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !expected.isEmpty else { return true }

        if request.bearerToken == expected {
            return true
        }
        return request.headers["x-notelab-agent-key"] == expected
    }

    private func sendJSON<T: Encodable>(_ value: T, status: Int = 200, connection: NWConnection) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            send(data: data, status: status, contentType: "application/json; charset=utf-8", connection: connection)
        } catch {
            send(data: Data("{\"error\":\"JSON encoding failed\"}".utf8), status: 500, contentType: "application/json", connection: connection)
        }
    }

    private func send(
        data: Data,
        status: Int = 200,
        contentType: String,
        fileName: String? = nil,
        connection: NWConnection
    ) {
        var headers = [
            "HTTP/1.1 \(status) \(statusText(status))",
            "Content-Type: \(contentType)",
            "Content-Length: \(data.count)",
            "Connection: close"
        ]
        if let fileName {
            headers.append("X-NoteLab-Filename: \(fileName)")
        }
        headers.append("")
        headers.append("")

        var response = Data(headers.joined(separator: "\r\n").utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        default: return "Internal Server Error"
        }
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    var bearerToken: String? {
        guard let authorization = headers["authorization"] else { return nil }
        let prefix = "bearer "
        guard authorization.lowercased().hasPrefix(prefix) else { return nil }
        return String(authorization.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(data: Data) {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8),
              let firstLine = headerText.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        guard method == "GET" || method == "POST" else { return nil }
        let target = String(parts[1])
        let components = URLComponents(string: target)
        path = components?.path ?? target
        query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        headers = Self.headers(headerText)

        let bodyStart = headerRange.upperBound
        let length = Self.contentLength(headerText)
        guard data.count >= bodyStart + length else { return nil }
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }

    static func needsMoreData(_ data: Data) -> Bool {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return true }
        return data.count < headerRange.upperBound + contentLength(headerText)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }

    private static func contentLength(_ headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                return Int(parts[1]) ?? 0
            }
        }
        return 0
    }

    private static func headers(_ headerText: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2 {
                result[parts[0].lowercased()] = parts[1]
            }
        }
        return result
    }
}

private final class AgentAccessReader {
    private let context = StorageController.shared.mainContext

    func profiles() throws -> [AgentProfileDTO] {
        try read {
            let request = UserProfileEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).map {
                AgentProfileDTO(
                    id: $0.id,
                    displayEmail: $0.displayEmail,
                    displayName: $0.displayName,
                    createdAt: iso($0.createdAt),
                    updatedAt: iso($0.updatedAt),
                    isLocked: $0.isLocked
                )
            }
        }
    }

    func notebooks(query: [String: String]) throws -> [AgentNotebookDTO] {
        try read {
            let request = NotebookEntity.fetchRequest()
            request.predicate = notebooksPredicate(query: query)
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false)
            ]
            request.fetchLimit = limit(query)
            let counts = try noteCounts(query: query)
            return try context.fetch(request).map {
                AgentNotebookDTO(
                    id: $0.id,
                    profileId: $0.profileId,
                    title: $0.title,
                    color: $0.colorRaw,
                    iconName: $0.iconName,
                    description: $0.notebookDescription,
                    createdAt: iso($0.createdAt),
                    updatedAt: iso($0.updatedAt),
                    isPinned: $0.isPinned,
                    noteCount: counts[$0.id, default: 0]
                )
            }
        }
    }

    func notebook(id: String, query: [String: String]) throws -> AgentNotebookDTO? {
        var scoped = query
        scoped["id"] = id.lowercased()
        return try notebooks(query: scoped).first
    }

    func notes(query: [String: String]) throws -> [AgentNoteDTO] {
        try read {
            let request = NoteEntity.fetchRequest()
            request.predicate = notesPredicate(query: query)
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
            request.fetchLimit = limit(query)
            let notes = try context.fetch(request)
            let attachments = try attachmentsByNote(ids: Set(notes.map(\.id)), query: query)
            return notes.map { noteDTO($0, attachments: attachments[$0.id] ?? []) }
        }
    }

    func note(id: String, query: [String: String]) throws -> AgentNoteDTO? {
        var scoped = query
        scoped["id"] = id.lowercased()
        return try notes(query: scoped).first
    }

    func content(id: String, query: [String: String]) throws -> AgentContentDTO? {
        try note(id: id, query: query).map {
            AgentContentDTO(
                id: $0.id,
                profileId: $0.profileId,
                notebookId: $0.notebookId,
                title: $0.title,
                content: $0.content,
                updatedAt: $0.updatedAt
            )
        }
    }

    func attachments(query: [String: String]) throws -> [AgentAttachmentDTO] {
        try read {
            let request = AttachmentEntity.fetchRequest()
            request.predicate = attachmentsPredicate(query: query)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchLimit = limit(query)
            return try context.fetch(request).map(attachmentDTO)
        }
    }

    func resources(query: [String: String]) throws -> AgentResourcesDTO {
        try read {
            AgentResourcesDTO(
                profiles: try count(UserProfileEntity.fetchRequest()),
                notebooks: try count(NotebookEntity.fetchRequest(), predicate: scopedPredicate(query: query)),
                notes: try count(NoteEntity.fetchRequest(), predicate: scopedPredicate(query: query)),
                attachments: try count(AttachmentEntity.fetchRequest(), predicate: scopedPredicate(query: query))
            )
        }
    }

    func attachmentData(id: String, query: [String: String]) throws -> (data: Data, fileName: String, mimeType: String)? {
        guard let attachment = try attachments(query: query.merging(["id": id.lowercased()]) { current, _ in current }).first,
              let attachmentId = UUID(uuidString: attachment.id) else { return nil }
        if let url = localAttachmentURL(attachment) {
            return (try Data(contentsOf: url), attachment.fileName, attachment.mimeType)
        }

        let data = try loadAttachmentData(
            attachmentId: attachmentId,
            storagePath: attachment.storagePath,
            fileName: attachment.fileName
        )
        return (data, attachment.fileName, attachment.mimeType)
    }

    private func loadAttachmentData(attachmentId: UUID, storagePath: String, fileName: String) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>!

        Task {
            do {
                let data = try await AttachmentStorage.shared.loadAttachmentData(
                    attachmentId: attachmentId,
                    storagePath: storagePath,
                    fileName: fileName
                )
                result = .success(data)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try result.get()
    }

    private func read<T>(_ body: () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try body()
        }

        var result: Result<T, Error>!
        DispatchQueue.main.sync {
            result = Result { try body() }
        }
        return try result.get()
    }

    private func notesPredicate(query: [String: String]) -> NSPredicate {
        var predicates = [scopedPredicate(query: query)]
        if let id = query["id"] {
            predicates.append(NSPredicate(format: "id == %@", id.lowercased()))
        }
        if let notebook = query["notebook"] {
            predicates.append(NSPredicate(format: "notebookId == %@", notebook.lowercased()))
        }
        if let search = query["query"], !search.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "title CONTAINS[cd] %@", search),
                NSPredicate(format: "summary CONTAINS[cd] %@", search),
                NSPredicate(format: "content CONTAINS[cd] %@", search)
            ]))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func notebooksPredicate(query: [String: String]) -> NSPredicate {
        var predicates = [scopedPredicate(query: query)]
        if let id = query["id"] {
            predicates.append(NSPredicate(format: "id == %@", id.lowercased()))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func attachmentsPredicate(query: [String: String]) -> NSPredicate {
        var predicates = [scopedPredicate(query: query)]
        if let id = query["id"] {
            predicates.append(NSPredicate(format: "id == %@", id.lowercased()))
        }
        if let noteId = query["noteId"] {
            predicates.append(NSPredicate(format: "noteId == %@", noteId.lowercased()))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func scopedPredicate(query: [String: String]) -> NSPredicate {
        var predicates: [NSPredicate] = []
        if let profile = query["profile"] {
            predicates.append(NSPredicate(format: "profileId == %@", profile.lowercased()))
        }
        if query["includeDeleted"] != "true" {
            predicates.append(NSPredicate(format: "deletedAt == nil"))
        }
        return predicates.isEmpty ? NSPredicate(value: true) : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func attachmentsByNote(ids: Set<String>, query: [String: String]) throws -> [String: [AgentAttachmentDTO]] {
        guard !ids.isEmpty else { return [:] }
        var attachmentQuery = query
        attachmentQuery.removeValue(forKey: "id")
        let request = AttachmentEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteId IN %@", Array(ids)),
            attachmentsPredicate(query: attachmentQuery)
        ])
        return Dictionary(grouping: try context.fetch(request).map(attachmentDTO), by: \.noteId)
    }

    private func noteCounts(query: [String: String]) throws -> [String: Int] {
        let request = NoteEntity.fetchRequest()
        request.predicate = scopedPredicate(query: query)
        return Dictionary(grouping: try context.fetch(request), by: \.notebookId).mapValues(\.count)
    }

    private func count<T: NSManagedObject>(_ request: NSFetchRequest<T>, predicate: NSPredicate? = nil) throws -> Int {
        request.predicate = predicate
        return try context.count(for: request)
    }

    private func noteDTO(_ note: NoteEntity, attachments: [AgentAttachmentDTO]) -> AgentNoteDTO {
        AgentNoteDTO(
            id: note.id,
            profileId: note.profileId,
            notebookId: note.notebookId,
            title: note.title,
            summary: note.summary,
            content: note.content,
            paragraphCount: Int(note.paragraphCount),
            bulletCount: Int(note.bulletCount),
            hasAdditionalContext: note.hasAdditionalContext,
            createdAt: iso(note.createdAt),
            updatedAt: iso(note.updatedAt),
            isPinned: note.isPinned,
            attachments: attachments
        )
    }

    private func attachmentDTO(_ attachment: AttachmentEntity) -> AgentAttachmentDTO {
        AgentAttachmentDTO(
            id: attachment.id,
            profileId: attachment.profileId,
            noteId: attachment.noteId,
            storagePath: attachment.storagePath,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            fileSize: attachment.fileSize,
            originalPath: attachment.originalPath,
            createdAt: iso(attachment.createdAt),
            updatedAt: iso(attachment.updatedAt),
            isUploaded: attachment.isUploaded,
            missingLocalFile: attachment.missingLocalFile,
            localFilePath: localAttachmentURL(attachmentDTOWithoutLocalPath(attachment))?.path
        )
    }

    private func attachmentDTOWithoutLocalPath(_ attachment: AttachmentEntity) -> AgentAttachmentDTO {
        AgentAttachmentDTO(
            id: attachment.id,
            profileId: attachment.profileId,
            noteId: attachment.noteId,
            storagePath: attachment.storagePath,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            fileSize: attachment.fileSize,
            originalPath: attachment.originalPath,
            createdAt: iso(attachment.createdAt),
            updatedAt: iso(attachment.updatedAt),
            isUploaded: attachment.isUploaded,
            missingLocalFile: attachment.missingLocalFile,
            localFilePath: nil
        )
    }

    private func localAttachmentURL(_ attachment: AgentAttachmentDTO) -> URL? {
        if let originalPath = attachment.originalPath,
           FileManager.default.fileExists(atPath: originalPath) {
            return URL(fileURLWithPath: originalPath)
        }

        let ext = (attachment.fileName as NSString).pathExtension
        let name = ext.isEmpty ? attachment.id : "\(attachment.id).\(ext)"
        let original = StorageController.attachmentsOriginalsURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: original.path) {
            return original
        }
        return nil
    }

    private func limit(_ query: [String: String]) -> Int {
        max(1, Int(query["limit"] ?? "") ?? 50)
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private final class AgentAccessWriter {
    private let context = StorageController.shared.mainContext
    private let repository = NotebookRepository()

    func createNotebook(_ payload: AgentCreateNotebookRequest) throws -> AgentNotebookDTO {
        try write {
            let profileId = try resolvedProfileId(payload.profileId)
            let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw AgentAccessError("Notebook title is required")
            }
            let color = NotebookColor(rawValue: payload.color ?? "") ?? .lime
            let iconName = payload.iconName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notebook = try repository.createNotebook(
                profileId: profileId,
                title: title,
                color: color,
                iconName: iconName?.isEmpty == false ? iconName! : "book"
            )
            return AgentNotebookDTO(
                id: notebook.id.uuidString.lowercased(),
                profileId: profileId.uuidString.lowercased(),
                title: notebook.title,
                color: notebook.color.rawValue,
                iconName: notebook.iconName,
                description: notebook.notebookDescription,
                createdAt: iso(notebook.createdAt),
                updatedAt: iso(notebook.createdAt),
                isPinned: notebook.isPinned,
                noteCount: 0
            )
        }
    }

    func updateNotebook(id rawId: String, payload: AgentUpdateNotebookRequest) throws -> AgentNotebookDTO {
        try write {
            guard let id = UUID(uuidString: rawId) else {
                throw AgentAccessError("Invalid notebook id")
            }
            guard let entity = try findNotebook(id: id, profileId: payload.profileId),
                  let profileId = UUID(uuidString: entity.profileId) else {
                throw AgentAccessError("Notebook not found")
            }

            let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let color = payload.color.flatMap(NotebookColor.init(rawValue:))
            try repository.updateNotebook(
                profileId: profileId,
                id: id,
                title: title?.isEmpty == false ? title : nil,
                color: color,
                description: payload.description,
                iconName: payload.iconName
            )

            guard let refreshed = try findNotebook(id: id, profileId: entity.profileId) else {
                throw AgentAccessError("Notebook not found after update")
            }
            return notebookDTO(refreshed)
        }
    }

    func deleteNotebook(id rawId: String, payload: AgentScopedWriteRequest) throws -> AgentWriteResultDTO {
        try write {
            guard let id = UUID(uuidString: rawId) else {
                throw AgentAccessError("Invalid notebook id")
            }
            guard let entity = try findNotebook(id: id, profileId: payload.profileId),
                  let profileId = UUID(uuidString: entity.profileId) else {
                throw AgentAccessError("Notebook not found")
            }
            try repository.deleteNotebook(profileId: profileId, id: id)
            return AgentWriteResultDTO(id: rawId.lowercased(), deleted: true)
        }
    }

    func createNote(_ payload: AgentCreateNoteRequest) throws -> AgentNoteDTO {
        try write {
            guard let notebookId = UUID(uuidString: payload.notebookId) else {
                throw AgentAccessError("Invalid notebook id")
            }
            guard let notebook = try findNotebook(id: notebookId, profileId: payload.profileId) else {
                throw AgentAccessError("Notebook not found")
            }
            guard let profileId = UUID(uuidString: notebook.profileId) else {
                throw AgentAccessError("Invalid notebook profile id")
            }

            let now = Date()
            let content = payload.content ?? ""
            let title = cleanedTitle(payload.title) ?? NoteTitleDeriver.title(fromMarkdown: content, fallback: "Untitled")
            var note = Note(
                id: UUID(),
                title: title,
                summary: "",
                paragraphCount: 0,
                bulletCount: 0,
                hasAdditionalContext: false,
                createdAt: now,
                updatedAt: now,
                contentRTF: nil,
                content: content,
                isPinned: false
            )
            note.updateMetrics()
            _ = try repository.createNote(profileId: profileId, notebookId: notebookId, note: note)
            return noteDTO(note: note, profileId: notebook.profileId, notebookId: notebook.id, attachments: [])
        }
    }

    func appendNote(id: String, payload: AgentAppendNoteRequest) throws -> AgentNoteDTO {
        try write {
            guard let noteId = UUID(uuidString: id) else {
                throw AgentAccessError("Invalid note id")
            }
            guard let entity = try findNote(id: noteId, profileId: payload.profileId),
                  let profileId = UUID(uuidString: entity.profileId),
                  let notebookId = UUID(uuidString: entity.notebookId) else {
                throw AgentAccessError("Note not found")
            }

            var note = domainNote(entity)
            note.content = appended(base: note.content, extra: payload.content)
            note.updatedAt = Date()
            note.updateMetrics()
            try repository.updateNote(profileId: profileId, notebookId: notebookId, note: note)
            let refreshed = try findNote(id: noteId, profileId: entity.profileId) ?? entity
            return noteDTO(entity: refreshed, attachments: [])
        }
    }

    func updateNote(id rawId: String, payload: AgentUpdateNoteRequest) throws -> AgentNoteDTO {
        try write {
            guard let noteId = UUID(uuidString: rawId) else {
                throw AgentAccessError("Invalid note id")
            }
            guard let entity = try findNote(id: noteId, profileId: payload.profileId),
                  let profileId = UUID(uuidString: entity.profileId) else {
                throw AgentAccessError("Note not found")
            }

            var targetNotebookId = UUID(uuidString: entity.notebookId)
            if let rawNotebookId = payload.notebookId {
                guard let notebookId = UUID(uuidString: rawNotebookId),
                      try findNotebook(id: notebookId, profileId: entity.profileId) != nil else {
                    throw AgentAccessError("Target notebook not found")
                }
                targetNotebookId = notebookId
            }
            guard let notebookId = targetNotebookId else {
                throw AgentAccessError("Invalid notebook id")
            }

            var note = domainNote(entity)
            if let title = cleanedTitle(payload.title) {
                note.title = title
            }
            if let content = payload.content {
                note.content = content
            }
            note.updatedAt = Date()
            note.updateMetrics()
            try repository.updateNote(profileId: profileId, notebookId: notebookId, note: note)
            let refreshed = try findNote(id: noteId, profileId: entity.profileId) ?? entity
            return noteDTO(entity: refreshed, attachments: [])
        }
    }

    func updateContent(id rawId: String, payload: AgentContentUpdateRequest) throws -> AgentContentDTO {
        let note = try updateNote(
            id: rawId,
            payload: AgentUpdateNoteRequest(profileId: payload.profileId, notebookId: nil, title: nil, content: payload.content)
        )
        return AgentContentDTO(
            id: note.id,
            profileId: note.profileId,
            notebookId: note.notebookId,
            title: note.title,
            content: note.content,
            updatedAt: note.updatedAt
        )
    }

    func clearContent(id rawId: String, payload: AgentScopedWriteRequest) throws -> AgentContentDTO {
        try updateContent(id: rawId, payload: AgentContentUpdateRequest(profileId: payload.profileId, content: ""))
    }

    func deleteNote(id rawId: String, payload: AgentScopedWriteRequest) throws -> AgentWriteResultDTO {
        try write {
            guard let id = UUID(uuidString: rawId) else {
                throw AgentAccessError("Invalid note id")
            }
            guard let entity = try findNote(id: id, profileId: payload.profileId),
                  let profileId = UUID(uuidString: entity.profileId) else {
                throw AgentAccessError("Note not found")
            }
            try repository.deleteNote(profileId: profileId, noteId: id)
            return AgentWriteResultDTO(id: rawId.lowercased(), deleted: true)
        }
    }

    func addAttachment(noteId rawNoteId: String, payload: AgentAddAttachmentRequest) throws -> AgentAttachmentDTO {
        try write {
            guard let noteId = UUID(uuidString: rawNoteId) else {
                throw AgentAccessError("Invalid note id")
            }
            guard let entity = try findNote(id: noteId, profileId: payload.profileId),
                  let profileId = UUID(uuidString: entity.profileId),
                  let notebookId = UUID(uuidString: entity.notebookId) else {
                throw AgentAccessError("Note not found")
            }
            guard let data = Data(base64Encoded: payload.dataBase64) else {
                throw AgentAccessError("Attachment data is not valid base64")
            }

            let fileName = payload.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty else {
                throw AgentAccessError("Attachment fileName is required")
            }

            let attachmentId = UUID()
            let mimeType = payload.mimeType ?? AttachmentStorage.mimeType(for: fileName)
            let record = try AttachmentStorage.shared.saveNewAttachmentV3(
                data: data,
                attachmentId: attachmentId,
                ownerId: profileId,
                noteId: noteId,
                fileName: fileName,
                mimeType: mimeType
            )

            if payload.appendMarkdown ?? true {
                var note = domainNote(entity)
                note.content = appended(base: note.content, extra: "\n![Attachment](\(record.storagePath))")
                note.updatedAt = Date()
                note.updateMetrics()
                try repository.updateNote(profileId: profileId, notebookId: notebookId, note: note)
            }

            Task {
                await AttachmentStorage.shared.uploadAndUpsertMetadataV3(attachment: record)
            }

            return attachmentDTO(record)
        }
    }

    private func write<T>(_ body: () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try body()
        }

        var result: Result<T, Error>!
        DispatchQueue.main.sync {
            result = Result { try body() }
        }
        return try result.get()
    }

    private func findNotebook(id: UUID, profileId: String?) throws -> NotebookEntity? {
        let request = NotebookEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "id == %@", id.uuidString.lowercased()),
            NSPredicate(format: "deletedAt == nil")
        ]
        if let profileId {
            predicates.append(NSPredicate(format: "profileId == %@", profileId.lowercased()))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func resolvedProfileId(_ rawProfileId: String?) throws -> UUID {
        if let rawProfileId {
            guard let profileId = UUID(uuidString: rawProfileId) else {
                throw AgentAccessError("Invalid profile id")
            }
            return profileId
        }

        let request = UserProfileEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 1
        guard let profile = try context.fetch(request).first,
              let profileId = UUID(uuidString: profile.id) else {
            throw AgentAccessError("No local profile is available")
        }
        return profileId
    }

    private func findNote(id: UUID, profileId: String?) throws -> NoteEntity? {
        let request = NoteEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "id == %@", id.uuidString.lowercased()),
            NSPredicate(format: "deletedAt == nil")
        ]
        if let profileId {
            predicates.append(NSPredicate(format: "profileId == %@", profileId.lowercased()))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func domainNote(_ entity: NoteEntity) -> Note {
        Note(
            id: UUID(uuidString: entity.id) ?? UUID(),
            title: entity.title,
            summary: entity.summary,
            paragraphCount: Int(entity.paragraphCount),
            bulletCount: Int(entity.bulletCount),
            hasAdditionalContext: entity.hasAdditionalContext,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            contentRTF: entity.contentRTF,
            content: entity.content,
            isPinned: entity.isPinned
        )
    }

    private func noteDTO(entity: NoteEntity, attachments: [AgentAttachmentDTO]) -> AgentNoteDTO {
        noteDTO(note: domainNote(entity), profileId: entity.profileId, notebookId: entity.notebookId, attachments: attachments)
    }

    private func notebookDTO(_ notebook: NotebookEntity) -> AgentNotebookDTO {
        AgentNotebookDTO(
            id: notebook.id,
            profileId: notebook.profileId,
            title: notebook.title,
            color: notebook.colorRaw,
            iconName: notebook.iconName,
            description: notebook.notebookDescription,
            createdAt: iso(notebook.createdAt),
            updatedAt: iso(notebook.updatedAt),
            isPinned: notebook.isPinned,
            noteCount: 0
        )
    }

    private func noteDTO(note: Note, profileId: String, notebookId: String, attachments: [AgentAttachmentDTO]) -> AgentNoteDTO {
        AgentNoteDTO(
            id: note.id.uuidString.lowercased(),
            profileId: profileId,
            notebookId: notebookId,
            title: note.title,
            summary: note.summary,
            content: note.content,
            paragraphCount: note.paragraphCount,
            bulletCount: note.bulletCount,
            hasAdditionalContext: note.hasAdditionalContext,
            createdAt: iso(note.createdAt),
            updatedAt: iso(note.updatedAt),
            isPinned: note.isPinned,
            attachments: attachments
        )
    }

    private func attachmentDTO(_ record: AttachmentRecord) -> AgentAttachmentDTO {
        AgentAttachmentDTO(
            id: record.id.uuidString.lowercased(),
            profileId: record.profileId.uuidString.lowercased(),
            noteId: record.noteId.uuidString.lowercased(),
            storagePath: record.storagePath,
            fileName: record.fileName,
            mimeType: record.mimeType,
            fileSize: record.fileSize,
            originalPath: record.originalPath,
            createdAt: iso(record.createdAt),
            updatedAt: iso(record.updatedAt),
            isUploaded: record.isUploaded,
            missingLocalFile: record.missingLocalFile,
            localFilePath: record.originalPath
        )
    }

    private func cleanedTitle(_ title: String?) -> String? {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func appended(base: String, extra: String) -> String {
        let trimmedExtra = extra.trimmingCharacters(in: .newlines)
        guard !trimmedExtra.isEmpty else { return base }
        if base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return trimmedExtra
        }
        return base.trimmingCharacters(in: .newlines) + "\n\n" + trimmedExtra + "\n"
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private struct AgentAccessError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

private struct AgentProfileDTO: Codable {
    let id: String
    let displayEmail: String?
    let displayName: String?
    let createdAt: String
    let updatedAt: String
    let isLocked: Bool
}

private struct AgentNotebookDTO: Codable {
    let id: String
    let profileId: String
    let title: String
    let color: String
    let iconName: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let isPinned: Bool
    let noteCount: Int
}

private struct AgentNoteDTO: Codable {
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
    let attachments: [AgentAttachmentDTO]
}

private struct AgentAttachmentDTO: Codable {
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

private struct AgentResourcesDTO: Codable {
    let profiles: Int
    let notebooks: Int
    let notes: Int
    let attachments: Int
}

private struct AgentContentDTO: Codable {
    let id: String
    let profileId: String
    let notebookId: String
    let title: String
    let content: String
    let updatedAt: String
}

private struct AgentWriteResultDTO: Codable {
    let id: String
    let deleted: Bool
}

private struct AgentHealthDTO: Codable {
    let ok: Bool
    let service: String
}

private struct AgentCreateNoteRequest: Decodable {
    let notebookId: String
    let profileId: String?
    let title: String?
    let content: String?
}

private struct AgentCreateNotebookRequest: Decodable {
    let profileId: String?
    let title: String
    let color: String?
    let iconName: String?
}

private struct AgentUpdateNotebookRequest: Decodable {
    let profileId: String?
    let title: String?
    let color: String?
    let iconName: String?
    let description: String?
}

private struct AgentUpdateNoteRequest: Decodable {
    let profileId: String?
    let notebookId: String?
    let title: String?
    let content: String?
}

private struct AgentContentUpdateRequest: Decodable {
    let profileId: String?
    let content: String
}

private struct AgentScopedWriteRequest: Decodable {
    let profileId: String?
}

private struct AgentAppendNoteRequest: Decodable {
    let profileId: String?
    let content: String
}

private struct AgentAddAttachmentRequest: Decodable {
    let profileId: String?
    let fileName: String
    let mimeType: String?
    let dataBase64: String
    let appendMarkdown: Bool?
}
#endif
