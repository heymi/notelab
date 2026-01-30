//
//  ContentView.swift
//  NoteLab
//
//  Created by Strictly · · on 2026/1/25.
//

import SwiftUI
import Combine
import SwiftData

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("schemaVersion") private var schemaVersion: Int = 0
    @State private var modelContainer: ModelContainer?
    @State private var persistenceError: String?
    @State private var lastUserId: UUID?
    @State private var showResetConfirmation = false
    
    // Current schema version - increment when making breaking changes to models
    private let currentSchemaVersion = 4

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
                        Text("正在初始化本地缓存…")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                    .task {
                        await initializeContainer()
                    }
                }
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
        .onChange(of: auth.userId) { _, newValue in
            // Only rebuild container when switching to a different logged-in user.
            if let newUserId = newValue, newUserId != lastUserId {
                modelContainer = nil
            }
            lastUserId = newValue
        }
        .alert("初始化失败", isPresented: Binding(get: { persistenceError != nil }, set: { if !$0 { persistenceError = nil } })) {
            Button("重置本地数据", role: .destructive) {
                resetAndRetry()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地数据库初始化失败：\(persistenceError ?? "")\n\n您可以尝试重置本地数据，数据会在登录后从云端重新同步。")
        }
    }
    
    private func initializeContainer() async {
        // Check if schema version changed - if so, reset the store
        if schemaVersion != currentSchemaVersion {
            print("Schema version changed from \(schemaVersion) to \(currentSchemaVersion), resetting store...")
            await resetStoreInBackground()
            schemaVersion = currentSchemaVersion
            PersistenceController.didResetForCorruption = false
        }
        
        do {
            let container = try await buildContainerInBackground()
            // Small delay to ensure SwiftData is fully initialized
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            await MainActor.run {
                self.modelContainer = container
                PersistenceController.didResetForCorruption = false
            }
        } catch {
            if !PersistenceController.didResetForCorruption {
                print("Store validation failed, attempting one-time reset: \(error.localizedDescription)")
                await MainActor.run {
                    PersistenceController.didResetForCorruption = true
                }
                do {
                    await resetStoreInBackground()
                    let container = try await buildContainerInBackground()
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    await MainActor.run {
                        self.modelContainer = container
                    }
                } catch {
                    await MainActor.run {
                        self.persistenceError = error.localizedDescription
                    }
                }
            } else {
                await MainActor.run {
                    self.persistenceError = error.localizedDescription
                }
            }
        }
    }

    private func buildContainerInBackground() async throws -> ModelContainer {
        try await Task.detached(priority: .userInitiated) {
            let container = try PersistenceController.makeContainer()
            try PersistenceController.validateStore(container: container)
            return container
        }.value
    }

    private func resetStoreInBackground() async {
        _ = await Task.detached(priority: .utility) {
            do {
                try PersistenceController.resetStore()
            } catch {
                print("Failed to reset store: \(error.localizedDescription)")
            }
        }.value
    }
    
    private func resetAndRetry() {
        do {
            try PersistenceController.resetStore()
            schemaVersion = currentSchemaVersion
            PersistenceController.didResetForCorruption = false
            modelContainer = try PersistenceController.makeContainer()
            persistenceError = nil
        } catch {
            persistenceError = "重置失败：\(error.localizedDescription)"
        }
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
