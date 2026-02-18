//
//  LoginView.swift
//  CymaxPhoneOutMenubar
//
//  Subscription login screen — Cymatics branding, email + password fields.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var email: String = KeychainHelper.loadCredentials()?.email ?? ""
    @State private var password: String = KeychainHelper.loadCredentials()?.password ?? ""
    @State private var hoveringTrafficLights = false

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

            Spacer().frame(height: 20)

            // Cymatics logo + wordmark
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
            .offset(y: -10)

            Spacer().frame(height: 20)

            // Form
            VStack(spacing: 14) {
                // Email
                ZStack(alignment: .leading) {
                    if email.isEmpty {
                        Text("Email")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.5))
                            .padding(.leading, 10)
                    }
                    TextField("", text: $email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(10)
                        .disableAutocorrection(true)
                        .onSubmit { }
                }
                .background(Color.white.opacity(0.15))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

                // Password
                ZStack(alignment: .leading) {
                    if password.isEmpty {
                        Text("Password")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.5))
                            .padding(.leading, 10)
                    }
                    SecureField("", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(10)
                        .onSubmit {
                            if !email.isEmpty && !password.isEmpty {
                                appState.login(email: email, password: password)
                            }
                        }
                }
                .background(Color.white.opacity(0.15))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

                // Error message
                if let errorMessage = appState.subscriptionError {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Sign In button
                Button(action: {
                    appState.login(email: email, password: password)
                }) {
                    Group {
                        if appState.subscriptionStatus == .checking {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(.circular)
                        } else {
                            Text("Sign In")
                                .font(.system(size: 14, weight: .semibold))
                        }
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
                    .shadow(color: Color.mixLinkCyan.opacity(0.3), radius: 8)
                }
                .buttonStyle(.plain)
                .disabled(email.isEmpty || password.isEmpty || appState.subscriptionStatus == .checking)
                .opacity((email.isEmpty || password.isEmpty) ? 0.5 : 1)

                // Forgot password link
                Button(action: {
                    if let url = URL(string: "https://cymatics.fm/pages/forgot-password") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Forgot Password?")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.mixLinkCyan)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)
        }
        .frame(width: 300)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
    }

    // MARK: - Traffic Lights (same as MenuBarView)

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
