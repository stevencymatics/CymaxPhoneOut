//
//  AppState.swift
//  CymaxPhoneOutMenubar
//
//  Application state management
//

import Foundation
import SwiftUI
import Combine

/// Represents a discovered iPhone receiver
struct DiscoveredDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let hostName: String
    let port: Int
    let ipAddress: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Connection status
enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}

/// Statistics from the iOS receiver
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
    // Discovery
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var selectedDevice: DiscoveredDevice?
    
    // Connection
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isStreaming: Bool = false
    
    // Audio configuration
    @Published var sampleRate: UInt32 = 48000
    @Published var bufferSize: UInt32 = 256
    
    // Statistics
    @Published var stats: ReceiverStats = ReceiverStats()
    @Published var estimatedLatencyMs: Double = 25.0
    
    // Logging
    @Published var logMessages: [LogMessage] = []
    
    // Services
    private var bonjourBrowser: BonjourBrowser?
    private var controlChannel: ControlChannelClient?
    private var driverCommunication: DriverCommunication?
    
    init() {
        setupServices()
    }
    
    private func setupServices() {
        bonjourBrowser = BonjourBrowser { [weak self] devices in
            Task { @MainActor in
                self?.discoveredDevices = devices
                self?.log("Found \(devices.count) device(s)")
            }
        }
        
        driverCommunication = DriverCommunication()
        driverCommunication?.onLog = { [weak self] message in
            Task { @MainActor in
                self?.log("Driver: \(message)")
            }
        }
        
        // Add default USB tethering device since Bonjour may not work
        let usbDevice = DiscoveredDevice(
            id: "usb-tethering-default",
            name: "iPhone (USB)",
            hostName: "172.20.10.1",
            port: 19621,
            ipAddress: "172.20.10.1"
        )
        discoveredDevices = [usbDevice]
        
        log("Cymax Phone Out Menubar started")
        log("Default USB device: 172.20.10.1:19621")
        
        // Check network status
        checkNetworkStatus()
    }
    
    func checkNetworkStatus() {
        // Run network diagnostics
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-t", "1", "172.20.10.1"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                await MainActor.run {
                    if process.terminationStatus == 0 {
                        log("✓ iPhone reachable at 172.20.10.1", level: .info)
                    } else {
                        log("✗ Cannot reach 172.20.10.1 - Check USB tethering", level: .warning)
                        log("Tip: Settings > Personal Hotspot must be ON", level: .info)
                    }
                }
            } catch {
                await MainActor.run {
                    log("Network check failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    func startBrowsing() {
        bonjourBrowser?.startBrowsing()
        log("Started browsing for receivers")
    }
    
    func stopBrowsing() {
        bonjourBrowser?.stopBrowsing()
    }
    
    func selectDevice(_ device: DiscoveredDevice) {
        selectedDevice = device
        log("Selected device: \(device.name)")
    }
    
    func connect() {
        guard let device = selectedDevice else {
            log("No device selected", level: .error)
            return
        }
        
        guard let ipAddress = device.ipAddress else {
            log("No IP address for device", level: .error)
            return
        }
        
        connectionStatus = .connecting
        log("Connecting to \(device.name) at \(ipAddress)...")
        
        // Set destination IP in driver
        driverCommunication?.setDestinationIP(ipAddress)
        
        // Connect control channel
        controlChannel = ControlChannelClient(
            host: ipAddress,
            port: 19621,
            onStats: { [weak self] stats in
                Task { @MainActor in
                    self?.updateStats(stats)
                }
            },
            onDisconnect: { [weak self] reason in
                Task { @MainActor in
                    self?.handleDisconnect(reason: reason)
                }
            }
        )
        
        Task {
            do {
                try await controlChannel?.connect()
                try await controlChannel?.sendHello(
                    deviceName: Host.current().localizedName ?? "Mac",
                    sampleRate: sampleRate,
                    channels: 2
                )
                connectionStatus = .connected
                log("Connected to \(device.name)")
            } catch {
                connectionStatus = .error(error.localizedDescription)
                log("Connection failed: \(error.localizedDescription)", level: .error)
            }
        }
    }
    
    func disconnect() {
        controlChannel?.disconnect()
        controlChannel = nil
        driverCommunication?.clearDestinationIP()
        connectionStatus = .disconnected
        isStreaming = false
        log("Disconnected")
    }
    
    func startStreaming() {
        guard connectionStatus == .connected else {
            log("Cannot stream: not connected", level: .error)
            return
        }
        
        isStreaming = true
        log("Streaming started")
    }
    
    func stopStreaming() {
        isStreaming = false
        log("Streaming stopped")
    }
    
    // MARK: - Private
    
    private func updateStats(_ stats: ReceiverStats) {
        self.stats = stats
        
        // Calculate estimated latency
        let bufferLatency = Double(bufferSize) / Double(sampleRate) * 1000.0
        estimatedLatencyMs = bufferLatency + stats.bufferLevelMs + 2.0  // +2ms for network
    }
    
    private func handleDisconnect(reason: String) {
        connectionStatus = .disconnected
        isStreaming = false
        log("Disconnected: \(reason)", level: .warning)
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        let logMessage = LogMessage(timestamp: Date(), level: level, message: message)
        logMessages.append(logMessage)
        
        // Keep last 100 messages
        if logMessages.count > 100 {
            logMessages.removeFirst(logMessages.count - 100)
        }
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

