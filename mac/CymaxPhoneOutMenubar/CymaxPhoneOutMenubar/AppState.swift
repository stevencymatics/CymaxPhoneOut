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
    private let subscriptionService = SubscriptionService()
    private var savedEmail: String?
    private var savedPassword: String?

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

        // Check permission immediately so the walkthrough shows on first open
        if !SystemAudioCapture.hasPermission() {
            needsPermission = true
        }

        // Auto-login if credentials are saved from a previous session
        if let creds = KeychainHelper.loadCredentials() {
            log("Found saved credentials for \(creds.email) — auto-logging in")
            savedEmail = creds.email
            savedPassword = creds.password
            subscriptionStatus = .active
            backgroundVerify(email: creds.email, password: creds.password)
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

    /// Re-detect IP address and update QR code + served HTML without restarting the server
    func refreshNetwork() {
        guard isServerRunning else { return }

        guard let localIP = QRCodeGenerator.getLocalIPAddress() else {
            log("Cannot detect IP address", level: .warning)
            return
        }

        let hostName = Host.current().localizedName ?? "Mac"
        let htmlContent = getWebPlayerHTML(wsPort: httpPort, hostIP: localIP, hostName: hostName)

        httpServer?.htmlContent = htmlContent
        webPlayerURL = "http://\(localIP):\(httpPort)"
        updateQRCode()

        log("Network refreshed: \(webPlayerURL ?? "unknown")")
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
    
    // MARK: - Subscription

    /// Authenticate with Shopify and check Recharge subscription status.
    func login(email: String, password: String) {
        subscriptionStatus = .checking
        subscriptionError = nil

        Task {
            do {
                let isActive = try await subscriptionService.checkSubscription(
                    email: email,
                    password: password
                )
                await MainActor.run {
                    if isActive {
                        self.subscriptionStatus = .active
                        self.subscriptionError = nil
                        self.savedEmail = email
                        self.savedPassword = password
                        KeychainHelper.saveCredentials(email: email, password: password)
                        self.log("Subscription verified — access granted, credentials saved", level: .info)
                    } else {
                        self.subscriptionStatus = .inactive
                        self.subscriptionError = nil
                        KeychainHelper.clearCredentials()
                        self.log("No active subscription for this product", level: .warning)
                    }
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    self.subscriptionStatus = .loginFailed(message)
                    self.subscriptionError = message
                    self.log("Login/subscription check failed: \(message)", level: .error)
                }
            }
        }
    }

    /// Run subscription verification silently in the background (used for auto-login).
    /// The app stays usable while this runs. Only revokes access on explicit failure.
    private func backgroundVerify(email: String, password: String) {
        isBackgroundVerifying = true
        log("Starting background verification for \(email)", level: .info)

        Task {
            do {
                let isActive = try await subscriptionService.checkSubscription(
                    email: email,
                    password: password
                )
                await MainActor.run {
                    self.isBackgroundVerifying = false
                    if isActive {
                        self.log("Background verification passed", level: .info)
                    } else {
                        self.log("Background verification: subscription no longer active", level: .warning)
                        self.subscriptionStatus = .inactive
                        KeychainHelper.clearCredentials()
                    }
                }
            } catch let error as SubscriptionServiceError {
                await MainActor.run {
                    self.isBackgroundVerifying = false
                    switch error {
                    case .invalidCredentials:
                        self.log("Background verification: credentials invalid — requiring re-login", level: .warning)
                        self.subscriptionStatus = .notChecked
                        self.subscriptionError = "Your session has expired. Please sign in again."
                        KeychainHelper.clearCredentials()
                    default:
                        // Network errors or transient issues — keep user logged in (grace period)
                        self.log("Background verification failed (non-critical): \(error.localizedDescription) — keeping access", level: .warning)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isBackgroundVerifying = false
                    // Unknown errors — keep user logged in (grace period)
                    self.log("Background verification error (non-critical): \(error.localizedDescription) — keeping access", level: .warning)
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
        log("User signed out — credentials cleared", level: .info)
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
