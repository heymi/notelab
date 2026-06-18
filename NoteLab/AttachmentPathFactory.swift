import Foundation

enum AttachmentPathFactory {
    static func storagePath(ownerId: UUID, attachmentId: UUID, fileName: String) -> String {
        CloudKitSchema.storagePath(ownerId: ownerId, attachmentId: attachmentId, fileName: fileName)
    }
}
