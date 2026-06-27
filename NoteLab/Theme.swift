import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum Theme {
    static let background = Color(light: Color(red: 0.96, green: 0.96, blue: 0.96),
                                 dark: Color(red: 0.09, green: 0.09, blue: 0.11))
    
    static let ink = Color(light: Color(red: 0.10, green: 0.10, blue: 0.12),
                           dark: Color(red: 0.94, green: 0.94, blue: 0.96))
    
    static let secondaryInk = Color(light: Color(red: 0.42, green: 0.42, blue: 0.45),
                                    dark: Color(red: 0.60, green: 0.60, blue: 0.65))
    
    static let cardShadow = Color(light: Color.black.opacity(0.15),
                                  dark: Color.black.opacity(0.3))
    
    static let softShadow = Color(light: Color.black.opacity(0.08),
                                  dark: Color.black.opacity(0.2))
    
    static let glass = Color(light: Color.white.opacity(0.7),
                             dark: Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.7))
    
    static let pillBlack = Color(light: Color(red: 0.08, green: 0.08, blue: 0.10),
                                 dark: Color(red: 0.18, green: 0.18, blue: 0.21))
    
    static let cardBackground = Color(light: .white,
                                      dark: Color(red: 0.14, green: 0.14, blue: 0.16))
    
    static let paper = Color(light: Color(red: 0.94, green: 0.95, blue: 0.97),
                             dark: Color(red: 0.16, green: 0.16, blue: 0.19))
    
    static let groupedBackground = Color(light: Color.black.opacity(0.05),
                                         dark: Color.white.opacity(0.08))

    // Note detail surface
    static let editorBackground = Color(light: Color(red: 0.985, green: 0.980, blue: 0.955),
                                        dark: Color(red: 0.075, green: 0.083, blue: 0.090))

    static let editorTopWash = Color(light: Color(red: 0.895, green: 0.950, blue: 0.925),
                                     dark: Color(red: 0.080, green: 0.155, blue: 0.160))

    static let editorPaper = Color(light: Color(red: 0.995, green: 0.990, blue: 0.970),
                                   dark: Color(red: 0.125, green: 0.130, blue: 0.140))

    static let editorPaperSoft = Color(light: Color(red: 0.955, green: 0.958, blue: 0.930),
                                       dark: Color(red: 0.165, green: 0.175, blue: 0.180))

    static let editorLine = Color(light: Color(red: 0.875, green: 0.870, blue: 0.825),
                                  dark: Color(red: 0.255, green: 0.265, blue: 0.275))

    static let editorAccent = Color(light: Color(red: 0.290, green: 0.620, blue: 0.560),
                                    dark: Color(red: 0.425, green: 0.760, blue: 0.700))

    static let editorAccentDeep = Color(light: Color(red: 0.135, green: 0.335, blue: 0.345),
                                        dark: Color(red: 0.610, green: 0.860, blue: 0.820))

    static let editorQuiet = Color(light: Color(red: 0.620, green: 0.650, blue: 0.630),
                                   dark: Color(red: 0.520, green: 0.560, blue: 0.565))
    
    // UI Constants
    static let cornerRadius: CGFloat = 22
    static let buttonHeight: CGFloat = 56
    static let inputHeight: CGFloat = 54
}

#if canImport(UIKit)
extension UIColor {
    static var noteEditorInk: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1) :
                UIColor(red: 0.15, green: 0.18, blue: 0.18, alpha: 1)
        }
    }

    static var noteEditorBody: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.82, green: 0.84, blue: 0.84, alpha: 1) :
                UIColor(red: 0.25, green: 0.29, blue: 0.29, alpha: 1)
        }
    }

    static var noteEditorSecondaryInk: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.62, green: 0.65, blue: 0.66, alpha: 1) :
                UIColor(red: 0.47, green: 0.50, blue: 0.49, alpha: 1)
        }
    }

    static var noteEditorPaper: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.125, green: 0.130, blue: 0.140, alpha: 1) :
                UIColor(red: 0.995, green: 0.990, blue: 0.970, alpha: 1)
        }
    }

    static var noteEditorPaperSoft: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.165, green: 0.175, blue: 0.180, alpha: 1) :
                UIColor(red: 0.955, green: 0.958, blue: 0.930, alpha: 1)
        }
    }

    static var noteEditorLine: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.255, green: 0.265, blue: 0.275, alpha: 1) :
                UIColor(red: 0.875, green: 0.870, blue: 0.825, alpha: 1)
        }
    }

    static var noteEditorAccent: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.425, green: 0.760, blue: 0.700, alpha: 1) :
                UIColor(red: 0.290, green: 0.620, blue: 0.560, alpha: 1)
        }
    }

    static var noteEditorAccentDeep: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.610, green: 0.860, blue: 0.820, alpha: 1) :
                UIColor(red: 0.135, green: 0.335, blue: 0.345, alpha: 1)
        }
    }

    static var noteEditorSelection: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.200, green: 0.300, blue: 0.295, alpha: 0.72) :
                UIColor(red: 0.845, green: 0.930, blue: 0.895, alpha: 1.0)
        }
    }
}
#endif

extension Color {
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        } ?? NSColor(light))
        #else
        self = light
        #endif
    }
    
    static func notebook(_ color: NotebookColor) -> Color {
        switch color {
        case .lime:
            return Color(red: 0.67, green: 0.98, blue: 0.35)
        case .sky:
            return Color(red: 0.77, green: 0.93, blue: 0.98)
        case .orange:
            return Color(red: 0.98, green: 0.69, blue: 0.35)
        case .lavender:
            return Color(red: 0.78, green: 0.76, blue: 0.83)
        case .mint:
            return Color(red: 0.78, green: 0.92, blue: 0.78)
        case .teal:
            return Color(red: 0.47, green: 0.78, blue: 0.78)
        case .sand:
            return Color(red: 0.92, green: 0.87, blue: 0.76)
        }
    }
}

extension Color {
    static var systemBackgroundAdaptive: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.white
        #endif
    }
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
