import AppKit

struct Variant {
    let name: String
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

func drawIcon(variant: Variant, outputURL: URL) throws {
    let size = 1024
    let sizeF = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: sizeF, height: sizeF)

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
        bitsPerPixel: 0
    )
    guard let bitmap = rep else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap"])
    }

    let ctx = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current = ctx

    let bgGradient = NSGradient(colors: [variant.bgTop, variant.bgBottom])
    bgGradient?.draw(in: rect, angle: 90)

    let glowGradient = NSGradient(colors: [variant.glow, NSColor.clear])
    glowGradient?.draw(fromCenter: NSPoint(x: sizeF * 0.22, y: sizeF * 0.82), radius: sizeF * 0.08, toCenter: NSPoint(x: sizeF * 0.22, y: sizeF * 0.82), radius: sizeF * 0.62, options: [])

    let vignette = NSGradient(colors: [NSColor.clear, NSColor.black.withAlphaComponent(0.18)])
    vignette?.draw(in: rect, angle: 90)

    let cardWidth: CGFloat = 700
    let cardHeight: CGFloat = 760
    let cardRect = NSRect(
        x: (CGFloat(size) - cardWidth) / 2,
        y: (CGFloat(size) - cardHeight) / 2,
        width: cardWidth,
        height: cardHeight
    )
    let cardRadius: CGFloat = 150

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()

    let cardPath = drawRoundedRect(cardRect, radius: cardRadius)
    let cardGradient = NSGradient(colors: [variant.cardFillTop, variant.cardFillBottom])
    cardGradient?.draw(in: cardPath, angle: 90)

    NSShadow().set()
    variant.cardStroke.setStroke()
    cardPath.lineWidth = 3
    cardPath.stroke()

    let highlightRect = cardRect.insetBy(dx: 40, dy: 40)
    let highlightPath = drawRoundedRect(highlightRect, radius: cardRadius - 40)
    let highlightGradient = NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0.02)])
    highlightGradient?.draw(in: highlightPath, angle: 90)

    let sheetRect = cardRect.insetBy(dx: 130, dy: 160)
    let sheetRadius = cardRadius - 70
    let sheetPath = drawRoundedRect(sheetRect, radius: sheetRadius)
    let sheetGradient = NSGradient(colors: [variant.sheetFillTop, variant.sheetFillBottom])
    sheetGradient?.draw(in: sheetPath, angle: 90)

    variant.sheetStroke.setStroke()
    sheetPath.lineWidth = 2
    sheetPath.stroke()

    let foldSize: CGFloat = 90
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

    let lineInset: CGFloat = 90
    let lineHeight: CGFloat = 34
    let lineGap: CGFloat = 40
    let firstLineY = sheetRect.maxY - 190

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

    let accentCircle = NSBezierPath(ovalIn: NSRect(x: cardRect.minX + 90, y: cardRect.minY + 120, width: 140, height: 140))
    NSColor.white.withAlphaComponent(0.16).setFill()
    accentCircle.fill()

    let pngData = bitmap.representation(using: .png, properties: [:])
    guard let data = pngData else {
        throw NSError(domain: "AppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }
    try data.write(to: outputURL)
}

let variants: [Variant] = [
    Variant(
        name: "icon-1024",
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
    ),
    Variant(
        name: "icon-1024-dark",
        bgTop: .hex(0x0A1A24),
        bgBottom: .hex(0x124355),
        glow: .hex(0x7FD6FF, alpha: 0.45),
        cardFillTop: .hex(0xFFFFFF, alpha: 0.22),
        cardFillBottom: .hex(0x74B9D4, alpha: 0.06),
        cardStroke: .hex(0xFFFFFF, alpha: 0.42),
        sheetFillTop: .hex(0xFFFFFF, alpha: 0.18),
        sheetFillBottom: .hex(0x6AA5C0, alpha: 0.05),
        sheetStroke: .hex(0xFFFFFF, alpha: 0.32),
        lineColor: .hex(0xBFEFFF, alpha: 0.50)
    ),
    Variant(
        name: "icon-1024-tinted",
        bgTop: .hex(0xF3F6F8),
        bgBottom: .hex(0xDDE6EE),
        glow: .hex(0xFFFFFF, alpha: 0.50),
        cardFillTop: .hex(0xFFFFFF, alpha: 0.30),
        cardFillBottom: .hex(0xDCE6EE, alpha: 0.10),
        cardStroke: .hex(0xFFFFFF, alpha: 0.55),
        sheetFillTop: .hex(0xFFFFFF, alpha: 0.26),
        sheetFillBottom: .hex(0xE2E9EF, alpha: 0.08),
        sheetStroke: .hex(0xFFFFFF, alpha: 0.40),
        lineColor: .hex(0x5E6C76, alpha: 0.55)
    )
]

let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
for variant in variants {
    let url = outputDir.appendingPathComponent("\(variant.name).png")
    try drawIcon(variant: variant, outputURL: url)
}
