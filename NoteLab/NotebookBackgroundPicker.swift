import SwiftUI

extension NotebookBackground {
    func generatedStyle(for colorScheme: ColorScheme) -> NotebookBackgroundStyle? {
        generatedStyle(isDarkMode: colorScheme == .dark)
    }

    func swiftUIInk(for colorScheme: ColorScheme) -> Color {
        guard let style = generatedStyle(for: colorScheme) else { return Theme.ink }
        return Color(hex: style.inkHex)
    }

    func swiftUISecondaryInk(for colorScheme: ColorScheme) -> Color {
        guard let style = generatedStyle(for: colorScheme) else { return Theme.secondaryInk }
        return Color(hex: style.secondaryInkHex)
    }
}

struct NotebookBackgroundPicker: View {
    @Binding var selection: NotebookBackground
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(NotebookBackground.allCases, id: \.self) { background in
                    backgroundButton(background)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private func backgroundButton(_ background: NotebookBackground) -> some View {
        let isSelected = selection == background
        return Button {
            Haptics.shared.play(.selection)
            selection = background
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                preview(for: background)
                    .frame(width: 118, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Theme.ink : Theme.editorLine.opacity(0.6), lineWidth: isSelected ? 2 : 0.7)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(7)
                        }
                    }

                Text(background.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.secondaryInk)
                    .lineLimit(1)
            }
            .frame(width: 118, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func preview(for background: NotebookBackground) -> some View {
        ZStack(alignment: .topLeading) {
            if let style = background.generatedStyle(for: colorScheme) {
                GeneratedNotebookBackgroundSurface(style: style)
            } else {
                Theme.editorBackground
                LinearGradient(
                    colors: [Theme.editorTopWash.opacity(0.65), Theme.editorBackground.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            Color.white.opacity(0.08)

            VStack(alignment: .leading, spacing: 5) {
                Capsule()
                    .fill(background.swiftUIInk(for: colorScheme).opacity(0.64))
                    .frame(width: 58, height: 7)
                Capsule()
                    .fill(background.swiftUIInk(for: colorScheme).opacity(0.32))
                    .frame(width: 82, height: 5)
                Capsule()
                    .fill(background.swiftUIInk(for: colorScheme).opacity(0.24))
                    .frame(width: 66, height: 5)
            }
            .padding(12)
        }
    }
}

struct GeneratedNotebookBackgroundSurface: View {
    let style: NotebookBackgroundStyle
    var contentOffsetY: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: style.washHex), Color(hex: style.baseHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Canvas { context, size in
                    let color = Color(hex: style.markHex).opacity(style.opacity)
                    let spacing = max(24, style.spacing)
                    let phase = -(contentOffsetY.truncatingRemainder(dividingBy: spacing))
                    var path = Path()
                    switch style.pattern {
                    case .ruled:
                        var y = phase
                        while y < size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            y += spacing
                        }
                        context.stroke(path, with: .color(color), lineWidth: 1)
                    case .grid, .softGrid:
                        var x: CGFloat = 0
                        while x < size.width {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            x += spacing
                        }
                        var y = phase
                        while y < size.height {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            y += spacing
                        }
                        context.stroke(path, with: .color(color), lineWidth: style.pattern == .softGrid ? 0.7 : 1)
                    case .dots:
                        var y = phase
                        while y < size.height {
                            var x = spacing * 0.5
                            while x < size.width {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(color))
                                x += spacing
                            }
                            y += spacing
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}
