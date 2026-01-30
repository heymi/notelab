import Foundation

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

enum AttachmentThumbnailMemoryCache {
    private static let cache = NSCache<NSString, ImageBox>()

    static func get(attachmentId: UUID, fileName: String) -> PlatformImage? {
        cache.object(forKey: key(attachmentId: attachmentId, fileName: fileName))?.image
    }

    static func set(_ image: PlatformImage, attachmentId: UUID, fileName: String) {
        cache.setObject(ImageBox(image), forKey: key(attachmentId: attachmentId, fileName: fileName))
    }

    private static func key(attachmentId: UUID, fileName: String) -> NSString {
        "\(attachmentId.uuidString)::\(fileName)" as NSString
    }
}

private final class ImageBox: NSObject {
    let image: PlatformImage

    init(_ image: PlatformImage) {
        self.image = image
    }
}
