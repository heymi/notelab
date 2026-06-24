import Foundation

enum LivePhotoAttachment {
    static func motionFileName(for stillAttachmentId: UUID) -> String {
        "\(stillAttachmentId.uuidString.lowercased()).live.mov"
    }

    static func stillAttachmentId(fromMotionFileName fileName: String) -> UUID? {
        let name = (fileName as NSString).lastPathComponent.lowercased()
        guard name.hasSuffix(".live.mov") else { return nil }
        return UUID(uuidString: String(name.dropLast(".live.mov".count)))
    }

    static func isMotionCompanion(fileName: String, mimeType: String = "") -> Bool {
        stillAttachmentId(fromMotionFileName: fileName) != nil &&
            (mimeType.isEmpty || mimeType.lowercased().hasPrefix("video/"))
    }
}
