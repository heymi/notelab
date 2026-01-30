import SwiftUI

struct WavyNotebookShape: Shape {
    var cornerRadius: CGFloat = 26
    var notchDepth: CGFloat = 16
    var notchHeight: CGFloat = 54

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) * 0.22)
        let depth = min(notchDepth, rect.width * 0.18)
        let height = min(notchHeight, rect.height * 0.5)
        let centerY = rect.midY
        let notchTop = centerY - height * 0.5
        let notchBottom = centerY + height * 0.5

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: notchTop))
        path.addCurve(
            to: CGPoint(x: rect.maxX - depth, y: centerY),
            control1: CGPoint(x: rect.maxX, y: notchTop + height * 0.12),
            control2: CGPoint(x: rect.maxX - depth, y: centerY - height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: notchBottom),
            control1: CGPoint(x: rect.maxX - depth, y: centerY + height * 0.22),
            control2: CGPoint(x: rect.maxX, y: notchBottom - height * 0.12)
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct NotebookPageShape: Shape {
    var cornerRadius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) * 0.22)
        return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)
    }
}
