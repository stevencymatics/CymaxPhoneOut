//
//  MenuBarView.swift
//  CymaxPhoneOutMenubar
//
//  Main menubar popover view
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
            
            // Device selection
            deviceSelectionView
            
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
        .onAppear {
            appState.startBrowsing()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(appState.isStreaming ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Cymax Phone Out")
                    .font(.headline)
                Text("MVP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(appState.connectionStatus.color)
                .frame(width: 10, height: 10)
        }
    }
    
    // MARK: - Device Selection
    
    @State private var manualIP: String = ""
    
    private var deviceSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iPhone Receivers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Manual IP entry
            HStack {
                TextField("iPhone IP (e.g. 192.168.1.x)", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Add") {
                    if !manualIP.isEmpty {
                        let device = DiscoveredDevice(
                            id: "manual-\(manualIP)",
                            name: "iPhone (\(manualIP))",
                            hostName: manualIP,
                            port: 19621,
                            ipAddress: manualIP
                        )
                        appState.discoveredDevices.append(device)
                        appState.log("Added manual device: \(manualIP)")
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            
            ForEach(appState.discoveredDevices) { device in
                deviceRow(device)
            }
        }
    }
    
    private func deviceRow(_ device: DiscoveredDevice) -> some View {
        Button(action: { appState.selectDevice(device) }) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundStyle(device == appState.selectedDevice ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.callout)
                    if let ip = device.ipAddress {
                        Text(ip)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if device == appState.selectedDevice {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(device == appState.selectedDevice ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Status
    
    private var statusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Status:")
                    .foregroundStyle(.secondary)
                Text(appState.connectionStatus.description)
                    .foregroundStyle(appState.connectionStatus.color)
            }
            .font(.caption)
            
            HStack {
                Text("Sample Rate:")
                    .foregroundStyle(.secondary)
                Text("\(appState.sampleRate) Hz")
            }
            .font(.caption)
            
            HStack {
                Text("Buffer Size:")
                    .foregroundStyle(.secondary)
                Text("\(appState.bufferSize) frames")
            }
            .font(.caption)
            
            HStack {
                Text("Est. Latency:")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f ms", appState.estimatedLatencyMs))
            }
            .font(.caption)
            
            if appState.isStreaming {
                HStack {
                    Text("Packet Loss:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f%%", appState.stats.lossPercentage))
                        .foregroundStyle(appState.stats.lossPercentage > 1 ? .red : .green)
                }
                .font(.caption)
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsView: some View {
        HStack(spacing: 12) {
            if appState.connectionStatus == .connected {
                Button(action: { appState.disconnect() }) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                
                if appState.isStreaming {
                    Button(action: { appState.stopStreaming() }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: { appState.startStreaming() }) {
                        Label("Stream", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            } else if appState.connectionStatus == .connecting {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Connecting...")
                    .font(.caption)
            } else {
                Button(action: { appState.connect() }) {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.selectedDevice == nil)
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
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            
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

