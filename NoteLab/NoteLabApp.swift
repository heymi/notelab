//
//  NoteLabApp.swift
//  NoteLab
//
//  Created by Strictly · · on 2026/1/25.
//

import SwiftUI
import Combine
import CloudKit
#if os(iOS)
import UIKit
#endif

@main
struct NoteLabApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var syncEngine = SyncEngine()
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    #if os(iOS)
    @UIApplicationDelegateAdaptor(NoteLabAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
                .environmentObject(auth)
                .environmentObject(syncEngine)
                .onAppear {
                    #if DEBUG
                    SubscriptionManager.shared.debugSetTier(.pro)
                    #if os(macOS)
                    AgentAccessServer.shared.start()
                    #endif
                    #elseif os(macOS)
                    if UserDefaults.standard.bool(forKey: "AgentAccessEnabled") {
                        AgentAccessServer.shared.start()
                    }
                    #endif
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(auth)
                .environmentObject(syncEngine)
        }
        #endif
    }
    
    private var colorScheme: ColorScheme? {
        appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark)
    }
}

#if os(iOS)
final class NoteLabAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if CKNotification(fromRemoteNotificationDictionary: userInfo) is CKRecordZoneNotification {
            NotificationCenter.default.post(name: .cloudKitRemoteNotification, object: nil)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
}
#endif
