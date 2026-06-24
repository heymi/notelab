import Foundation

#if os(iOS)
import Photos
import UIKit

struct NoteAttachmentPayload {
    let data: Data
    let attachmentId: UUID
    let fileName: String
    let type: AttachmentType
    let livePhotoMotionData: Data?
    let livePhotoMotionFileName: String?

    init(
        data: Data,
        attachmentId: UUID,
        fileName: String,
        type: AttachmentType,
        livePhotoMotionData: Data? = nil,
        livePhotoMotionFileName: String? = nil
    ) {
        self.data = data
        self.attachmentId = attachmentId
        self.fileName = fileName
        self.type = type
        self.livePhotoMotionData = livePhotoMotionData
        self.livePhotoMotionFileName = livePhotoMotionFileName
    }
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

    static func livePhotoPayload(from livePhoto: PHLivePhoto, fallbackImage: UIImage? = nil) async -> NoteAttachmentPayload? {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        let stillResource = resources.first { $0.type == .photo || $0.type == .fullSizePhoto }
        let motionResource = resources.first { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }

        let resourceStillData: Data?
        if let stillResource {
            resourceStillData = try? await data(for: stillResource)
        } else {
            resourceStillData = nil
        }
        let stillData = resourceStillData ?? fallbackImage?.jpegData(compressionQuality: 0.9)
        guard let stillData else { return nil }

        let attachmentId = UUID()
        let stillExtension = stillResource.map(fileExtension) ?? "jpg"
        let motionData: Data?
        if let motionResource {
            motionData = try? await data(for: motionResource)
        } else {
            motionData = nil
        }
        return NoteAttachmentPayload(
            data: stillData,
            attachmentId: attachmentId,
            fileName: "\(attachmentId.uuidString).\(stillExtension)",
            type: .image,
            livePhotoMotionData: motionData,
            livePhotoMotionFileName: motionData == nil ? nil : LivePhotoAttachment.motionFileName(for: attachmentId)
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
        .insertAttachment(
            data: payload.data,
            type: payload.type,
            fileName: payload.fileName,
            livePhotoMotionData: payload.livePhotoMotionData
        )
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

        if let motionData = payload.livePhotoMotionData,
           let motionFileName = payload.livePhotoMotionFileName {
            let motionAttachment = try AttachmentStorage.shared.saveNewAttachmentV3(
                data: motionData,
                attachmentId: UUID(),
                ownerId: ownerId,
                noteId: noteId,
                fileName: motionFileName,
                mimeType: AttachmentStorage.mimeType(for: motionFileName)
            )
            await AttachmentStorage.shared.uploadAndUpsertMetadataV3(attachment: motionAttachment)
        }
    }

    private static func fileExtension(for resource: PHAssetResource) -> String {
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "heic" : ext
    }

    private static func data(for resource: PHAssetResource) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            var result = Data()
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    result.append(chunk)
                },
                completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            )
        }
    }
}
#endif
