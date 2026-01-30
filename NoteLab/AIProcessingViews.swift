import SwiftUI

struct ThinkingIndicatorView: View {
    let text: String
    let icon: String
    let fontSize: CGFloat
    let iconSize: CGFloat
    let gradientColors: [Color]
    let letterSpacing: CGFloat

    @State private var thinking = false

    init(
        text: String = "Thinking",
        icon: String = "sparkles",
        fontSize: CGFloat = 18,
        iconSize: CGFloat = 16,
        gradientColors: [Color] = [Color.blue, Color.indigo],
        letterSpacing: CGFloat = 0
    ) {
        self.text = text
        self.icon = icon
        self.fontSize = fontSize
        self.iconSize = iconSize
        self.gradientColors = gradientColors
        self.letterSpacing = letterSpacing
    }

    var body: some View {
        let gradient = EllipticalGradient(
            colors: gradientColors,
            center: .center,
            startRadiusFraction: 0.0,
            endRadiusFraction: 0.6
        )

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                .foregroundStyle(gradient)

            HStack(spacing: letterSpacing) {
                ForEach(Array(text).enumerated(), id: \.offset) { index, letter in
                    Text(String(letter))
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(gradient)
                        .hueRotation(.degrees(thinking ? 220 : 0))
                        .opacity(thinking ? 0.55 : 1)
                        .scaleEffect(thinking ? 1.08 : 1, anchor: .bottom)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .delay(1.0 + Double(index) / 20)
                                .repeatForever(autoreverses: false),
                            value: thinking
                        )
                }
            }
        }
        .onAppear { thinking = true }
    }
}

struct AIStageStepper: View {
    let stages: [String]
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(stages.indices, id: \.self) { index in
                let isCompleted = index < currentIndex
                let isCurrent = index == currentIndex
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isCompleted || isCurrent ? Theme.ink : Theme.secondaryInk.opacity(0.2))
                            .frame(width: isCurrent ? 10 : 8, height: isCurrent ? 10 : 8)
                            .animation(.easeInOut(duration: 0.2), value: currentIndex)
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 6, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(stages[index])
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isCompleted || isCurrent ? Theme.ink : Theme.secondaryInk)
                }
                if index < stages.count - 1 {
                    Rectangle()
                        .fill(isCompleted ? Theme.ink : Theme.secondaryInk.opacity(0.2))
                        .frame(width: 12, height: 1)
                        .offset(y: -8)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
