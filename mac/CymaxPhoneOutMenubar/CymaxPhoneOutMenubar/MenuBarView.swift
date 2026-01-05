//
//  MenuBarView.swift
//  CymaxPhoneOutMenubar
//
//  Main menubar popover view - Simplified web-only version
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingLog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView
            
            Divider()
            
            // QR Code & Connection
            connectionView
            
            Divider()
            
            // Status
            statusView
            
            Divider()
            
            // Controls
            controlsView
            
            if showingLog {
                Divider()
                logView
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .padding()
        .frame(width: 320)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(appState.isServerRunning ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Cymax Audio")
                    .font(.headline)
                Text("Stream to your phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(appState.isServerRunning ? .green : .secondary)
                .frame(width: 10, height: 10)
        }
    }
    
    // MARK: - Connection View
    
    private var connectionView: some View {
        VStack(spacing: 16) {
            if appState.isServerRunning {
                // QR Code
                if let qrImage = appState.qrCodeImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .background(Color.white)
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 160, height: 160)
                        .cornerRadius(8)
                        .overlay(
                            Text("No network")
                                .foregroundStyle(.secondary)
                        )
                }
                
                // URL
                if let url = appState.webPlayerURL {
                    VStack(spacing: 4) {
                        Text("Scan QR or visit:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(url)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        
                        Button("Copy URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            } else {
                // Instructions when not running
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("Click Start to begin")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    Text("No setup needed - just scan the QR code with your phone!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 160)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Status
    
    private var statusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Server:")
                    .foregroundStyle(.secondary)
                Text(appState.isServerRunning ? "Running" : "Stopped")
                    .foregroundStyle(appState.isServerRunning ? .green : .secondary)
            }
            .font(.caption)
            
            HStack {
                Text("Audio Capture:")
                    .foregroundStyle(.secondary)
                Text(appState.captureStatus)
                    .foregroundStyle(appState.isCaptureActive ? .green : (appState.needsPermission ? .orange : .secondary))
            }
            .font(.caption)
            
            // Permission warning banner
            if appState.needsPermission {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Screen Recording Permission Required")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Text("1. Click 'Open System Settings' below\n2. Find this app and toggle it ON\n3. Come back and click 'Retry'")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        Button(action: { appState.openScreenRecordingSettings() }) {
                            Label("Open System Settings", systemImage: "gear")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        Button(action: { 
                            appState.needsPermission = false
                            appState.stopServer()
                            appState.startServer() 
                        }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack {
                Text("Connected Phones:")
                    .foregroundStyle(.secondary)
                Text("\(appState.webClientsConnected)")
                    .foregroundStyle(appState.webClientsConnected > 0 ? .green : .secondary)
            }
            .font(.caption)
            
            if appState.isServerRunning && appState.packetsSent > 0 {
                HStack {
                    Text("Packets Sent:")
                        .foregroundStyle(.secondary)
                    Text("\(appState.packetsSent)")
                }
                .font(.caption)
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsView: some View {
        HStack(spacing: 12) {
            if appState.isServerRunning {
                Button(action: { appState.stopServer() }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: { appState.startServer() }) {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }
    
    // MARK: - Log View
    
    private var logView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Log")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    let logText = appState.logMessages.map { "[\($0.formattedTimestamp)] \($0.level.rawValue): \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.logMessages.suffix(30)) { log in
                        HStack(alignment: .top, spacing: 4) {
                            Text(log.formattedTimestamp)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(log.message)
                                .font(.system(size: 10))
                                .foregroundStyle(log.level.color)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(height: 120)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(4)
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button(action: { showingLog.toggle() }) {
                Image(systemName: showingLog ? "chevron.up" : "terminal")
            }
            .buttonStyle(.borderless)
            .help("Toggle log")
            
            Spacer()
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .font(.callout)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
