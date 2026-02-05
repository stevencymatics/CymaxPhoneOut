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
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}

/// App delegate to handle first-launch auto-open of the menubar panel
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // On first launch without permissions, auto-open the menubar panel
        // to show the permissions walkthrough immediately
        if !SystemAudioCapture.hasPermission() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.autoOpenMenuBarPanel()
            }
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
