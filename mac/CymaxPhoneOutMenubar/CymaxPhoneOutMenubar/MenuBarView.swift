//
//  MenuBarView.swift
//  CymaxPhoneOutMenubar
//
//  Main menubar popover view - Modern dark theme matching browser UI
//

import SwiftUI

// Custom cyan color to match browser
extension Color {
    static let mixLinkCyan = Color(red: 0, green: 212/255, blue: 1)
    static let mixLinkTeal = Color(red: 0, green: 1, blue: 212/255)
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingLog = false
    @State private var hoveringTrafficLights = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Traffic light buttons (top left)
            HStack {
                trafficLightButtons
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            // Header
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            // Main content
            VStack(spacing: 16) {
                // QR Code & Connection
                connectionView
                
                // Status indicators
                statusView
                
                // Controls
                controlsView
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            if showingLog {
                Divider()
                    .background(Color.white.opacity(0.1))
                logView
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            
            // Footer
            Divider()
                .background(Color.white.opacity(0.1))
            footerView
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
    }
    
    // MARK: - Traffic Light Buttons
    
    private var trafficLightButtons: some View {
        HStack(spacing: 8) {
            // Close button (red)
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 1, green: 0.38, blue: 0.34))
                        .frame(width: 12, height: 12)
                    
                    if hoveringTrafficLights {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Color(red: 0.4, green: 0, blue: 0))
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Minimize button (yellow) - closes popover back to menubar
            Button(action: {
                NSApp.keyWindow?.close()
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 1, green: 0.74, blue: 0.17))
                        .frame(width: 12, height: 12)
                    
                    if hoveringTrafficLights {
                        Image(systemName: "minus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0))
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering in
            hoveringTrafficLights = hovering
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Mix Link branding
            HStack(spacing: 6) {
                Text("Mix")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                Text("Link")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.mixLinkCyan)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isServerRunning ? Color.mixLinkCyan : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .shadow(color: appState.isServerRunning ? Color.mixLinkCyan.opacity(0.6) : .clear, radius: 4)
                
                Text(appState.isServerRunning ? "Live" : "Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(appState.isServerRunning ? .mixLinkCyan : .gray)
            }
        }
    }
    
    // MARK: - Connection View
    
    private var connectionView: some View {
        VStack(spacing: 12) {
            if appState.isServerRunning {
                // QR Code with styled container
                if let qrImage = appState.qrCodeImage {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .frame(width: 150, height: 150)
                        
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                    }
                    .shadow(color: Color.mixLinkCyan.opacity(0.2), radius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 150, height: 150)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "wifi.slash")
                                    .font(.system(size: 24))
                                Text("No network")
                                    .font(.caption)
                            }
                            .foregroundColor(.gray)
                        )
                }
                
                // URL display
                if let url = appState.webPlayerURL {
                    VStack(spacing: 8) {
                        Text("Scan with your phone")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }) {
                            HStack(spacing: 6) {
                                Text(url)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.mixLinkCyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.mixLinkCyan.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Not running state
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.mixLinkCyan.opacity(0.3), lineWidth: 2)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "qrcode")
                            .font(.system(size: 32))
                            .foregroundColor(.mixLinkCyan.opacity(0.5))
                    }
                    
                    Text("Press Start to begin streaming")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .frame(height: 150)
            }
        }
    }
    
    // MARK: - Status
    
    private var statusView: some View {
        VStack(spacing: 8) {
            // Permission warning
            if appState.needsPermission {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Screen Recording Required")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    
                    Text("Enable in System Settings → Privacy → Screen Recording")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 8) {
                        Button(action: { appState.openScreenRecordingSettings() }) {
                            Text("Open Settings")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            appState.needsPermission = false
                            appState.stopServer()
                            appState.startServer()
                        }) {
                            Text("Retry")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            }
            
            // Connection stats
            if appState.isServerRunning {
                HStack(spacing: 16) {
                    // Connected phones
                    VStack(spacing: 2) {
                        Text("\(appState.webClientsConnected)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(appState.webClientsConnected > 0 ? .mixLinkCyan : .gray)
                        Text("Phones")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                        .frame(height: 30)
                        .background(Color.white.opacity(0.1))
                    
                    // Audio status
                    VStack(spacing: 2) {
                        Image(systemName: appState.isCaptureActive ? "waveform" : "waveform.slash")
                            .font(.system(size: 16))
                            .foregroundColor(appState.isCaptureActive ? .mixLinkCyan : .gray)
                        Text(appState.isCaptureActive ? "Streaming" : "Idle")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                        .frame(height: 30)
                        .background(Color.white.opacity(0.1))
                    
                    // Packets
                    VStack(spacing: 2) {
                        Text(formatPackets(appState.packetsSent))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(appState.packetsSent > 0 ? .white : .gray)
                        Text("Packets")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(10)
            }
        }
    }
    
    private func formatPackets(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
    
    // MARK: - Controls
    
    private var controlsView: some View {
        Button(action: {
            if appState.isServerRunning {
                appState.stopServer()
            } else {
                appState.startServer()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: appState.isServerRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 14))
                Text(appState.isServerRunning ? "Stop" : "Start")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(appState.isServerRunning ? .white : .black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Group {
                    if appState.isServerRunning {
                        Color.red.opacity(0.8)
                    } else {
                        LinearGradient(
                            colors: [.mixLinkCyan, .mixLinkTeal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .cornerRadius(10)
            .shadow(color: appState.isServerRunning ? .clear : Color.mixLinkCyan.opacity(0.3), radius: 8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Log View
    
    private var logView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Debug Log")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                Button("Copy") {
                    let logText = appState.logMessages.map { "[\($0.formattedTimestamp)] \($0.level.rawValue): \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                .font(.system(size: 9))
                .foregroundColor(.mixLinkCyan)
                .buttonStyle(.plain)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.logMessages.suffix(30)) { log in
                        HStack(alignment: .top, spacing: 6) {
                            Text(log.formattedTimestamp)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.6))
                            Text(log.message)
                                .font(.system(size: 9))
                                .foregroundColor(logColor(for: log.level))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: 100)
            .background(Color.black.opacity(0.3))
            .cornerRadius(6)
        }
    }
    
    private func logColor(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .mixLinkCyan
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Button(action: { showingLog.toggle() }) {
                Image(systemName: showingLog ? "chevron.down" : "terminal")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help("Toggle debug log")
            
            Spacer()
            
            Text("v1.0")
                .font(.system(size: 9))
                .foregroundColor(.gray.opacity(0.5))
            
            Spacer()
            
            // Empty spacer to balance the layout (power button removed, using traffic lights now)
            Color.clear
                .frame(width: 12, height: 12)
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
