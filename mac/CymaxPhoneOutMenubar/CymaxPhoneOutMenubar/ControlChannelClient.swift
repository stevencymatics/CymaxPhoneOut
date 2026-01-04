//
//  ControlChannelClient.swift
//  CymaxPhoneOutMenubar
//
//  TCP control channel client for communicating with iOS receiver
//
//  IMPORTANT: This is the ONLY component that uses TCP sockets.
//  The AudioServerPlugIn does NOT use TCP - only UDP.
//

import Foundation
import Network

/// TCP control channel client for format negotiation and stats
class ControlChannelClient {
    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private let onStats: (ReceiverStats) -> Void
    private let onDisconnect: (String) -> Void
    
    private var isConnected = false
    private var receiveBuffer = Data()
    
    /// Connection timeout in seconds
    static let connectionTimeout: TimeInterval = 5.0
    
    init(host: String, port: UInt16, onStats: @escaping (ReceiverStats) -> Void, onDisconnect: @escaping (String) -> Void) {
        self.host = host
        self.port = port
        self.onStats = onStats
        self.onDisconnect = onDisconnect
    }
    
    deinit {
        disconnect()
    }
    
    func connect() async throws {
        // Create the connection
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        connection = NWConnection(to: endpoint, using: .tcp)
        
        // Use a continuation with manual timeout handling
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            let lock = NSLock()
            
            // Set up timeout timer
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                lock.lock()
                defer { lock.unlock() }
                
                if !hasResumed {
                    hasResumed = true
                    self?.connection?.cancel()
                    self?.connection = nil
                    self?.isConnected = false
                    continuation.resume(throwing: ControlChannelError.connectionTimeout)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: timeoutWorkItem)
            
            connection?.stateUpdateHandler = { [weak self] state in
                lock.lock()
                defer { lock.unlock() }
                
                guard !hasResumed else { return }
                
                switch state {
                case .ready:
                    hasResumed = true
                    timeoutWorkItem.cancel()
                    self?.isConnected = true
                    self?.startReceiving()
                    continuation.resume()
                    
                case .failed(let error):
                    hasResumed = true
                    timeoutWorkItem.cancel()
                    self?.isConnected = false
                    continuation.resume(throwing: error)
                    
                case .cancelled:
                    // Only resume if we haven't already (timeout might have cancelled us)
                    if !hasResumed {
                        hasResumed = true
                        timeoutWorkItem.cancel()
                        self?.isConnected = false
                        continuation.resume(throwing: ControlChannelError.connectionCancelled)
                    }
                    
                case .waiting(let error):
                    // Connection is waiting (e.g., no route to host)
                    print("Connection waiting: \(error)")
                    
                default:
                    break
                }
            }
            
            connection?.start(queue: .main)
        }
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    func sendHello(deviceName: String, sampleRate: UInt32, channels: UInt16) async throws {
        let hello = HelloMessage(
            deviceName: deviceName,
            sampleRate: sampleRate,
            channels: channels
        )
        
        try await send(message: .hello(hello))
    }
    
    func sendFormatRequest(sampleRate: UInt32, channels: UInt16) async throws {
        let request = FormatRequest(
            sampleRate: sampleRate,
            channels: channels
        )
        
        try await send(message: .formatRequest(request))
    }
    
    func sendDisconnect(reason: String) async throws {
        try await send(message: .disconnect(DisconnectMessage(reason: reason)))
    }
    
    // MARK: - Private
    
    private func send(message: ControlMessage) async throws {
        guard let connection = connection, isConnected else {
            throw ControlChannelError.notConnected
        }
        
        let data = try encodeMessage(message)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func startReceiving() {
        receiveLoop()
    }
    
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.onDisconnect("Receive error: \(error.localizedDescription)")
                return
            }
            
            if let data = data {
                self.receiveBuffer.append(data)
                self.processReceiveBuffer()
            }
            
            if isComplete {
                self.onDisconnect("Connection closed by peer")
                return
            }
            
            // Continue receiving
            self.receiveLoop()
        }
    }
    
    private func processReceiveBuffer() {
        // Message format: [4-byte length][JSON payload]
        while receiveBuffer.count >= 4 {
            // Safely read length as little-endian UInt32 using Array
            let lengthBytes = Array(receiveBuffer.prefix(4))
            guard lengthBytes.count == 4 else {
                print("Failed to read length bytes")
                return
            }
            
            let length = UInt32(lengthBytes[0]) |
                        (UInt32(lengthBytes[1]) << 8) |
                        (UInt32(lengthBytes[2]) << 16) |
                        (UInt32(lengthBytes[3]) << 24)
            
            // Sanity check - reject unreasonably large messages (> 1MB)
            guard length < 1_000_000 else {
                print("Received invalid message length: \(length), clearing buffer")
                receiveBuffer.removeAll()
                return
            }
            
            let totalMessageSize = 4 + Int(length)
            guard receiveBuffer.count >= totalMessageSize else {
                break  // Wait for more data
            }
            
            // Extract message data safely
            let messageData = Data(receiveBuffer.dropFirst(4).prefix(Int(length)))
            receiveBuffer.removeFirst(totalMessageSize)
            
            do {
                let message = try decodeMessage(messageData)
                handleMessage(message)
            } catch {
                print("Failed to decode message: \(error)")
            }
        }
    }
    
    private func handleMessage(_ message: ControlMessage) {
        switch message {
        case .helloAck(let ack):
            print("Received hello ack from: \(ack.deviceName)")
            
        case .formatAck(let ack):
            print("Format accepted: \(ack.accepted)")
            
        case .stats(let stats):
            let receiverStats = ReceiverStats(
                packetsReceived: stats.packetsReceived,
                packetsLost: stats.packetsLost,
                jitterMs: stats.jitterMs,
                bufferLevelMs: stats.bufferLevelMs,
                lossPercentage: stats.lossPercentage
            )
            onStats(receiverStats)
            
        case .disconnect(let msg):
            onDisconnect(msg.reason)
            
        case .ping:
            Task {
                try? await send(message: .pong)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Message Encoding/Decoding
    
    private func encodeMessage(_ message: ControlMessage) throws -> Data {
        let json = try JSONEncoder().encode(message)
        
        var data = Data(capacity: 4 + json.count)
        var length = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(json)
        
        return data
    }
    
    private func decodeMessage(_ data: Data) throws -> ControlMessage {
        return try JSONDecoder().decode(ControlMessage.self, from: data)
    }
}

// MARK: - Control Messages

enum ControlMessage: Codable {
    case hello(HelloMessage)
    case helloAck(HelloAckMessage)
    case formatRequest(FormatRequest)
    case formatAck(FormatAckMessage)
    case stats(StatsMessage)
    case disconnect(DisconnectMessage)
    case ping
    case pong
}

struct HelloMessage: Codable {
    let deviceName: String
    let sampleRate: UInt32
    let channels: UInt16
}

struct HelloAckMessage: Codable {
    let deviceName: String
    let accepted: Bool
    let rejectionReason: String?
}

struct FormatRequest: Codable {
    let sampleRate: UInt32
    let channels: UInt16
}

struct FormatAckMessage: Codable {
    let accepted: Bool
    let sampleRate: UInt32
    let channels: UInt16
}

struct StatsMessage: Codable {
    let packetsReceived: UInt64
    let packetsLost: UInt64
    let jitterMs: Double
    let bufferLevelMs: Double
    let lossPercentage: Double
}

struct DisconnectMessage: Codable {
    let reason: String
}

// MARK: - Errors

enum ControlChannelError: Error, LocalizedError {
    case notConnected
    case encodingFailed
    case decodingFailed
    case connectionTimeout
    case connectionCancelled
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected"
        case .encodingFailed: return "Failed to encode message"
        case .decodingFailed: return "Failed to decode message"
        case .connectionTimeout: return "Connection timed out (5s) - check IP address"
        case .connectionCancelled: return "Connection cancelled"
        }
    }
}

