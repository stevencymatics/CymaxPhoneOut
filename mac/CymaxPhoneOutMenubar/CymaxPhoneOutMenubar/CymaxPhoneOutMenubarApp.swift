//
//  CymaxPhoneOutMenubarApp.swift
//  CymaxPhoneOutMenubar
//
//  macOS menubar application for streaming system audio to your phone
//

import SwiftUI
import AppKit

@main
struct CymaxPhoneOutMenubarApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarLabel(isActive: appState.isCaptureActive)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menubar icon with optional cyan activity indicator
struct MenuBarLabel: View {
    let isActive: Bool

    var body: some View {
        Image("CymaticsLogo")
            .renderingMode(.template)
            .overlay(alignment: .bottomTrailing) {
                if isActive {
                    Circle()
                        .fill(Color(red: 0, green: 212/255, blue: 1))
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: 2)
                }
            }
    }
}

/// App delegate to handle first-launch auto-open of the menubar panel
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always auto-open the menubar panel on launch so the login screen
        // (or permissions walkthrough) is shown immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.autoOpenMenuBarPanel()
        }
    }

    private func autoOpenMenuBarPanel() {
        NSApp.activate(ignoringOtherApps: true)

        // Find the status bar button created by MenuBarExtra and simulate a click
        // to open the popover showing the permissions walkthrough
        if !findAndClickStatusBarButton() {
            // Retry if MenuBarExtra hasn't finished initializing yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.findAndClickStatusBarButton()
            }
        }
    }

    @discardableResult
    private func findAndClickStatusBarButton() -> Bool {
        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            if clickStatusBarButton(in: contentView) {
                return true
            }
        }
        return false
    }

    private func clickStatusBarButton(in view: NSView) -> Bool {
        if view is NSStatusBarButton {
            (view as! NSStatusBarButton).performClick(nil)
            return true
        }
        for subview in view.subviews {
            if clickStatusBarButton(in: subview) {
                return true
            }
        }
        return false
    }
}
