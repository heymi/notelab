import Foundation

#if os(iOS)
import UIKit

struct NoteAttachmentPayload {
    let data: Data
    let attachmentId: UUID
    let fileName: String
    let type: AttachmentType
}

enum NoteAttachmentInserter {
    static func imagePayload(from image: UIImage) -> NoteAttachmentPayload? {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        let attachmentId = UUID()
        return NoteAttachmentPayload(
            data: data,
            attachmentId: attachmentId,
            fileName: "\(attachmentId.uuidString).jpg",
            type: .image
        )
    }

    static func documentPayload(from url: URL) -> NoteAttachmentPayload? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let attachmentId = UUID()
        let fileName = url.lastPathComponent
        let type = AttachmentType.from(fileName: fileName)
        return NoteAttachmentPayload(data: data, attachmentId: attachmentId, fileName: fileName, type: type)
    }

    static func nativeCommand(for payload: NoteAttachmentPayload) -> EditorCommand {
        .insertAttachment(data: payload.data, type: payload.type, fileName: payload.fileName)
    }

    static func webMarkdown(for payload: NoteAttachmentPayload, ownerId: UUID) -> String {
        AttachmentCache.save(data: payload.data, attachmentId: payload.attachmentId, fileName: payload.fileName)
        let storagePath = AttachmentPathFactory.storagePath(
            ownerId: ownerId,
            attachmentId: payload.attachmentId,
            fileName: payload.fileName
        )
        return "\n![Attachment](\(storagePath))\n"
    }

    @MainActor
    static func upload(payload: NoteAttachmentPayload, ownerId: UUID, noteId: UUID) async throws {
        let mimeType = AttachmentStorage.mimeType(for: payload.fileName)
        let localAttachment = try AttachmentStorage.shared.saveNewAttachmentV3(
            data: payload.data,
            attachmentId: payload.attachmentId,
            ownerId: ownerId,
            noteId: noteId,
            fileName: payload.fileName,
            mimeType: mimeType
        )
        await AttachmentStorage.shared.uploadAndUpsertMetadataV3(attachment: localAttachment)
    }
}
#endif
