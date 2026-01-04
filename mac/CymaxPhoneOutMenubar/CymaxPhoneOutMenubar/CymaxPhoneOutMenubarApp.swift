//
//  CymaxPhoneOutMenubarApp.swift
//  CymaxPhoneOutMenubar
//
//  macOS menubar application for controlling the Cymax Phone Out audio driver
//

import SwiftUI

@main
struct CymaxPhoneOutMenubarApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isStreaming ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

