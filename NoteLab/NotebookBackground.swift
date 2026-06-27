import CoreGraphics
import Foundation

enum NotebookBackground: String, CaseIterable, Hashable {
    case `default`
    case softStudio
    case quietLilac
    case freshAir
    case calmMinimal
    case peachMilk
    case paperGarden
    case moonGlass
    case bareNote

    nonisolated static func normalized(_ rawValue: String?) -> NotebookBackground {
        guard let rawValue,
              let background = NotebookBackground(rawValue: rawValue) else {
            return .default
        }
        return background
    }

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "默认"
        case .softStudio: return "柔和手账"
        case .quietLilac: return "安静灵感"
        case .freshAir: return "清爽脚本"
        case .calmMinimal: return "项目稿纸"
        case .peachMilk: return "生活记录"
        case .paperGarden: return "花园备忘"
        case .moonGlass: return "夜间专注"
        case .bareNote: return "极简笔记"
        }
    }

    nonisolated var generatedStyle: NotebookBackgroundStyle? {
        switch self {
        case .default: return nil
        case .softStudio: return NotebookBackgroundStyle(baseHex: "F8F2EA", washHex: "FFF7F0", markHex: "CFAF91", inkHex: "25211F", secondaryInkHex: "655B55", pattern: .ruled, spacing: 34, opacity: 0.34)
        case .quietLilac: return NotebookBackgroundStyle(baseHex: "F4F0FA", washHex: "FBF7FF", markHex: "B8A8D9", inkHex: "252230", secondaryInkHex: "635D70", pattern: .dots, spacing: 30, opacity: 0.30)
        case .freshAir: return NotebookBackgroundStyle(baseHex: "EEF8F5", washHex: "F8FFFD", markHex: "9BCDC3", inkHex: "1F2D2B", secondaryInkHex: "58706B", pattern: .grid, spacing: 36, opacity: 0.28)
        case .calmMinimal: return NotebookBackgroundStyle(baseHex: "F7F7F0", washHex: "FFFFFA", markHex: "C9C8B9", inkHex: "26261F", secondaryInkHex: "68685D", pattern: .ruled, spacing: 40, opacity: 0.30)
        case .peachMilk: return NotebookBackgroundStyle(baseHex: "FFF1EC", washHex: "FFF9F4", markHex: "E8B49D", inkHex: "2E211D", secondaryInkHex: "715E56", pattern: .softGrid, spacing: 38, opacity: 0.30)
        case .paperGarden: return NotebookBackgroundStyle(baseHex: "F1F7EC", washHex: "FBFFF7", markHex: "A8C79A", inkHex: "22301F", secondaryInkHex: "5B7055", pattern: .dots, spacing: 34, opacity: 0.32)
        case .moonGlass: return NotebookBackgroundStyle(baseHex: "22262D", washHex: "303744", markHex: "8291A8", inkHex: "F4F7FB", secondaryInkHex: "B9C3D2", pattern: .grid, spacing: 38, opacity: 0.24)
        case .bareNote: return NotebookBackgroundStyle(baseHex: "FAFAF6", washHex: "FFFFFF", markHex: "D7D3C5", inkHex: "242420", secondaryInkHex: "66645C", pattern: .ruled, spacing: 44, opacity: 0.26)
        }
    }

    nonisolated var darkGeneratedStyle: NotebookBackgroundStyle? {
        switch self {
        case .default: return nil
        case .softStudio: return NotebookBackgroundStyle(baseHex: "241F1A", washHex: "302820", markHex: "8C7463", inkHex: "F8F0E8", secondaryInkHex: "D0BFB0", pattern: .ruled, spacing: 34, opacity: 0.26)
        case .quietLilac: return NotebookBackgroundStyle(baseHex: "201F2A", washHex: "2C2940", markHex: "8075AE", inkHex: "F4F0FF", secondaryInkHex: "C4BDE1", pattern: .dots, spacing: 30, opacity: 0.30)
        case .freshAir: return NotebookBackgroundStyle(baseHex: "172822", washHex: "223A32", markHex: "5EA494", inkHex: "EFFBF7", secondaryInkHex: "B7D8D0", pattern: .grid, spacing: 36, opacity: 0.24)
        case .calmMinimal: return NotebookBackgroundStyle(baseHex: "20221D", washHex: "2C2F28", markHex: "757A67", inkHex: "F4F5EC", secondaryInkHex: "C4C7B8", pattern: .ruled, spacing: 40, opacity: 0.25)
        case .peachMilk: return NotebookBackgroundStyle(baseHex: "2B211F", washHex: "3A2B27", markHex: "A87565", inkHex: "FFF0EA", secondaryInkHex: "D9B9AE", pattern: .softGrid, spacing: 38, opacity: 0.24)
        case .paperGarden: return NotebookBackgroundStyle(baseHex: "1B281B", washHex: "263625", markHex: "78A06E", inkHex: "F1FBEF", secondaryInkHex: "BBD3B3", pattern: .dots, spacing: 34, opacity: 0.28)
        case .moonGlass: return NotebookBackgroundStyle(baseHex: "151922", washHex: "232A36", markHex: "6E809E", inkHex: "F4F7FB", secondaryInkHex: "BAC7D8", pattern: .grid, spacing: 38, opacity: 0.26)
        case .bareNote: return NotebookBackgroundStyle(baseHex: "22231F", washHex: "2F3029", markHex: "7A7665", inkHex: "F8F7EE", secondaryInkHex: "C8C5B6", pattern: .ruled, spacing: 44, opacity: 0.24)
        }
    }

    nonisolated func generatedStyle(isDarkMode: Bool) -> NotebookBackgroundStyle? {
        isDarkMode ? darkGeneratedStyle : generatedStyle
    }

    nonisolated func usesLightForeground(isDarkMode: Bool) -> Bool {
        generatedStyle(isDarkMode: isDarkMode)?.usesLightForeground ?? false
    }

    nonisolated var usesLightForeground: Bool {
        usesLightForeground(isDarkMode: false)
    }
}

struct NotebookBackgroundStyle: Hashable {
    enum Pattern: Hashable {
        case ruled
        case grid
        case softGrid
        case dots
    }

    let baseHex: String
    let washHex: String
    let markHex: String
    let inkHex: String
    let secondaryInkHex: String
    let pattern: Pattern
    let spacing: CGFloat
    let opacity: Double

    nonisolated var usesLightForeground: Bool {
        rgbComponents(hex: baseHex).luminance < 0.42
    }

    nonisolated private func rgbComponents(hex: String) -> (red: Double, green: Double, blue: Double, luminance: Double) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return (red, green, blue, luminance)
    }
}
