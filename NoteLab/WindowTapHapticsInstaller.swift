import SwiftUI
#if canImport(UIKit)
import UIKit
import ObjectiveC

struct WindowTapHapticsInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> WindowTapHapticsView {
        let view = WindowTapHapticsView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: WindowTapHapticsView, context: Context) {}
}

final class WindowTapHapticsView: UIView, UIGestureRecognizerDelegate {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else { return }
        installTapRecognizerIfNeeded(in: window)
    }

    private func installTapRecognizerIfNeeded(in window: UIWindow) {
        if window.noteLabHasTapHaptics {
            return
        }
        window.noteLabHasTapHaptics = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        Haptics.shared.play(.tap(.light), source: .globalTap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        return !isTextInput(view)
    }

    private func isTextInput(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            if node is UITextView || node is UITextField {
                return true
            }
            current = node.superview
        }
        return false
    }
}

private var noteLabTapHapticsKey: UInt8 = 0

private extension UIWindow {
    var noteLabHasTapHaptics: Bool {
        get {
            (objc_getAssociatedObject(self, &noteLabTapHapticsKey) as? Bool) ?? false
        }
        set {
            objc_setAssociatedObject(self, &noteLabTapHapticsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
#else
struct WindowTapHapticsInstaller: View {
    var body: some View {
        EmptyView()
    }
}
#endif