import Foundation
#if canImport(UIKit)
import UIKit
import CoreHaptics

enum HapticSource {
    case globalTap
    case explicit
}

enum HapticTapStyle {
    case light
    case medium
    case heavy
}

enum HapticEvent {
    case tap(HapticTapStyle)
    case selection
    case success
    case warning
    case error
    case long(duration: TimeInterval, intensity: Float = 0.75, sharpness: Float = 0.5)
}

final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private var supportsHaptics = false
    private var lastExplicitTime: TimeInterval = 0
    private var pendingGlobalWorkItem: DispatchWorkItem?

    private init() {
        prepareEngine()
    }

    func play(_ event: HapticEvent, source: HapticSource = .explicit) {
        switch source {
        case .globalTap:
            scheduleGlobalTap(event)
        case .explicit:
            pendingGlobalWorkItem?.cancel()
            pendingGlobalWorkItem = nil
            lastExplicitTime = CACurrentMediaTime()
            DispatchQueue.main.async { [weak self] in
                self?.execute(event)
            }
        }
    }

    private func scheduleGlobalTap(_ event: HapticEvent) {
        pendingGlobalWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let sinceExplicit = CACurrentMediaTime() - self.lastExplicitTime
            if sinceExplicit < 0.04 {
                return
            }
            self.execute(event)
        }
        pendingGlobalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015, execute: workItem)
    }

    private func execute(_ event: HapticEvent) {
        switch event {
        case .tap(let style):
            playImpact(style)
        case .selection:
            playSelection()
        case .success:
            playNotification(.success)
        case .warning:
            playNotification(.warning)
        case .error:
            playNotification(.error)
        case .long(let duration, let intensity, let sharpness):
            playContinuous(duration: duration, intensity: intensity, sharpness: sharpness)
        }
    }

    private func playImpact(_ style: HapticTapStyle) {
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light:
            feedbackStyle = .light
        case .medium:
            feedbackStyle = .medium
        case .heavy:
            feedbackStyle = .heavy
        }
        let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
        generator.prepare()
        generator.impactOccurred()
    }

    private func playSelection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    private func playNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private func playContinuous(duration: TimeInterval, intensity: Float, sharpness: Float) {
        guard supportsHaptics else {
            playImpact(.heavy)
            return
        }

        do {
            if engine == nil {
                try prepareEngine()
            }
            try engine?.start()
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: 0,
                duration: duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            playImpact(.heavy)
        }
    }

    @discardableResult
    private func prepareEngine() -> Bool {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard supportsHaptics else { return false }
        do {
            engine = try CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            try engine?.start()
            return true
        } catch {
            supportsHaptics = false
            engine = nil
            return false
        }
    }
}
#else
enum HapticSource {
    case globalTap
    case explicit
}

enum HapticTapStyle {
    case light
    case medium
    case heavy
}

enum HapticEvent {
    case tap(HapticTapStyle)
    case selection
    case success
    case warning
    case error
    case long(duration: TimeInterval, intensity: Float = 0.75, sharpness: Float = 0.5)
}

final class Haptics {
    static let shared = Haptics()
    private init() {}

    func play(_ event: HapticEvent, source: HapticSource = .explicit) {
        // No-op on platforms without UIKit haptics.
        _ = event
        _ = source
    }
}
#endif