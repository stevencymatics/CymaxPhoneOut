//
//  AppState.swift
//  CymaxPhoneOutMenubar
//
//  Application state management
//

import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - Subscription Status

enum SubscriptionStatus: Equatable {
    case notChecked
    case checking
    case active
    case inactive
    case loginFailed(String)

    static func == (lhs: SubscriptionStatus, rhs: SubscriptionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notChecked, .notChecked),
             (.checking, .checking),
             (.active, .active),
             (.inactive, .inactive):
            return true
        case (.loginFailed(let a), .loginFailed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// Legacy types kept for compatibility with unused files
struct DiscoveredDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let hostName: String
    let port: Int
    let ipAddress: String?
}

struct ReceiverStats {
    var packetsReceived: UInt64 = 0
    var packetsLost: UInt64 = 0
    var jitterMs: Double = 0
    var bufferLevelMs: Double = 0
    var lossPercentage: Double = 0
}

/// Main application state
@MainActor
class AppState: ObservableObject {
    
    // Subscription state
    @Published var subscriptionStatus: SubscriptionStatus = .notChecked
    @Published var subscriptionError: String? = nil
    @Published var isBackgroundVerifying: Bool = false
    @Published var viewPlansUrl: String? = nil
    private let subscriptionService = SubscriptionService()
    private var savedEmail: String?
    private var savedPassword: String?

    // Grace period — UserDefaults key for the last successful verification timestamp
    private static let lastVerifiedKey = "com.cymatics.mixlink.lastVerifiedAt"

    // Update check — stores the version the user dismissed so we don't nag every launch
    private static let dismissedUpdateVersionKey = "com.cymatics.mixlink.dismissedUpdateVersion"

    // Server state
    @Published var isServerRunning: Bool = false
    @Published var webClientsConnected: Int = 0
    @Published var qrCodeImage: NSImage?
    @Published var webPlayerURL: String?
    
    // Capture state
    @Published var isCaptureActive: Bool = false
    @Published var captureStatus: String = "Ready"
    @Published var needsPermission: Bool = false
    
    // Stats
    @Published var packetsSent: Int = 0
    
    // Services
    private var audioCapture: SystemAudioCapture?
    private var httpServer: HTTPServer?  // Combined HTTP + WebSocket server
    
    // Audio packet building
    private var sequenceNumber: UInt32 = 0
    
    // Ports - now using single port for both HTTP and WebSocket (Safari compatibility)
    private let httpPort: UInt16 = 19621
    
    // Sleep/wake handling
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var wasRunningBeforeSleep = false
    
    // Health check
    private var healthCheckTimer: Timer?
    private var lastPacketCount: Int = 0
    private var stalePacketCheckCount: Int = 0
    
    init() {
        log("Cymatics Mix Link started")
        log("Ready to stream system audio to your phone")
        updateQRCode()
        setupSleepWakeObservers()

        // Check permission so the walkthrough shows on first open
        if !SystemAudioCapture.hasPermission() {
            needsPermission = true
        }

        // Auto-login if credentials are saved from a previous session
        if let creds = KeychainHelper.loadCredentials() {
            log("Found saved credentials for \(creds.email) — auto-logging in")
            savedEmail = creds.email
            savedPassword = creds.password

            // If we verified recently, show app immediately and verify in background.
            // Otherwise, block on verification — don't grant access without proof.
            if isWithinGracePeriod() {
                subscriptionStatus = .active
                log("Within grace period — showing app immediately")
                backgroundVerify(email: creds.email, password: creds.password)
            } else {
                subscriptionStatus = .checking
                log("Grace period expired — must verify before granting access")
                foregroundVerify(email: creds.email, password: creds.password)
            }
        }
    }
    
    private func setupSleepWakeObservers() {
        // Observe when Mac is about to sleep
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSleep()
            }
        }
        
        // Observe when Mac wakes up
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }
    
    private func handleSleep() {
        log("Mac going to sleep...", level: .info)
        wasRunningBeforeSleep = isServerRunning
        if isServerRunning {
            stopServer()
            log("Servers stopped for sleep", level: .info)
        }
    }
    
    private func handleWake() {
        log("Mac woke up", level: .info)
        
        // First, verify permission is still valid
        if !SystemAudioCapture.hasPermission() {
            log("Permission lost after wake", level: .warning)
            needsPermission = true
            // Reset state
            isServerRunning = false
            isCaptureActive = false
            webClientsConnected = 0
            packetsSent = 0
            captureStatus = "Permission Required"
            return
        }
        
        if wasRunningBeforeSleep {
            // Small delay to let network come back up
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    self.log("Auto-restarting servers...", level: .info)
                    self.startServer()
                    
                    // Verify capture started successfully after a delay
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 more seconds
                        await MainActor.run {
                            if self.isServerRunning && !self.isCaptureActive && !self.needsPermission {
                                self.log("Capture failed to start after wake, resetting...", level: .error)
                                self.resetToInitialState(reason: "Capture failed after wake")
                            }
                        }
                    }
                }
            }
        }
    }
    
    deinit {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        healthCheckTimer?.invalidate()
    }
    
    // MARK: - Health Check
    
    private func startHealthCheck() {
        lastPacketCount = 0
        stalePacketCheckCount = 0
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performHealthCheck()
            }
        }
    }
    
    private func stopHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    private func performHealthCheck() {
        guard isServerRunning else { return }
        
        // CRITICAL: Check if permission was revoked while running
        if !SystemAudioCapture.hasPermission() {
            log("Permission was revoked!", level: .error)
            resetToInitialState(reason: "Permission revoked")
            needsPermission = true
            return
        }
        
        // Check if audio capture is still working
        if isCaptureActive && webClientsConnected > 0 {
            // If we have clients but packets aren't increasing, something's wrong
            if packetsSent == lastPacketCount {
                stalePacketCheckCount += 1
                
                if stalePacketCheckCount >= 3 {
                    // 15 seconds of no new packets with active clients - restart
                    log("Audio capture appears stalled, restarting...", level: .warning)
                    restartAudioCapture()
                    stalePacketCheckCount = 0
                }
            } else {
                stalePacketCheckCount = 0
            }
            lastPacketCount = packetsSent
        }
        
        // Check if capture died
        if !isCaptureActive && isServerRunning && !needsPermission {
            log("Audio capture stopped unexpectedly, restarting...", level: .warning)
            startAudioCapture()
        }
    }
    
    /// Reset app to initial "not running" state
    private func resetToInitialState(reason: String) {
        log("Resetting to initial state: \(reason)", level: .warning)
        
        // Stop everything
        stopHealthCheck()
        stopAudioCapture()
        
        httpServer?.stop()
        httpServer = nil
        
        // Reset all state
        isServerRunning = false
        isCaptureActive = false
        webClientsConnected = 0
        packetsSent = 0
        captureStatus = "Ready"
        
        log("App reset complete")
    }
    
    private func restartAudioCapture() {
        stopAudioCapture()
        
        // Brief delay before restarting
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await MainActor.run {
                self.startAudioCapture()
            }
        }
    }
    
    // MARK: - Server Control
    
    func startServer() {
        guard !isServerRunning else { return }
        
        log("Starting server...")
        
        // Check permission FIRST before starting anything
        if !SystemAudioCapture.hasPermission() {
            log("Permission not granted", level: .warning)
            needsPermission = true
            captureStatus = "Permission Required"
            return
        }
        
        // Get local IP
        guard let localIP = QRCodeGenerator.getLocalIPAddress() else {
            log("Cannot get local IP address", level: .error)
            log("Make sure you're connected to WiFi", level: .warning)
            return
        }
        
        // Get Mac's computer name
        let hostName = Host.current().localizedName ?? "Mac"
        
        // Generate HTML with same port for WebSocket (Safari compatibility)
        let htmlContent = getWebPlayerHTML(wsPort: httpPort, hostIP: localIP, hostName: hostName)
        
        // Start combined HTTP + WebSocket server (same port for Safari)
        httpServer = HTTPServer(port: httpPort)
        httpServer?.htmlContent = htmlContent
        httpServer?.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                self?.webClientsConnected = count
                self?.log("Browser clients: \(count)")
            }
        }
        httpServer?.start()
        
        isServerRunning = true
        webPlayerURL = "http://\(localIP):\(httpPort)"
        
        // Generate QR code
        updateQRCode()
        
        log("Server started!")
        log("URL: \(webPlayerURL ?? "unknown")")
        
        // Start audio capture
        startAudioCapture()
        
        // Start health check timer
        startHealthCheck()
    }
    
    func stopServer() {
        guard isServerRunning else { return }
        
        log("Stopping server...")
        
        // Stop health check
        stopHealthCheck()
        
        // Stop audio capture
        stopAudioCapture()
        
        httpServer?.stop()
        httpServer = nil
        
        isServerRunning = false
        webClientsConnected = 0
        packetsSent = 0
        
        log("Server stopped")
    }
    
    // MARK: - Audio Capture
    
    /// Open System Settings to Screen Recording permission pane
    func openScreenRecordingSettings() {
        // Register the app in the permissions list (adds the toggle)
        _ = SystemAudioCapture.requestPermission()
        // Open Settings immediately — the toggle is now there
        SystemAudioCapture.openSystemSettings()
        log("Opened System Settings - please grant permission", level: .info)
    }
    
    private func startAudioCapture() {
        log("Starting system audio capture...")
        captureStatus = "Starting..."
        needsPermission = false  // Reset permission flag

        audioCapture = SystemAudioCapture()
        
        audioCapture?.onStatusUpdate = { [weak self] status in
            Task { @MainActor in
                self?.captureStatus = status
                self?.log("Capture: \(status)")
            }
        }
        
        audioCapture?.onError = { [weak self] error in
            Task { @MainActor in
                self?.captureStatus = "Error"
                self?.log("Capture error: \(error)", level: .error)
            }
        }
        
        audioCapture?.onAudioSamples = { [weak self] samples, sampleRate, channels in
            guard let self = self else { return }
            // Process audio in background to avoid main thread congestion
            self.processAudioInBackground(samples, sampleRate: sampleRate, channels: channels)
        }
        
        Task {
            do {
                try await audioCapture?.start()
                await MainActor.run {
                    self.isCaptureActive = true
                    self.captureStatus = "Capturing"
                }
            } catch {
                await MainActor.run {
                    // Check if it's a permission issue
                    if let captureError = error as? CaptureError, captureError == .notAuthorized {
                        self.needsPermission = true
                        self.captureStatus = "Permission Required"
                        self.log("Screen Recording permission required", level: .warning)
                        self.log("Click 'Open Settings' below to grant permission", level: .info)
                    } else {
                        self.log("Failed to start capture: \(error.localizedDescription)", level: .error)
                        self.captureStatus = "Failed"
                    }
                }
            }
        }
    }
    
    private func stopAudioCapture() {
        audioCapture?.stop()
        audioCapture = nil
        isCaptureActive = false
        captureStatus = "Stopped"
    }
    
    /// Process audio in background to avoid main thread congestion
    private func processAudioInBackground(_ samples: [Float], sampleRate: Int, channels: Int) {
        // Capture what we need - now using combined HTTP+WebSocket server
        let server = httpServer
        let clientCount = webClientsConnected
        
        guard clientCount > 0 else { return }
        guard samples.count > 0 else { return }
        guard channels > 0 else { return }
        
        // Use global function to completely avoid Swift actor issues
        processAudioGlobally(samples: samples, sampleRate: sampleRate, channels: channels, server: server) { [weak self] count in
            Task { @MainActor in
                self?.packetsSent = count
            }
        }
    }
    
    // MARK: - Network Refresh

    /// Re-detect IP address and restart the server on the new network.
    /// A full stop/start cycle ensures the TCP listener binds cleanly after a network change.
    func refreshNetwork() {
        guard isServerRunning else { return }

        log("Network change detected — restarting server...")
        stopServer()

        // Brief delay to let the new network interface settle
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await MainActor.run {
                self.startServer()
            }
        }
    }

    // MARK: - QR Code

    private func updateQRCode() {
        guard let url = QRCodeGenerator.getWebPlayerURL(httpPort: httpPort) else {
            qrCodeImage = nil
            webPlayerURL = nil
            return
        }
        
        webPlayerURL = url
        qrCodeImage = QRCodeGenerator.generate(url: url, size: 200)
    }
    
    // MARK: - Grace Period Helpers

    /// Record a successful verification timestamp.
    private func markVerificationSuccess() {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastVerifiedKey)
        log("Grace period: recorded successful verification at \(now)", level: .info)
    }

    /// Returns true if we are still within the grace period from the last successful verification.
    private func isWithinGracePeriod() -> Bool {
        let lastVerified = UserDefaults.standard.double(forKey: Self.lastVerifiedKey)
        guard lastVerified > 0 else {
            log("Grace period: no previous verification on record", level: .info)
            return false
        }
        let elapsed = Date().timeIntervalSince1970 - lastVerified
        let grace = SubscriptionConfig.effectiveGracePeriod
        let remaining = grace - elapsed
        if remaining > 0 {
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            log("Grace period: \(hours)h \(minutes)m remaining (elapsed: \(Int(elapsed))s of \(Int(grace))s)", level: .info)
            return true
        } else {
            log("Grace period: expired (\(Int(elapsed))s elapsed, grace was \(Int(grace))s)", level: .warning)
            return false
        }
    }

    /// Clear the grace period timestamp.
    private func clearGracePeriod() {
        UserDefaults.standard.removeObject(forKey: Self.lastVerifiedKey)
    }

    // MARK: - Subscription

    /// Verify credentials and subscription status via the Cloudflare Worker.
    /// Credentials are saved after any non-invalid-credentials response so the
    /// user only types their password once.
    func login(email: String, password: String) {
        subscriptionStatus = .checking
        subscriptionError = nil

        Task {
            do {
                let result = try await subscriptionService.verifyLicense(
                    email: email,
                    password: password
                )
                await MainActor.run {
                    self.checkForUpdate(result: result)

                    if result.accessGranted {
                        self.savedEmail = email
                        self.savedPassword = password
                        KeychainHelper.saveCredentials(email: email, password: password)
                        self.subscriptionStatus = .active
                        self.subscriptionError = nil
                        self.viewPlansUrl = result.viewPlansUrl
                        self.markVerificationSuccess()
                        self.log("Subscription verified — access granted, credentials saved", level: .info)
                    } else {
                        switch result.reason {
                        case "invalid_credentials":
                            self.subscriptionStatus = .loginFailed("Invalid email or password.")
                            self.subscriptionError = "Invalid email or password."
                            self.log("Invalid credentials — not saving", level: .error)
                        case "inactive_subscription", "no_purchase":
                            self.savedEmail = email
                            self.savedPassword = password
                            KeychainHelper.saveCredentials(email: email, password: password)
                            self.subscriptionStatus = .inactive
                            self.subscriptionError = nil
                            self.viewPlansUrl = result.viewPlansUrl
                            self.log("No active subscription — credentials saved for next attempt", level: .warning)
                        default:
                            let message = "Verification failed. Please try again later."
                            self.subscriptionStatus = .loginFailed(message)
                            self.subscriptionError = message
                            self.log("Unknown reason: \(result.reason ?? "nil")", level: .error)
                        }
                    }
                }
            } catch let error as SubscriptionServiceError {
                await MainActor.run {
                    switch error {
                    case .networkError:
                        // Network errors — save credentials so they can retry on relaunch
                        self.savedEmail = email
                        self.savedPassword = password
                        KeychainHelper.saveCredentials(email: email, password: password)
                        let message = "Cannot reach server. Check your internet connection."
                        self.subscriptionStatus = .loginFailed(message)
                        self.subscriptionError = message
                        self.log("Network error — credentials saved for retry", level: .error)
                    default:
                        let message = error.localizedDescription
                        self.subscriptionStatus = .loginFailed(message)
                        self.subscriptionError = message
                        self.log("Login check failed: \(message)", level: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    self.subscriptionStatus = .loginFailed(message)
                    self.subscriptionError = message
                    self.log("Login check failed: \(message)", level: .error)
                }
            }
        }
    }

    /// Run subscription verification silently in the background (used for auto-login).
    /// The app stays usable while this runs. If subscription is found inactive,
    /// the grace period is checked before revoking access.
    private func backgroundVerify(email: String, password: String) {
        isBackgroundVerifying = true
        log("Starting background verification for \(email)", level: .info)

        Task {
            do {
                let result = try await subscriptionService.verifyLicense(
                    email: email,
                    password: password
                )
                await MainActor.run {
                    self.isBackgroundVerifying = false
                    self.viewPlansUrl = result.viewPlansUrl

                    // Check for app updates regardless of subscription status
                    self.checkForUpdate(result: result)

                    if result.accessGranted {
                        self.markVerificationSuccess()
                        self.log("Background verification passed", level: .info)
                    } else if result.reason == "invalid_credentials" {
                        self.log("Background verification: credentials invalid — requiring re-login", level: .warning)
                        self.subscriptionStatus = .notChecked
                        self.subscriptionError = "Your session has expired. Please sign in again."
                        KeychainHelper.clearCredentials()
                        self.clearGracePeriod()
                    } else {
                        // Subscription inactive / no purchase — check grace period
                        if self.isWithinGracePeriod() {
                            self.log("Background verification: subscription inactive but within grace period — keeping access", level: .warning)
                        } else {
                            self.log("Background verification: subscription inactive and grace period expired — revoking access", level: .warning)
                            self.subscriptionStatus = .inactive
                            KeychainHelper.clearCredentials()
                            self.clearGracePeriod()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isBackgroundVerifying = false
                    if self.isWithinGracePeriod() {
                        self.log("Background verification failed — within grace period, keeping access", level: .warning)
                    } else {
                        self.log("Background verification failed — grace period expired, revoking access", level: .warning)
                        self.subscriptionStatus = .inactive
                        KeychainHelper.clearCredentials()
                        self.clearGracePeriod()
                    }
                }
            }
        }
    }

    /// Verify subscription in the foreground — app stays in `.checking` state until resolved.
    /// Used when grace period has expired and we need proof before granting access.
    private func foregroundVerify(email: String, password: String) {
        log("Starting foreground verification for \(email)", level: .info)

        Task {
            do {
                let result = try await subscriptionService.verifyLicense(
                    email: email,
                    password: password
                )
                await MainActor.run {
                    self.viewPlansUrl = result.viewPlansUrl
                    self.checkForUpdate(result: result)

                    if result.accessGranted {
                        self.markVerificationSuccess()
                        self.subscriptionStatus = .active
                        self.log("Foreground verification passed — access granted", level: .info)
                    } else if result.reason == "invalid_credentials" {
                        self.log("Foreground verification: credentials invalid — requiring re-login", level: .warning)
                        self.subscriptionStatus = .notChecked
                        self.subscriptionError = "Your session has expired. Please sign in again."
                        KeychainHelper.clearCredentials()
                        self.clearGracePeriod()
                    } else {
                        // Subscription inactive / no purchase
                        self.log("Foreground verification: subscription inactive — locking out", level: .warning)
                        self.subscriptionStatus = .inactive
                    }
                }
            } catch {
                await MainActor.run {
                    // Network error with no grace period — stay locked
                    let message = "Cannot reach server. Check your internet connection and try again."
                    self.subscriptionStatus = .loginFailed(message)
                    self.subscriptionError = message
                    self.log("Foreground verification failed (network): \(error.localizedDescription) — staying locked", level: .error)
                }
            }
        }
    }

    /// Reset subscription state so the login screen shows again.
    func signOut() {
        subscriptionStatus = .notChecked
        subscriptionError = nil
        savedEmail = nil
        savedPassword = nil
        KeychainHelper.clearCredentials()
        clearGracePeriod()
        log("User signed out — credentials and grace period cleared", level: .info)
    }

    // MARK: - Update Check

    /// Check if the worker returned a newer version and prompt the user once per version.
    private func checkForUpdate(result: VerifyResult) {
        guard let latestVersion = result.latestVersion,
              let updateUrl = result.updateUrl,
              let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return }

        // Compare versions — only prompt if latest is strictly newer
        guard isVersion(latestVersion, newerThan: currentVersion) else {
            log("App is up to date (current: \(currentVersion), latest: \(latestVersion))", level: .info)
            return
        }

        // Don't nag if the user already dismissed this version
        let dismissed = UserDefaults.standard.string(forKey: Self.dismissedUpdateVersionKey)
        if dismissed == latestVersion {
            log("Update \(latestVersion) available but user previously dismissed", level: .info)
            return
        }

        log("Update available: \(currentVersion) → \(latestVersion)", level: .info)

        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Cymatics Mix Link \(latestVersion) is available."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: updateUrl) {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Remember this version so we don't prompt again
            UserDefaults.standard.set(latestVersion, forKey: Self.dismissedUpdateVersionKey)
        }
    }

    /// Simple semantic version comparison (supports "1.0", "1.0.0", "1.2.3", etc.)
    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(partsA.count, partsB.count)
        for i in 0..<maxLen {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }

    // MARK: - Logging

    func log(_ message: String, level: LogLevel = .info) {
        let line = "[\(level.rawValue)] \(message)\n"
        print(line, terminator: "")
        debugLogToFile(line)
    }
}

// MARK: - Log Level

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

// MARK: - Debug File Logging

private let debugLogFileHandle: FileHandle? = {
    let path = "/tmp/cymatics_debug.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()
private let debugLogLock = NSLock()

func debugLogToFile(_ message: String) {
    debugLogLock.lock()
    defer { debugLogLock.unlock() }
    if let data = message.data(using: .utf8) {
        debugLogFileHandle?.seekToEndOfFile()
        debugLogFileHandle?.write(data)
    }
}

// MARK: - Audio Processor (Thread-safe using OSAtomic-style counters)

/// Global audio processing state - avoids Swift concurrency issues
private var gAudioSequence: UInt32 = 0
private var gAudioPacketsSent: Int = 0
private let gAudioQueue = DispatchQueue(label: "com.cymax.audioprocessing", qos: .userInteractive)

/// Processes audio on a background queue - completely avoids Swift actor system
func processAudioGlobally(samples: [Float], sampleRate: Int, channels: Int, server: HTTPServer?, onPacketCount: @escaping @Sendable (Int) -> Void) {
    // Capture everything we need as values
    let samplesCopy = samples
    let sr = sampleRate
    let ch = channels
    
    gAudioQueue.async {
        let framesPerPacket = 128
        let samplesPerPacket = framesPerPacket * ch
        
        var offset = 0
        var packetCount = 0
        
        while offset < samplesCopy.count {
            let end = min(offset + samplesPerPacket, samplesCopy.count)
            guard end > offset else { break }
            
            let chunkSamples = Array(samplesCopy[offset..<end])
            guard chunkSamples.count > 0 else { break }
            
            let frameCount = chunkSamples.count / ch
            guard frameCount > 0 else { break }
            
            // Create audio data from samples
            var audioData: Data?
            chunkSamples.withUnsafeBufferPointer { buffer in
                if let baseAddress = buffer.baseAddress {
                    audioData = Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Float>.size)
                }
            }
            
            guard let data = audioData else {
                offset = end
                continue
            }
            
            // Create and send packet using global counters
            let seq = gAudioSequence
            gAudioSequence &+= 1
            
            // Build packet values safely
            let ts = UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
            
            let audioPacket = AudioPacket(
                sequence: seq,
                timestamp: ts,
                sampleRate: UInt32(sr),
                channels: UInt16(ch),
                frameCount: UInt16(frameCount),
                audioData: data
            )
            
            // Broadcast on the WebSocket's own queue to avoid thread issues
            server?.broadcast(audioPacket)
            
            gAudioPacketsSent += 1
            packetCount += 1
            
            offset = end
        }
        
        // Update UI periodically
        if packetCount > 0 && gAudioPacketsSent % 10 == 0 {
            let count = gAudioPacketsSent
            DispatchQueue.main.async {
                onPacketCount(count)
            }
        }
    }
}
