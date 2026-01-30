//
//  NoteLabApp.swift
//  NoteLab
//
//  Created by Strictly · · on 2026/1/25.
//

import SwiftUI
import Combine

@main
struct NoteLabApp: App {
    @StateObject private var auth = AuthManager()
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
                .environmentObject(auth)
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(auth)
        }
        #endif
    }
    
    private var colorScheme: ColorScheme? {
        appearanceMode == 0 ? nil : (appearanceMode == 1 ? .light : .dark)
    }
}
