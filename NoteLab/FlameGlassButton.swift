import Combine
#if os(iOS)
import CoreMotion
#endif
import SwiftUI

struct FlameGlassButtonBackground: View {
    @StateObject private var motion = FlameGlassMotion()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            GeometryReader { proxy in
                let t = timeline.date.timeIntervalSinceReferenceDate

                Rectangle()
                    .fill(.black)
                    .colorEffect(
                        ShaderLibrary.flameGlass(
                            .float2(Float(proxy.size.width), Float(proxy.size.height)),
                            .float(Float(t.truncatingRemainder(dividingBy: 60))),
                            .float2(motion.tilt.x, motion.tilt.y)
                        )
                    )
            }
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
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

private final class FlameGlassMotion: ObservableObject {
    @Published var tilt = SIMD2<Float>(repeating: 0)

    #if os(iOS)
    private let manager = CMMotionManager()
    #endif

    func start() {
        #if os(iOS)
        guard manager.isDeviceMotionAvailable, manager.isDeviceMotionActive == false else { return }

        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            self?.tilt = SIMD2(
                Float(max(-1.0, min(1.0, gravity.x))),
                Float(max(-1.0, min(1.0, gravity.z)))
            )
        }
        #endif
    }

    func stop() {
        #if os(iOS)
        manager.stopDeviceMotionUpdates()
        #endif
    }
}

#Preview {
    FlameGlassButtonBackground()
        .frame(width: 64, height: 64)
        .padding()
        .background(.black)
}
