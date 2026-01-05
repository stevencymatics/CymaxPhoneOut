//
//  ReceiverState.swift
//  CymaxPhoneReceiver
//
//  Main state management for the iOS receiver
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import Network

/// Connection state
enum ReceiverConnectionState: Equatable {
    case idle
    case advertising
    case connected(String)  // Mac device name
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .advertising: return "Ready - Waiting for Mac"
        case .connected(let name): return "Connected to \(name)"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Latency mode
enum LatencyMode: String, CaseIterable {
    case lowLatency = "Low Latency"
    case stable = "Stable"
    
    var jitterBufferMs: Double {
        switch self {
        case .lowLatency: return 250.0   // 250ms prebuffer for lower latency
        case .stable: return 400.0       // 400ms prebuffer for stability
        }
    }
}

/// Main receiver state
@MainActor
class ReceiverState: ObservableObject {
    // Connection
    @Published var connectionState: ReceiverConnectionState = .idle
    @Published var isReceiving: Bool = false
    
    // Audio configuration
    @Published var sampleRate: UInt32 = 48000
    @Published var channels: UInt16 = 2
    @Published var latencyMode: LatencyMode = .stable
    
    // Statistics
    @Published var packetsReceived: UInt64 = 0
    @Published var packetsLost: UInt64 = 0
    @Published var packetsDropped: UInt64 = 0
    @Published var underrunCount: Int = 0
    @Published var jitterMs: Double = 0
    @Published var bufferLevelMs: Double = 0
    @Published var lossPercentage: Double = 0
    
    // Debug logging
    @Published var logMessages: [String] = []
    
    // Services
    private var bonjourAdvertiser: BonjourAdvertiser?
    private var controlServer: ControlChannelServer?
    private var audioReceiver: AudioReceiver?
    private var audioPlayer: AudioPlayer?
    
    // Timers
    private var statsTimer: Timer?
    
    init() {
        setupAudioSession()
        addLog("CymaxPhoneReceiver initialized")
        addLog("Device: \(UIDevice.current.name)")
        logNetworkInfo()
    }
    
    func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        logMessages.append(logEntry)
        print(logEntry)
        
        // Keep last 200 messages
        if logMessages.count > 200 {
            logMessages.removeFirst(logMessages.count - 200)
        }
    }
    
    private func logNetworkInfo() {
        // Get device IP addresses
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            addLog("Could not get network interfaces")
            return
        }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let address = String(cString: hostname)
                if !address.isEmpty && address != "127.0.0.1" {
                    addresses.append("\(name): \(address)")
                }
            }
        }
        
        if addresses.isEmpty {
            addLog("No network addresses found")
        } else {
            for addr in addresses {
                addLog("Network: \(addr)")
            }
        }
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(Double(sampleRate))
            try session.setPreferredIOBufferDuration(0.005)  // 5ms
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Actions
    
    func startAdvertising() {
        connectionState = .advertising
        addLog("Starting receiver services...")
        
        // NOTE: Bonjour advertising disabled - requires multicast entitlement from Apple
        // The Mac app will connect directly via IP address instead
        addLog("Bonjour disabled (needs Apple approval)")
        
        // Log network info again
        logNetworkInfo()
        
        // Start control server
        addLog("Starting TCP control server on port 19621...")
        controlServer = ControlChannelServer(
            port: 19621,
            onHello: { [weak self] hello in
                Task { @MainActor in
                    self?.handleHello(hello)
                }
            },
            onFormatRequest: { [weak self] request in
                Task { @MainActor in
                    self?.handleFormatRequest(request)
                }
            },
            onDisconnect: { [weak self] reason in
                Task { @MainActor in
                    self?.handleDisconnect(reason: reason)
                }
            }
        )
        controlServer?.start()
        addLog("TCP control server started")
        
        // Start UDP receiver
        addLog("Starting UDP audio receiver on port 19620...")
        audioReceiver = AudioReceiver(port: 19620)
        audioReceiver?.start()
        addLog("UDP audio receiver started")
        
        // Start audio player
        audioPlayer = AudioPlayer(
            sampleRate: Double(sampleRate),
            channels: Int(channels),
            jitterBufferMs: latencyMode.jitterBufferMs
        )
        audioPlayer?.setAudioSource(audioReceiver!)
        
        // Start stats timer
        startStatsTimer()
    }
    
    func stopAdvertising() {
        stopStatsTimer()
        
        audioPlayer?.stop()
        audioPlayer = nil
        
        audioReceiver?.stop()
        audioReceiver = nil
        
        controlServer?.stop()
        controlServer = nil
        
        // Bonjour disabled
        // bonjourAdvertiser?.stopAdvertising()
        // bonjourAdvertiser = nil
        
        connectionState = .idle
        isReceiving = false
        resetStats()
    }
    
    func setLatencyMode(_ mode: LatencyMode) {
        latencyMode = mode
        audioPlayer?.setJitterBufferTarget(mode.jitterBufferMs)
    }
    
    // MARK: - Handlers
    
    private func handleHello(_ hello: HelloMessage) {
        addLog("Received HELLO from: \(hello.deviceName)")
        addLog("Format: \(hello.sampleRate)Hz, \(hello.channels)ch")
        connectionState = .connected(hello.deviceName)
        sampleRate = hello.sampleRate
        channels = hello.channels
        
        // Update audio player
        audioPlayer?.updateFormat(
            sampleRate: Double(sampleRate),
            channels: Int(channels)
        )
        
        // Start playback
        audioPlayer?.start()
        isReceiving = true
        
        // Send ack
        let ack = HelloAckMessage(
            deviceName: UIDevice.current.name,
            accepted: true,
            rejectionReason: nil
        )
        controlServer?.sendHelloAck(ack)
    }
    
    private func handleFormatRequest(_ request: FormatRequest) {
        sampleRate = request.sampleRate
        channels = request.channels
        
        audioPlayer?.updateFormat(
            sampleRate: Double(sampleRate),
            channels: Int(channels)
        )
        
        let ack = FormatAckMessage(
            accepted: true,
            sampleRate: sampleRate,
            channels: channels
        )
        controlServer?.sendFormatAck(ack)
    }
    
    private func handleDisconnect(reason: String) {
        connectionState = .advertising
        isReceiving = false
        audioPlayer?.stop()
    }
    
    // MARK: - Stats
    
    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStats()
            }
        }
    }
    
    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    private func updateStats() {
        guard let receiver = audioReceiver else { return }
        
        let stats = receiver.getStats()
        packetsReceived = stats.packetsReceived
        packetsLost = stats.packetsLost
        packetsDropped = stats.packetsDropped
        jitterMs = stats.jitterMs
        
        if let player = audioPlayer {
            bufferLevelMs = player.getBufferLevelMs()
            underrunCount = player.getUnderrunCount()
        }
        
        let total = packetsReceived + packetsLost
        lossPercentage = total > 0 ? Double(packetsLost) / Double(total) * 100.0 : 0
        
        // Send stats to Mac
        let statsMsg = StatsMessage(
            packetsReceived: packetsReceived,
            packetsLost: packetsLost,
            jitterMs: jitterMs,
            bufferLevelMs: bufferLevelMs,
            lossPercentage: lossPercentage
        )
        controlServer?.sendStats(statsMsg)
    }
    
    private func resetStats() {
        packetsReceived = 0
        packetsLost = 0
        packetsDropped = 0
        underrunCount = 0
        jitterMs = 0
        bufferLevelMs = 0
        lossPercentage = 0
    }
}

