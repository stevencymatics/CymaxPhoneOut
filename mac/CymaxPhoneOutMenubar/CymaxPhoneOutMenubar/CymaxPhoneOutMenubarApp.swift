//
//  CymaxPhoneOutMenubarApp.swift
//  CymaxPhoneOutMenubar
//
//  macOS menubar application for streaming system audio to your phone
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
            Image(systemName: appState.isServerRunning ? "waveform" : "waveform.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
