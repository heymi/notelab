import SwiftUI
import Combine
import SwiftData
import os

enum AppTab: String, CaseIterable {
    case library
    case list
    case whiteboard
    case plan
    case search
    case settings
}

struct RootView: View {
    @AppStorage("launchPage") private var launchPageString: String = "library"
    @State private var selection: AppTab = .library
    @StateObject private var store = NotebookStore()
    @StateObject private var aiClient = AIClient()
    @StateObject private var aiCenter = AIProcessingCenter()
    @StateObject private var planStore = PlanStore()
    @StateObject private var router = AppRouter()
    @StateObject private var syncEngine = SyncEngine()
    @StateObject private var avatarStore = AvatarStore()
    @State private var syncTask: Task<Void, Never>?
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let syncLogger = Logger(subsystem: "NoteLab", category: "Sync")

    var body: some View {
        platformContent
            .environmentObject(store)
            .environmentObject(aiClient)
            .environmentObject(aiCenter)
            .environmentObject(planStore)
            .environmentObject(router)
            .environmentObject(avatarStore)
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        macOSLayout
            .task(id: auth.userId) {
                syncTask?.cancel()
                avatarStore.updateUserId(auth.userId)
                guard let userId = auth.userId else { return }
                // Small delay to ensure modelContext is fully ready
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                guard !Task.isCancelled else { return }
                store.configure(ownerId: userId, context: modelContext)
                syncEngine.configure(ownerId: userId, context: modelContext)
                startSync()
            }
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                startSync()
            }
            .onChange(of: auth.userId) { _, newValue in
                if newValue == nil {
                    handleSignOutCleanup()
                }
            }
            .onDisappear {
                syncTask?.cancel()
                syncTask = nil
            }
            .onAppear {
                if let tab = AppTab(rawValue: launchPageString) {
                    selection = tab
                }
            }
        #else
        iOSLayout
            .onChange(of: selection) { _, newValue in
                // #region agent log
                DebugReporter.log(
                    hypothesisId: "H2",
                    location: "RootView.swift:onChange(selection)",
                    message: "tab changed",
                    data: ["tab": newValue.rawValue]
                )
                // #endregion
            }
            .task(id: auth.userId) {
                syncTask?.cancel()
                avatarStore.updateUserId(auth.userId)
                guard let userId = auth.userId else { return }
                // Small delay to ensure modelContext is fully ready
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
                guard !Task.isCancelled else { return }
                store.configure(ownerId: userId, context: modelContext)
                syncEngine.configure(ownerId: userId, context: modelContext)
                startSync()
            }
            .onChange(of: scenePhase) { _, newValue in
                guard newValue == .active else { return }
                startSync()
            }
            .onChange(of: auth.userId) { _, newValue in
                if newValue == nil {
                    handleSignOutCleanup()
                }
                avatarStore.updateUserId(newValue)
            }
            .onDisappear {
                syncTask?.cancel()
                syncTask = nil
            }
            .onAppear {
                if let tab = AppTab(rawValue: launchPageString) {
                    selection = tab
                }
            }
        #endif
    }

    @ViewBuilder
    private var macOSLayout: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            NavigationStack(path: $router.path) {
                content
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
            }
        }
    }

    @ViewBuilder
    private var iOSLayout: some View {
        NavigationStack(path: $router.path) {
            ZStack(alignment: .bottom) {
                content
                
                if router.path.isEmpty {
                    BottomNavBar(selection: $selection)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        .overlay(alignment: .top) {
            if aiCenter.isVisible {
                GlobalAIStatusCard(
                    title: aiCenter.statusTitle,
                    detail: aiCenter.statusDetail,
                    isLoading: aiCenter.isLoading,
                    isCompleted: aiCenter.isCompleted,
                    onCancel: { aiCenter.cancel() },
                    onTap: {
                        if let noteId = aiCenter.activeNoteId {
                            router.push(.note(noteId))
                        }
                        aiCenter.dismiss()
                    }
                )
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(WindowTapHapticsInstaller())
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .notebook(let notebookId):
            NotebookDetailView(notebookId: notebookId)
        case .note(let noteId):
            if let binding = store.noteBinding(noteId: noteId) {
                NoteEditorView(note: binding)
            } else {
                Text("未找到笔记")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
            }
        case .whiteboard:
            WhiteboardView(onClose: { selection = .library })
        case .recentFocus:
            RecentFocusDetailView()
        }
    }


    @ViewBuilder
    private var content: some View {
        Group {
            switch selection {
            case .library:
                #if os(macOS)
                LibraryView(tabSelection: $selection)
                #else
                LibraryPagerView(tabSelection: $selection)
                #endif
            case .list:
                AllNotesListView()
            case .whiteboard:
                WhiteboardView(onClose: { selection = .library })
            case .plan:
                PlanView()
            case .search:
                SearchView()
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Note binding now comes from `NotebookStore.noteBinding(noteId:)`.
    private func startSync() {
        syncTask?.cancel()
        syncTask = Task(priority: .background) {
            let startMark = DispatchTime.now()
            // Allow first frame render before any network sync work.
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            if Task.isCancelled { return }

            // Avoid syncing while user is navigating/reading.
            // After a rebuild, the first few navigations are sensitive to MainActor work.
            let canStart = await waitForIdleNavigation(
                maxWaitNanoseconds: 30_000_000_000,
                stableNanoseconds: 600_000_000
            ) // 30s max, require 0.6s stable idle
            if !canStart || Task.isCancelled { return }
            syncLogger.debug("SyncEngine start after \(Double(DispatchTime.now().uptimeNanoseconds - startMark.uptimeNanoseconds) / 1_000_000_000, privacy: .public)s delay")
            await syncEngine.syncNow()
            syncLogger.debug("SyncEngine finished in \(Double(DispatchTime.now().uptimeNanoseconds - startMark.uptimeNanoseconds) / 1_000_000_000, privacy: .public)s")
            
            // Defer cache refresh until UI is idle, so we don't stutter the current page.
            let canRefresh = await waitForIdleNavigation(
                maxWaitNanoseconds: 30_000_000_000,
                stableNanoseconds: 600_000_000
            ) // 30s max, require 0.6s stable idle
            if !canRefresh || Task.isCancelled { return }

            await refreshStoreFromLocalCache()
            syncLogger.debug("Local cache refresh done at \(Double(DispatchTime.now().uptimeNanoseconds - startMark.uptimeNanoseconds) / 1_000_000_000, privacy: .public)s")
        }
    }

    private func waitForIdleNavigation(maxWaitNanoseconds: UInt64, stableNanoseconds: UInt64 = 0) async -> Bool {
        let started = DispatchTime.now().uptimeNanoseconds
        var idleSince: UInt64?
        while true {
            if Task.isCancelled { return false }
            let isIdle = await MainActor.run { !router.isTransitioning && router.path.isEmpty }
            let now = DispatchTime.now().uptimeNanoseconds
            if isIdle {
                if stableNanoseconds == 0 { return true }
                if idleSince == nil { idleSince = now }
                if let idleSince, now - idleSince >= stableNanoseconds { return true }
            } else {
                idleSince = nil
            }
            if now - started > maxWaitNanoseconds { return false }
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        }
    }

    private func refreshStoreFromLocalCache() async {
        // Update data without animation to prevent layout jumps
        await MainActor.run {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.loadFromLocalCache()
                print("RootView: local notebooks count=\(store.notebooks.count)")
                // #region agent log
                DebugReporter.log(
                    hypothesisId: "H3",
                    location: "RootView.swift:startSync",
                    message: "after loadFromLocalCache",
                    data: ["notebooksCount": store.notebooks.count]
                )
                // #endregion
                
                // Prune navigation routes that reference deleted items
                let validNotebookIds = Set(store.notebooks.map { $0.id })
                let validNoteIds = Set(store.notebooks.flatMap { $0.notes.map { $0.id } })
                router.pruneInvalidRoutes(validNotebookIds: validNotebookIds, validNoteIds: validNoteIds)
            }
        }
    }

    private func handleSignOutCleanup() {
        syncTask?.cancel()
        syncTask = nil
        syncEngine.resetForSignOut()
        store.resetForSignOut()
        planStore.resetForSignOut()
        router.reset()
        selection = .library
        avatarStore.updateUserId(nil)
        AttachmentStorage.shared.clearCache()
    }
}
