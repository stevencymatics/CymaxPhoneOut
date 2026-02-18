//
//  OnboardingView.swift
//  CymaxPhoneOutMenubar
//
//  First-launch onboarding flow — shown once before permissions dialog
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isComplete: Bool
    @State private var currentPage = 0

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            // Traffic light buttons + hamburger menu
            HStack {
                trafficLightButtons
                Spacer()
                HamburgerMenuButton()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Page content — each page sizes naturally
            Group {
                switch currentPage {
                case 0: welcomePage
                case 1: requirementsPage
                case 2: permissionsPage
                default: EmptyView()
                }
            }

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? Color.white.opacity(0.9) : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                        .contentShape(Circle().scale(3))
                        .onTapGesture { currentPage = i }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Buttons
            VStack(spacing: 8) {
                if currentPage < 2 {
                    continueButton
                } else {
                    openSettingsButton
                    restartButton
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(width: 300)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
    }

    // MARK: - Buttons

    private var continueButton: some View {
        Button(action: { currentPage += 1 }) {
            Text("Continue")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.mixLinkCyan, .mixLinkTeal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var openSettingsButton: some View {
        Button(action: { appState.openScreenRecordingSettings() }) {
            HStack(spacing: 8) {
                Image(systemName: "gear")
                    .font(.system(size: 13))
                Text("Open Settings")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [.mixLinkCyan, .mixLinkTeal],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var restartButton: some View {
        Button(action: {
            isComplete = true
            restartApp()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                Text("I've enabled it — Restart")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.mixLinkCyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.mixLinkCyan.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 10) {
            Image("CymaticsWordmark")
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 12)
                .foregroundColor(.white)

            Text("MIX LINK")
                .font(.custom("Montserrat-SemiBold", size: 27))
                .tracking(4)
                .foregroundColor(.white)

            Text("Stream your desktop audio\nto your phone over your\nown local network.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 48)
    }

    // MARK: - Page 2: Requirements

    private var requirementsPage: some View {
        VStack(spacing: 12) {
            requirementRow(
                icon: "speaker.wave.3.fill",
                title: "Desktop Audio Access",
                detail: "Mix Link needs permission to capture your system audio."
            )

            requirementRow(
                icon: "wifi",
                title: "Same Network",
                detail: "Your computer and phone need to be on the same WiFi or Hotspot."
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private func requirementRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.mixLinkCyan)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text(detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    // MARK: - Page 3: Permissions

    private var permissionsPage: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.mixLinkCyan, .mixLinkTeal],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Enable Audio Capture")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 6) {
                permissionStep(number: 1, text: "Click \"Open Settings\" below")
                permissionStep(number: 2, text: "Find the \"Cymatics Mix Link\" permission and switch it on")
                permissionStep(number: 3, text: "Enter your password if prompted")
                permissionStep(number: 4, text: "Ensure your computer and phone are on the same WiFi network or Hotspot")
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
        .padding(.horizontal, 24)
    }

    private func permissionStep(number: Int, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.mixLinkCyan.opacity(0.15))
                    .frame(width: 20, height: 20)
                Text("\(number)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.mixLinkCyan)
            }

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Traffic Lights

    @State private var hoveringTrafficLights = false

    private var trafficLightButtons: some View {
        HStack(spacing: 8) {
            Button(action: { NSApplication.shared.terminate(nil) }) {
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

            Button(action: { NSApp.keyWindow?.close() }) {
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

    // MARK: - Restart

    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let script = "sleep 0.3 && open \"\(bundlePath)\""
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }
}
