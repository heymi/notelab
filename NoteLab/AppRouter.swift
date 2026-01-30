import SwiftUI
import Combine

enum AppRoute: Hashable {
    case notebook(UUID)
    case note(UUID)
    case whiteboard
    case recentFocus
}

final class AppRouter: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published private(set) var isTransitioning = false

    func push(_ route: AppRoute) {
        isTransitioning = true
        path.append(route)
        // 延迟重置，等待转场动画完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.isTransitioning = false
        }
    }

    func pop() {
        if !path.isEmpty {
            isTransitioning = true
            path.removeLast()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.isTransitioning = false
            }
        }
    }

    func reset() {
        path = []
        isTransitioning = false
    }
    
    /// Remove routes that reference non-existent notebooks or notes.
    /// Call this after data refresh to ensure navigation path is valid.
    func pruneInvalidRoutes(validNotebookIds: Set<UUID>, validNoteIds: Set<UUID>) {
        let filtered = path.filter { route in
            switch route {
            case .notebook(let id):
                return validNotebookIds.contains(id)
            case .note(let id):
                return validNoteIds.contains(id)
            case .whiteboard, .recentFocus:
                return true
            }
        }
        if filtered != path {
            path = filtered
        }
    }
}
