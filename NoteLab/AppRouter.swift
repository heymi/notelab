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
    private var transitionResetTask: Task<Void, Never>?

    func push(_ route: AppRoute) {
        isTransitioning = true
        path.append(route)
        scheduleTransitionReset()
    }

    func pop() {
        guard !path.isEmpty else { return }
        isTransitioning = true
        path.removeLast()
        scheduleTransitionReset()
    }

    func reset() {
        path = []
        isTransitioning = false
        transitionResetTask?.cancel()
        transitionResetTask = nil
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

    private func scheduleTransitionReset() {
        transitionResetTask?.cancel()
        transitionResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.isTransitioning = false
            }
        }
    }
}
