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
import Network

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
    
    // Logging
    @Published var logMessages: [LogMessage] = []
    
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

    // Network monitoring
    private var pathMonitor: NWPathMonitor?
    private var pathMonitorQueue = DispatchQueue(label: "com.cymax.pathmonitor")
    private nonisolated(unsafe) var networkDebounceWork: DispatchWorkItem?

    init() {
        log("Cymatics Link started")
        log("Ready to stream system audio to your phone")
        updateQRCode()
        setupSleepWakeObservers()
        startNetworkMonitor()

        // Don't proactively check permission — let capture attempt handle it.
        // On macOS 26, the proactive check can false-negative even when permission is granted.
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
    
    // MARK: - Network Monitoring

    private func startNetworkMonitor() {
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            // Debounce: NWPathMonitor fires rapidly during transitions
            self?.networkDebounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.handleNetworkChange(path)
                }
            }
            self?.networkDebounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        pathMonitor?.start(queue: pathMonitorQueue)
    }

    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
        networkDebounceWork?.cancel()
    }

    private func handleNetworkChange(_ path: NWPath) {
        guard isServerRunning else { return }

        // Get the first active interface name from NWPathMonitor
        let preferredInterface = path.availableInterfaces.first?.name

        guard let newIP = QRCodeGenerator.getLocalIPAddress(preferredInterface: preferredInterface) else {
            log("Network changed but no IP available", level: .warning)
            return
        }

        let currentURL = webPlayerURL
        let port = httpServer?.actualPort ?? httpPort
        let newURL = "http://\(newIP):\(port)"

        if newURL != currentURL {
            log("Network changed: \(currentURL ?? "none") -> \(newURL)", level: .info)
            webPlayerURL = newURL

            // Regenerate HTML with new IP
            let hostName = Host.current().localizedName ?? "Mac"
            let htmlContent = getWebPlayerHTML(wsPort: port, hostIP: newIP, hostName: hostName)
            httpServer?.htmlContent = htmlContent

            // Update QR code
            updateQRCode()
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

        // Verify permission asynchronously, then restart if needed
        Task {
            let hasPermission = await SystemAudioCapture.checkPermissionAsync()
            await MainActor.run {
                if !hasPermission {
                    self.log("Permission lost after wake", level: .warning)
                    self.needsPermission = true
                    self.isServerRunning = false
                    self.isCaptureActive = false
                    self.webClientsConnected = 0
                    self.packetsSent = 0
                    self.captureStatus = "Permission Required"
                    return
                }

                if self.wasRunningBeforeSleep {
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
        pathMonitor?.cancel()
        pathMonitor = nil
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
        
        // Get local IP (use NWPathMonitor's preferred interface if available)
        let preferredIface = pathMonitor?.currentPath.availableInterfaces.first?.name
        guard let localIP = QRCodeGenerator.getLocalIPAddress(preferredInterface: preferredIface) else {
            log("Cannot get local IP address", level: .error)
            log("Make sure you're connected to WiFi", level: .warning)
            return
        }
        
        // Get Mac's computer name
        let hostName = Host.current().localizedName ?? "Mac"

        // Start combined HTTP + WebSocket server (same port for Safari)
        httpServer = HTTPServer(port: httpPort)
        httpServer?.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                self?.webClientsConnected = count
                self?.log("Browser clients: \(count)")
            }
        }
        httpServer?.start()

        guard let server = httpServer, server.actualPort > 0 else {
            log("Failed to bind to any port", level: .error)
            httpServer = nil
            return
        }

        let boundPort = server.actualPort

        // Generate HTML with the actual bound port
        let htmlContent = getWebPlayerHTML(wsPort: boundPort, hostIP: localIP, hostName: hostName)
        httpServer?.htmlContent = htmlContent

        isServerRunning = true
        webPlayerURL = "http://\(localIP):\(boundPort)"

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
    
    // MARK: - QR Code
    
    private func updateQRCode() {
        let port = httpServer?.actualPort ?? httpPort
        guard let url = QRCodeGenerator.getWebPlayerURL(httpPort: port) else {
            qrCodeImage = nil
            webPlayerURL = nil
            return
        }

        webPlayerURL = url
        qrCodeImage = QRCodeGenerator.generate(url: url, size: 200)
    }
    
    // MARK: - Logging
    
    func log(_ message: String, level: LogLevel = .info) {
        let logMessage = LogMessage(timestamp: Date(), level: level, message: message)
        logMessages.append(logMessage)
        
        // Keep last 100 messages
        if logMessages.count > 100 {
            logMessages.removeFirst(logMessages.count - 100)
        }
        
        print("[\(level.rawValue)] \(message)")
    }
}

// MARK: - Log Message

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    
    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct LogMessage: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Audio Processor (Thread-safe using OSAtomic-style counters)

/// Global audio processing state - avoids Swift concurrency issues
private var gAudioSequence: UInt32 = 0
private var gAudioPacketsSent: Int = 0
private var gTotalFramesSent: Int = 0
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
        var framesThisBatch = 0
        
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
            gTotalFramesSent += frameCount
            framesThisBatch += frameCount
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
