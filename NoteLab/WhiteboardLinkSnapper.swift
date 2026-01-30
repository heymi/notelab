import SwiftUI

enum WhiteboardLinkSnapper {
    static func clamp(offset: CGSize, container: CGSize, insets: EdgeInsets, overlaySize: CGSize, padding: CGFloat = 12) -> CGSize {
        guard overlaySize != .zero else { return offset }
        let baseX = container.width - insets.trailing - padding - overlaySize.width
        let baseY = insets.top + padding
        let minX = (insets.leading + padding) - baseX
        let maxX = (container.width - insets.trailing - padding - overlaySize.width) - baseX
        let minY = (insets.top + padding) - baseY
        let maxY = (container.height - insets.bottom - padding - overlaySize.height) - baseY
        let clampedX = min(max(offset.width, minX), maxX)
        let clampedY = min(max(offset.height, minY), maxY)
        return CGSize(width: clampedX, height: clampedY)
    }

    static func snap(offset: CGSize, container: CGSize, insets: EdgeInsets, overlaySize: CGSize, padding: CGFloat = 12) -> CGSize {
        let clamped = clamp(offset: offset, container: container, insets: insets, overlaySize: overlaySize, padding: padding)
        guard overlaySize != .zero else { return clamped }
        let baseX = container.width - insets.trailing - padding - overlaySize.width
        let baseY = insets.top + padding
        let minX = (insets.leading + padding) - baseX
        let maxX = (container.width - insets.trailing - padding - overlaySize.width) - baseX
        let minY = (insets.top + padding) - baseY
        let maxY = (container.height - insets.bottom - padding - overlaySize.height) - baseY
        let centerY = (minY + maxY) / 2

        let points: [CGSize] = [
            CGSize(width: minX, height: minY),
            CGSize(width: minX, height: maxY),
            CGSize(width: maxX, height: minY),
            CGSize(width: maxX, height: maxY),
            CGSize(width: minX, height: centerY),
            CGSize(width: maxX, height: centerY)
        ]

        var closest = points[0]
        var minDistance = distance(clamped, closest)
        for point in points.dropFirst() {
            let d = distance(clamped, point)
            if d < minDistance {
                minDistance = d
                closest = point
            }
        }
        return closest
    }

    private static func distance(_ lhs: CGSize, _ rhs: CGSize) -> CGFloat {
        let dx = lhs.width - rhs.width
        let dy = lhs.height - rhs.height
        return sqrt(dx * dx + dy * dy)
    }
}
