import SwiftUI
#if canImport(UIKit)
import UIKit

struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? Controller)?.enableSoon()
    }

    private final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSoon()
        }

        func enableSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.navigationControllerInHierarchy()?.interactivePopGestureRecognizer.map {
                    $0.isEnabled = true
                    $0.delegate = nil
                }
            }
        }

        private func navigationControllerInHierarchy() -> UINavigationController? {
            if let navigationController { return navigationController }
            var controller = parent
            while let current = controller {
                if let navigationController = current as? UINavigationController {
                    return navigationController
                }
                controller = current.parent
            }
            return nil
        }
    }
}
#else
struct InteractivePopGestureEnabler: View {
    var body: some View {
        EmptyView()
    }
}
#endif
