import SwiftUI
import Combine

enum AppRoute: Hashable {
    case notebook(UUID)
    case note(UUID)
    case whiteboard
    case recentFocus
}

final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()
    @Published private(set) var isTransitioning = false
    
    /// Keeps track of routes for validation purposes
    private var routeStack: [AppRoute] = []

    func push(_ route: AppRoute) {
        isTransitioning = true
        routeStack.append(route)
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
            if !routeStack.isEmpty {
                routeStack.removeLast()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.isTransitioning = false
            }
        }
    }

    func reset() {
        path = NavigationPath()
        routeStack = []
        isTransitioning = false
    }
    
    /// Remove routes that reference non-existent notebooks or notes.
    /// Call this after data refresh to ensure navigation path is valid.
    func pruneInvalidRoutes(validNotebookIds: Set<UUID>, validNoteIds: Set<UUID>) {
        var newStack: [AppRoute] = []
        var needsRebuild = false
        
        for route in routeStack {
            switch route {
            case .notebook(let id):
                if validNotebookIds.contains(id) {
                    newStack.append(route)
                } else {
                    needsRebuild = true
                }
            case .note(let id):
                if validNoteIds.contains(id) {
                    newStack.append(route)
                } else {
                    needsRebuild = true
                }
            case .whiteboard, .recentFocus:
                newStack.append(route)
            }
        }
        
        if needsRebuild {
            routeStack = newStack
            // Rebuild NavigationPath from valid routes
            path = NavigationPath()
            for route in newStack {
                path.append(route)
            }
        }
    }
}
