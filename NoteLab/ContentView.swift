//
//  ContentView.swift
//  NoteLab
//
//  Created by Strictly · · on 2026/1/25.
//

import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0

    var body: some View {
        Group {
            if auth.isAuthenticated {
                if let error = StorageController.shared.openError {
                    StorageRecoveryView(message: error.localizedDescription)
                } else {
                    RootView()
                        .environmentObject(auth)
                        .preferredColorScheme(appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark))
                }
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
    }
}

private struct StorageRecoveryView: View {
    let message: String

    var body: some View {
        Text("本地数据库不可用\n\(message)\n为避免数据丢失，NoteLab 不会自动删除数据库或切换到临时内存模式。请强制退出 App 后重试。")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.secondaryInk)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
