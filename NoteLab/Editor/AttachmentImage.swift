#if canImport(UIKit)
import ImageIO
import UIKit

enum AttachmentImage {
    static func image(data: Data, fileName: String) -> UIImage? {
        guard (fileName as NSString).pathExtension.lowercased() == "gif" else {
            return UIImage(data: data)
        }
        return animatedGIF(data: data) ?? UIImage(data: data)
    }

    private static func animatedGIF(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval
        return max(unclamped ?? clamped ?? 0.1, 0.02)
    }
}
#endif
