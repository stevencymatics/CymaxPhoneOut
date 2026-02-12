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
        ZStack {
            // Main content (blurred when permission needed)
            VStack(spacing: 0) {
                // Traffic light buttons (top left)
                HStack {
                    trafficLightButtons
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                
                // Header (without Live indicator when permission needed)
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                // Main content
                VStack(spacing: 16) {
                    // QR Code & Connection
                    connectionView
                    
                    // Status indicators (without permission box - shown in overlay)
                    if !appState.needsPermission {
                        statusView
                    }
                    
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
            .blur(radius: appState.needsPermission ? 8 : 0)
            .opacity(appState.needsPermission ? 0.3 : 1)
            
            // Permission overlay
            if appState.needsPermission {
                permissionOverlay
            }
        }
        .frame(width: 300)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
    }
    
    // MARK: - Permission Overlay
    
    private var permissionOverlay: some View {
        VStack(spacing: 0) {
            // Traffic lights at top
            HStack {
                trafficLightButtons
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            // Permission content
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    
                    Text("Permission Required")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Mix Link needs Screen Recording access to capture your Mac's audio")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                
                // Steps
                VStack(alignment: .leading, spacing: 10) {
                    permissionStep(number: 1, text: "Click \"Open Settings\" below")
                    permissionStep(number: 2, text: "Find \"Screen & System Audio\" section and click +")
                    permissionStep(number: 3, text: "Select \"Mix Link\" from the list")
                    permissionStep(number: 4, text: "Enter password if prompted")
                }
                .padding(14)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                
                // Buttons
                VStack(spacing: 10) {
                    Button(action: { appState.openScreenRecordingSettings() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                                .font(.system(size: 14))
                            Text("Open Settings")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        // macOS requires app restart to pick up new TCC permissions
                        restartApp()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("I've enabled it - Restart App")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color(red: 0.10, green: 0.10, blue: 0.10))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 20)
            
            Spacer()
        }
    }
    
    private func permissionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Number circle
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 20, height: 20)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
            }
            
            // Step text - allow wrapping
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            
            // Status indicator (hidden when permission needed)
            if !appState.needsPermission {
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
                    
                    // Connection quality
                    VStack(spacing: 2) {
                        signalBars
                        Text("Quality")
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
    
    /// 3-bar signal quality indicator
    private var signalBars: some View {
        let level = connectionQualityLevel
        let colors: [Color] = [
            Color(red: 0.29, green: 0.87, blue: 0.50), // green #4ade80
            Color(red: 0.98, green: 0.75, blue: 0.14), // yellow #fbbf24
            Color(red: 0.94, green: 0.27, blue: 0.27)  // red #ef4444
        ]
        let color = level >= 3 ? colors[0] : level == 2 ? colors[1] : colors[2]

        return HStack(alignment: .bottom, spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(level >= 1 ? color : Color.gray.opacity(0.3))
                .frame(width: 5, height: 6)
            RoundedRectangle(cornerRadius: 1)
                .fill(level >= 2 ? color : Color.gray.opacity(0.3))
                .frame(width: 5, height: 12)
            RoundedRectangle(cornerRadius: 1)
                .fill(level >= 3 ? color : Color.gray.opacity(0.3))
                .frame(width: 5, height: 18)
        }
    }

    /// 3 = good, 2 = fair, 1 = poor
    private var connectionQualityLevel: Int {
        guard appState.isServerRunning else { return 0 }
        if appState.isCaptureActive && appState.webClientsConnected > 0 && appState.packetsSent > 0 {
            return 3 // streaming to clients
        } else if appState.isCaptureActive {
            return 2 // capturing but no clients yet
        }
        return 1 // server running but issues
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
    
    // MARK: - App Restart
    
    /// Restart the app to pick up new TCC permissions
    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        
        // Run a background command that waits for us to quit, then relaunches
        let script = "sleep 0.3 && open \"\(bundlePath)\""
        
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
        } catch {
            // Fallback: just quit
        }
        
        // Quit immediately - the background script will relaunch us
        NSApp.terminate(nil)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
