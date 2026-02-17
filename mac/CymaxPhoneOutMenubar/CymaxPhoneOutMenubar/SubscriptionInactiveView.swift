//
//  SubscriptionInactiveView.swift
//  CymaxPhoneOutMenubar
//
//  Shown when the user is logged in but has no active subscription for this product.
//

import SwiftUI
import AppKit

struct SubscriptionInactiveView: View {
    @EnvironmentObject var appState: AppState
    @State private var hoveringTrafficLights = false

    var body: some View {
        VStack(spacing: 0) {
            // Traffic light buttons
            HStack {
                trafficLightButtons
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer().frame(height: 24)

            // Cymatics branding
            VStack(spacing: 6) {
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

            Spacer().frame(height: 28)

            // Content
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)

                // Title
                Text("Your subscription isn't active")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // View Plans button
                Button(action: {
                    if let url = URL(string: SubscriptionConfig.viewPlansURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("View Plans")
                        .font(.system(size: 14, weight: .semibold))
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
                        .shadow(color: Color.mixLinkCyan.opacity(0.3), radius: 8)
                }
                .buttonStyle(.plain)

                // Support text
                Text("If you have any other questions contact \(SubscriptionConfig.supportEmail)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Sign out / try again
                Button(action: {
                    appState.signOut()
                }) {
                    Text("Sign Out")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.mixLinkCyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.mixLinkCyan.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)
        }
        .frame(width: 300)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
    }

    // MARK: - Traffic Lights

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
}
