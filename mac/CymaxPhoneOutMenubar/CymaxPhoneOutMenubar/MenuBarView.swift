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

/// Pre-rendered hamburger icons (dim for default, bright for hover)
private func makeHamburgerImage(alpha: CGFloat) -> NSImage {
    let size: CGFloat = 18
    let barW: CGFloat = 14
    let barH: CGFloat = 2.25
    let cr: CGFloat = 1.1
    let xOff = (size - barW) / 2

    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    NSColor.white.withAlphaComponent(alpha).setFill()
    for yTop in [3.375, 7.875, 12.375] as [CGFloat] {
        let yBottom = size - yTop - barH
        let rect = NSRect(x: xOff, y: yBottom, width: barW, height: barH)
        NSBezierPath(roundedRect: rect, xRadius: cr, yRadius: cr).fill()
    }
    img.unlockFocus()
    return img
}
private let hamburgerDim = makeHamburgerImage(alpha: 0.4)
private let hamburgerBright = makeHamburgerImage(alpha: 0.85)

/// Hamburger menu shown in top-right corner of all screens
struct HamburgerMenuButton: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovering = false

    var body: some View {
        Menu {
            Button(action: {
                if appState.isServerRunning {
                    appState.stopServer()
                }
                appState.signOut()
            }) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Button(action: {
                if let url = URL(string: "mailto:\(SubscriptionConfig.supportEmail)") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("Help", systemImage: "questionmark.circle")
            }

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
            }
        } label: {
            Image(nsImage: isHovering ? hamburgerBright : hamburgerDim)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .padding(.top, 2)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveringTrafficLights = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        // Subscription gate — must be active before showing the app
        switch appState.subscriptionStatus {
        case .notChecked, .checking, .loginFailed:
            LoginView()
                .environmentObject(appState)
        case .inactive:
            SubscriptionInactiveView()
                .environmentObject(appState)
        case .active:
            // Show onboarding on first launch when permissions are needed
            if !hasCompletedOnboarding && appState.needsPermission {
                OnboardingView(isComplete: $hasCompletedOnboarding)
                    .environmentObject(appState)
            } else {
                mainView
            }
        }
    }

    private var mainView: some View {
        ZStack {
            // Main content (blurred when permission needed)
            VStack(spacing: 0) {
                // Traffic light buttons + status indicator
                HStack {
                    trafficLightButtons
                    Spacer()
                    HamburgerMenuButton()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                // Centered branding logo
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, -2)
                    .padding(.bottom, 8)
                
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
    } // end mainView

    // MARK: - Permission Overlay
    
    private var permissionOverlay: some View {
        VStack(spacing: 0) {
            // Traffic lights at top
            HStack {
                trafficLightButtons
                Spacer()
                HamburgerMenuButton()
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
                    
                    Text("Cymatics Mix Link needs Screen Recording access to capture your Mac's audio")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }
                
                // Steps
                VStack(alignment: .leading, spacing: 10) {
                    permissionStep(number: 1, text: "Click \"Open Settings\" below")
                    permissionStep(number: 2, text: "Find \"Screen & System Audio\" section and click +")
                    permissionStep(number: 3, text: "Select \"Cymatics Mix Link\" from the list")
                    permissionStep(number: 4, text: "Enter password if prompted")
                    permissionStep(number: 5, text: "Ensure your phone and computer are on the same WiFi or Hotspot network")
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
        HStack(alignment: .center, spacing: 10) {
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
        VStack(spacing: 4) {
            Image("CymaticsWordmark")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 11)
                .foregroundColor(.white)
            Text("MIX LINK")
                .font(.custom("Montserrat-SemiBold", size: 24))
                .tracking(4)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
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

                        HStack(spacing: 6) {
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

                            Button(action: {
                                appState.refreshNetwork()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.mixLinkCyan)
                                    .frame(width: 26, height: 26)
                                    .background(Color.mixLinkCyan.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh IP address")
                        }
                    }
                }
            } else {
                // Not running state
                VStack(spacing: 20) {
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
                .padding(.top, 30)
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
                    
                    // Signal strength
                    VStack(spacing: 2) {
                        HStack(alignment: .bottom, spacing: 2) {
                            let active = appState.isCaptureActive && appState.webClientsConnected > 0
                            let barColor: Color = active ? .mixLinkCyan : .gray.opacity(0.3)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(appState.webClientsConnected > 0 ? barColor : .gray.opacity(0.3))
                                .frame(width: 5, height: 6)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(appState.isCaptureActive ? barColor : .gray.opacity(0.3))
                                .frame(width: 5, height: 12)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(active ? barColor : .gray.opacity(0.3))
                                .frame(width: 5, height: 18)
                        }
                        Text("Signal")
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
    
    // MARK: - Controls
    
    private var controlsView: some View {
        VStack(spacing: 0) {
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
