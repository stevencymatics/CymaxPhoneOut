//
//  SettingsView.swift
//  CymaxPhoneOutMenubar
//
//  Settings view (simplified for web-only mode)
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Cymax Audio")
                .font(.title)
            
            Text("Stream your Mac's audio to any phone browser")
                .foregroundStyle(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("How to use:")
                    .font(.headline)
                
                Text("1. Click the waveform icon in your menubar")
                Text("2. Click 'Start' to begin")
                Text("3. Scan the QR code with your phone")
                Text("4. Tap 'Play' on the web page")
                Text("5. Audio from your Mac streams to your phone!")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            Text("No setup required. Works with any phone browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(30)
        .frame(width: 400, height: 350)
    }
}
