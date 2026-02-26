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

/// Pre-rendered waveform menubar icon (Apple TV audio-picker style, center-aligned bars)
private func makeMenuBarIcon(slashed: Bool) -> NSImage {
    let barHeights: [CGFloat] = [0.35, 0.7, 1.0, 0.7, 0.35]
    let barWidth: CGFloat = 2.0
    let gap: CGFloat = 2.0
    let maxH: CGFloat = 16.0
    let totalW = ceil(CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * gap)

    let img = NSImage(size: NSSize(width: totalW, height: maxH))
    img.lockFocus()
    NSColor.black.setFill()
    for i in 0..<barHeights.count {
        let h = max(4, maxH * barHeights[i])
        let x = CGFloat(i) * (barWidth + gap)
        let y = (maxH - h) / 2  // center-aligned vertically
        let rect = NSRect(x: x, y: y, width: barWidth, height: h)
        NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
    }
    if slashed {
        NSColor.black.setStroke()
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: totalW - 1, y: maxH - 1))
        slash.line(to: NSPoint(x: 1, y: 1))
        slash.lineWidth = 1.5
        slash.lineCapStyle = .round
        slash.stroke()
    }
    img.unlockFocus()
    img.isTemplate = true
    return img
}

private let menuBarIconActive = makeMenuBarIcon(slashed: false)
private let menuBarIconInactive = makeMenuBarIcon(slashed: true)

/// Menubar icon — wave bars when active, slashed wave bars when inactive
struct MenuBarLabel: View {
    let isActive: Bool

    var body: some View {
        Image(nsImage: isActive ? menuBarIconActive : menuBarIconInactive)
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
