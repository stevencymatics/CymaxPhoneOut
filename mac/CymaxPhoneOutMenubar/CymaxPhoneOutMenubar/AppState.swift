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
    
    init() {
        log("Mix Link started")
        log("Ready to stream system audio to your phone")
        updateQRCode()
        setupSleepWakeObservers()

        // Check permission immediately so the walkthrough shows on first open
        if !SystemAudioCapture.hasPermission() {
            needsPermission = true
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
    
    // #region agent log - debug file logger
    private func debugLog(_ hypothesisId: String, _ message: String, _ data: [String: Any] = [:]) {
        let logPath = "/Users/stevencymatics/Documents/Phone Audio Project/.cursor/debug.log"
        var logData: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "location": "AppState.swift",
            "sessionId": "debug-session",
            "hypothesisId": hypothesisId,
            "message": message,
            "data": data
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write((jsonString + "\n").data(using: .utf8)!)
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: (jsonString + "\n").data(using: .utf8))
            }
        }
    }
    // #endregion
    
    /// Open System Settings to Screen Recording permission pane
    func openScreenRecordingSettings() {
        SystemAudioCapture.openSystemSettings()
        log("Opened System Settings - please grant permission", level: .info)
    }
    
    private func startAudioCapture() {
        log("Starting system audio capture...")
        captureStatus = "Starting..."
        needsPermission = false  // Reset permission flag
        
        // #region agent log
        // Check Info.plist for required keys
        let screenCaptureDesc = Bundle.main.object(forInfoDictionaryKey: "NSScreenCaptureUsageDescription") as? String
        let hasPermission = SystemAudioCapture.hasPermission()
        debugLog("D", "Checking Info.plist keys and permission", [
            "NSScreenCaptureUsageDescription": screenCaptureDesc ?? "NOT SET",
            "hasPermission": hasPermission
        ])
        // #endregion
        
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
                // #region agent log
                debugLog("E", "About to call audioCapture.start()", [:])
                // #endregion
                
                try await audioCapture?.start()
                await MainActor.run {
                    // #region agent log
                    self.debugLog("E", "audioCapture.start() SUCCEEDED", [:])
                    // #endregion
                    self.isCaptureActive = true
                    self.captureStatus = "Capturing"
                }
            } catch {
                await MainActor.run {
                    // #region agent log
                    let nsError = error as NSError
                    self.debugLog("A,B,C,D,E", "audioCapture.start() FAILED in AppState", [
                        "errorDomain": nsError.domain,
                        "errorCode": nsError.code,
                        "errorDescription": error.localizedDescription,
                        "errorFull": String(describing: error)
                    ])
                    // #endregion
                    
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
        guard let url = QRCodeGenerator.getWebPlayerURL(httpPort: httpPort) else {
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
private var gStartTime: CFAbsoluteTime = 0
private let gAudioQueue = DispatchQueue(label: "com.cymax.audioprocessing", qos: .userInteractive)

/// Processes audio on a background queue - completely avoids Swift actor system
func processAudioGlobally(samples: [Float], sampleRate: Int, channels: Int, server: HTTPServer?, onPacketCount: @escaping @Sendable (Int) -> Void) {
    // Capture everything we need as values
    let samplesCopy = samples
    let sr = sampleRate
    let ch = channels
    
    gAudioQueue.async {
        // #region agent log - H5 track timing
        if gStartTime == 0 {
            gStartTime = CFAbsoluteTimeGetCurrent()
        }
        // #endregion
        
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
        
        // #region agent log - H5 rate measurement
        if gAudioPacketsSent % 500 == 0 {
            let elapsed = CFAbsoluteTimeGetCurrent() - gStartTime
            let expectedFrames = Int(elapsed * Double(sr))
            let drift = gTotalFramesSent - expectedFrames
            let effectiveRate = elapsed > 0 ? Double(gTotalFramesSent) / elapsed : 0
            
            let logPath = "/Users/stevencymatics/Documents/Phone Audio Project/.cursor/debug.log"
            let logData: [String: Any] = [
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "location": "AppState.processAudioGlobally",
                "sessionId": "debug-session",
                "hypothesisId": "H5",
                "message": "RATE_CHECK",
                "data": [
                    "elapsedSec": elapsed,
                    "totalFramesSent": gTotalFramesSent,
                    "expectedFrames": expectedFrames,
                    "drift": drift,
                    "driftPercent": expectedFrames > 0 ? Double(drift) / Double(expectedFrames) * 100 : 0,
                    "effectiveRate": effectiveRate,
                    "targetRate": sr,
                    "packetsTotal": gAudioPacketsSent
                ]
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write((jsonString + "\n").data(using: .utf8)!)
                    handle.closeFile()
                } else if FileManager.default.createFile(atPath: logPath, contents: (jsonString + "\n").data(using: .utf8)) {
                    // File created
                }
            }
        }
        // #endregion
        
        // Update UI periodically
        if packetCount > 0 && gAudioPacketsSent % 10 == 0 {
            let count = gAudioPacketsSent
            DispatchQueue.main.async {
                onPacketCount(count)
            }
        }
    }
}
