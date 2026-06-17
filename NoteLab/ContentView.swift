//
//  ContentView.swift
//  NoteLab
//
//  Created by Strictly · · on 2026/1/25.
//

import SwiftUI
import Combine
import SwiftData
import os

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @State private var modelContainer: ModelContainer?
    @State private var persistenceError: String?
    @State private var isInitializing = false
    @State private var initializationMessage = "正在初始化本地缓存…"
    private static let logger = Logger(subsystem: "NoteLab", category: "Init")

    var body: some View {
        Group {
            if auth.isAuthenticated {
                if let modelContainer {
                    RootView()
                        .modelContainer(modelContainer)
                        .environmentObject(auth)
                        .preferredColorScheme(appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark))
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(initializationMessage)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                    .task {
                        await initializeWithTimeout()
                    }
                }
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
        .onChange(of: auth.userId) { oldValue, newValue in
            // Only clear when userId actually changed (not on initial render).
            // Prevents async credential-state check in AuthManager from spuriously
            // resetting modelContainer while init is still in progress.
            guard oldValue != newValue else { return }
            Self.logger.info("userId changed, clearing modelContainer. old=\(oldValue?.uuidString ?? "nil", privacy: .public) new=\(newValue?.uuidString ?? "nil", privacy: .public)")
            modelContainer = nil
        }
        .alert("初始化失败", isPresented: Binding(get: { persistenceError != nil }, set: { if !$0 { persistenceError = nil } })) {
            Button("重试", role: .cancel) {
                persistenceError = nil
                modelContainer = nil
                isInitializing = false
                initializationMessage = "正在初始化本地缓存…"
            }
        } message: {
            Text("本地数据库初始化失败：\(persistenceError ?? "")")
        }
    }

    // MARK: - Timeout-protected initialization

    /// Outcome of the init waterfall.  Returned from the TaskGroup so @State
    /// mutations only happen on the MainActor after the group completes.
    private enum InitOutcome {
        case success(ModelContainer)
        case failure(String)
        case timedOut
    }

    /// Wrap the synchronous init work in a TaskGroup so a 15-second timeout
    /// can trigger the in-memory fallback even if ModelContainer(for:) hangs
    /// on a locked store file.
    ///
    /// Important: do NOT mutate @State inside TaskGroup.addTask closures.
    /// Instead, return an InitOutcome and apply mutations after the group.
    private func initializeWithTimeout() async {
        guard !isInitializing else {
            Self.logger.debug("[INIT] already initializing, skip")
            return
        }

        Self.logger.info("[INIT] starting. storeURL=\(PersistenceController.storeURL.path, privacy: .public)")
        let overallStart = Date()
        isInitializing = true
        initializationMessage = "正在初始化本地数据…"

        let outcome = await withTaskGroup(of: InitOutcome.self) { group in
            // Lane 1: actual init work (may block on store open)
            group.addTask {
                // Tier 1 — normal persistent store
                let t1 = Date()
                do {
                    let c = try PersistenceController.makeContainer()
                    Self.logger.info("[INIT] Tier1 ok, \(Date().timeIntervalSince(t1), privacy: .public)s")
                    return .success(c)
                } catch {
                    Self.logger.error("[INIT] Tier1 fail (\(error.localizedDescription, privacy: .public)), \(Date().timeIntervalSince(t1), privacy: .public)s")
                }

                // Tier 2 — reset store & retry
                let t2 = Date()
                do {
                    try PersistenceController.resetStore()
                    let c = try PersistenceController.makeContainer()
                    Self.logger.info("[INIT] Tier2 ok, \(Date().timeIntervalSince(t2), privacy: .public)s")
                    return .success(c)
                } catch {
                    Self.logger.error("[INIT] Tier2 fail (\(error.localizedDescription, privacy: .public)), \(Date().timeIntervalSince(t2), privacy: .public)s")
                }

                // Tier 3 — in-memory
                let t3 = Date()
                do {
                    let c = try PersistenceController.makeInMemoryContainer()
                    Self.logger.info("[INIT] Tier3 ok, \(Date().timeIntervalSince(t3), privacy: .public)s")
                    return .success(c)
                } catch {
                    Self.logger.error("[INIT] Tier3 fail (\(error.localizedDescription, privacy: .public))")
                    return .failure(error.localizedDescription)
                }
            }

            // Lane 2: 15-second timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                return .timedOut
            }

            return await group.first(where: { _ in true }) ?? .failure("unknown")
        }

        // Apply outcome on MainActor — safe to mutate @State here
        switch outcome {
        case .success(let container):
            modelContainer = container
            persistenceError = nil
        case .timedOut:
            Self.logger.error("[INIT] timed out after 15s, in-memory fallback")
            initializationMessage = "正在启动临时本地模式…"
            modelContainer = try? PersistenceController.makeInMemoryContainer()
            persistenceError = modelContainer == nil ? "启动超时且无法创建内存存储" : nil
        case .failure(let msg):
            Self.logger.error("[INIT] all tiers failed: \(msg)")
            initializationMessage = "正在启动临时本地模式…"
            // One last attempt at in-memory (in case Tier3 was skipped by a throw)
            modelContainer = (try? PersistenceController.makeInMemoryContainer())
            persistenceError = modelContainer == nil ? msg : nil
        }

        isInitializing = false
        let elapsed = Date().timeIntervalSince(overallStart)
        Self.logger.info("[INIT] done, \(elapsed, privacy: .public)s success=\(self.modelContainer != nil)")
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
