import AppKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

struct Variant {
    let bgTop: NSColor
    let bgBottom: NSColor
    let glow: NSColor
    let cardFillTop: NSColor
    let cardFillBottom: NSColor
    let cardStroke: NSColor
    let sheetFillTop: NSColor
    let sheetFillBottom: NSColor
    let sheetStroke: NSColor
    let lineColor: NSColor
}

extension NSColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(variant: Variant, size: Int, outputURL: URL) throws {
    let sizeF = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: sizeF, height: sizeF)
    let scale = sizeF / 1024

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )
    guard let bitmap = rep else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap"])
    }

    let ctx = NSGraphicsContext(bitmapImageRep: bitmap)
    ctx?.imageInterpolation = .high
    NSGraphicsContext.current = ctx

    let bgGradient = NSGradient(colors: [variant.bgTop, variant.bgBottom])
    bgGradient?.draw(in: rect, angle: 90)

    let glowGradient = NSGradient(colors: [variant.glow, NSColor.clear])
    glowGradient?.draw(fromCenter: NSPoint(x: sizeF * 0.22, y: sizeF * 0.82), radius: sizeF * 0.08, toCenter: NSPoint(x: sizeF * 0.22, y: sizeF * 0.82), radius: sizeF * 0.62, options: [])

    let vignette = NSGradient(colors: [NSColor.clear, NSColor.black.withAlphaComponent(0.18)])
    vignette?.draw(in: rect, angle: 90)

    let cardWidth: CGFloat = 700 * scale
    let cardHeight: CGFloat = 760 * scale
    let cardRect = NSRect(
        x: (CGFloat(size) - cardWidth) / 2,
        y: (CGFloat(size) - cardHeight) / 2,
        width: cardWidth,
        height: cardHeight
    )
    let cardRadius: CGFloat = 150 * scale

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 40 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    shadow.set()

    let cardPath = drawRoundedRect(cardRect, radius: cardRadius)
    let cardGradient = NSGradient(colors: [variant.cardFillTop, variant.cardFillBottom])
    cardGradient?.draw(in: cardPath, angle: 90)

    NSShadow().set()
    variant.cardStroke.setStroke()
    cardPath.lineWidth = max(1, 3 * scale)
    cardPath.stroke()

    let highlightRect = cardRect.insetBy(dx: 40 * scale, dy: 40 * scale)
    let highlightPath = drawRoundedRect(highlightRect, radius: max(0, cardRadius - 40 * scale))
    let highlightGradient = NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0.02)])
    highlightGradient?.draw(in: highlightPath, angle: 90)

    let sheetRect = cardRect.insetBy(dx: 130 * scale, dy: 160 * scale)
    let sheetRadius = cardRadius - 70 * scale
    let sheetPath = drawRoundedRect(sheetRect, radius: sheetRadius)
    let sheetGradient = NSGradient(colors: [variant.sheetFillTop, variant.sheetFillBottom])
    sheetGradient?.draw(in: sheetPath, angle: 90)

    variant.sheetStroke.setStroke()
    sheetPath.lineWidth = max(1, 2 * scale)
    sheetPath.stroke()

    let foldSize: CGFloat = 90 * scale
    let foldRect = NSRect(
        x: sheetRect.maxX - foldSize,
        y: sheetRect.maxY - foldSize,
        width: foldSize,
        height: foldSize
    )
    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: foldRect.minX, y: foldRect.maxY))
    foldPath.line(to: NSPoint(x: foldRect.maxX, y: foldRect.maxY))
    foldPath.line(to: NSPoint(x: foldRect.maxX, y: foldRect.minY))
    foldPath.close()
    NSColor.white.withAlphaComponent(0.22).setFill()
    foldPath.fill()

    let lineInset: CGFloat = 90 * scale
    let lineHeight: CGFloat = 34 * scale
    let lineGap: CGFloat = 40 * scale
    let firstLineY = sheetRect.maxY - 190 * scale

    variant.lineColor.setFill()
    for i in 0..<3 {
        let lineRect = NSRect(
            x: sheetRect.minX + lineInset,
            y: firstLineY - CGFloat(i) * (lineHeight + lineGap),
            width: sheetRect.width - lineInset * 2,
            height: lineHeight
        )
        let linePath = drawRoundedRect(lineRect, radius: lineHeight / 2)
        linePath.fill()
    }

    let accentCircle = NSBezierPath(ovalIn: NSRect(x: cardRect.minX + 90 * scale, y: cardRect.minY + 120 * scale, width: 140 * scale, height: 140 * scale))
    NSColor.white.withAlphaComponent(0.16).setFill()
    accentCircle.fill()

    guard let sourceImage = bitmap.cgImage else {
        throw NSError(domain: "AppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create source image"])
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let flattenedContext = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "AppIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create flattened bitmap"])
    }
    flattenedContext.draw(sourceImage, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard
        let flattenedImage = flattenedContext.makeImage(),
        let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw NSError(domain: "AppIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
    }
    CGImageDestinationAddImage(destination, flattenedImage, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "AppIcon", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG"])
    }
}

let variant = Variant(
    bgTop: .hex(0xBFEFFF),
    bgBottom: .hex(0x1D6A7A),
    glow: .hex(0xFFFFFF, alpha: 0.55),
    cardFillTop: .hex(0xFFFFFF, alpha: 0.35),
    cardFillBottom: .hex(0xC9F2FF, alpha: 0.08),
    cardStroke: .hex(0xFFFFFF, alpha: 0.50),
    sheetFillTop: .hex(0xFFFFFF, alpha: 0.30),
    sheetFillBottom: .hex(0xD6F5FF, alpha: 0.08),
    sheetStroke: .hex(0xFFFFFF, alpha: 0.38),
    lineColor: .hex(0x0F7D8C, alpha: 0.55)
)

let outputs: [(filename: String, pixels: Int)] = [
    ("ios-20@2x.png", 40),
    ("ios-20@3x.png", 60),
    ("ios-29@2x.png", 58),
    ("ios-29@3x.png", 87),
    ("ios-40@2x.png", 80),
    ("ios-40@3x.png", 120),
    ("ios-60@2x.png", 120),
    ("ios-60@3x.png", 180),
    ("ipad-20.png", 20),
    ("ipad-20@2x.png", 40),
    ("ipad-29.png", 29),
    ("ipad-29@2x.png", 58),
    ("ipad-40.png", 40),
    ("ipad-40@2x.png", 80),
    ("ipad-76.png", 76),
    ("ipad-76@2x.png", 152),
    ("ipad-83.5@2x.png", 167),
    ("icon-1024.png", 1024),
    ("icon-16.png", 16),
    ("icon-16@2x.png", 32),
    ("icon-32.png", 32),
    ("icon-32@2x.png", 64),
    ("icon-128.png", 128),
    ("icon-128@2x.png", 256),
    ("icon-256.png", 256),
    ("icon-256@2x.png", 512),
    ("icon-512.png", 512),
    ("icon-512@2x.png", 1024)
]

let outputDir: URL
if CommandLine.arguments.count > 1 {
    outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
} else {
    let repoIconComposerFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("NoteLab/AppIcon.icon", isDirectory: true)
    if FileManager.default.fileExists(atPath: repoIconComposerFile.path) {
        fail("NoteLab uses NoteLab/AppIcon.icon as the app icon source. Pass an explicit output directory to generate legacy PNG exports.")
    }
    outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for output in outputs {
    let url = outputDir.appendingPathComponent(output.filename)
    try drawIcon(variant: variant, size: output.pixels, outputURL: url)
}
