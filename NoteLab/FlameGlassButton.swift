import SwiftUI

struct FlameGlassButtonBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { proxy in
                let t = timeline.date.timeIntervalSinceReferenceDate

                Rectangle()
                    .fill(.black)
                    .colorEffect(
                        ShaderLibrary.flameGlass(
                            .float2(Float(proxy.size.width), Float(proxy.size.height)),
                            .float(Float(t.truncatingRemainder(dividingBy: 60)))
                        )
                    )
            }
        }
        .saturation(1.34)
        .contrast(1.42)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.22),
                            .white.opacity(0.18),
                            .orange.opacity(0.42)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.4
                )
        }
        .shadow(color: .purple.opacity(0.14), radius: 5, x: 0, y: -2)
        .shadow(color: .orange.opacity(0.22), radius: 7, x: 0, y: 4)
    }
}

#Preview {
    FlameGlassButtonBackground()
        .frame(width: 64, height: 64)
        .padding()
        .background(.black)
}
