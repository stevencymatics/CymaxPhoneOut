//
//  ControlMessage.swift
//  CymaxAudioProtocol
//
//  TCP control channel messages for Cymax Phone Audio MVP
//
//  The control channel is used for:
//  - Initial handshake and format negotiation
//  - Runtime statistics reporting
//  - Graceful disconnect
//
//  IMPORTANT: The control channel (TCP) is ONLY used by the menubar app
//  and iOS app. The AudioServerPlugIn does NOT use TCP at all.
//

import Foundation

/// Control message types
public enum CymaxControlMessageType: UInt8, Codable, Sendable {
    /// Initial hello from Mac to iOS
    case hello = 1
    /// Hello acknowledgment from iOS to Mac
    case helloAck = 2
    /// Format negotiation request
    case formatRequest = 3
    /// Format acknowledgment
    case formatAck = 4
    /// Periodic statistics update
    case stats = 5
    /// Graceful disconnect notification
    case disconnect = 6
    /// Ping for connection keepalive
    case ping = 7
    /// Pong response to ping
    case pong = 8
}

/// Base control message envelope
public struct CymaxControlMessage: Codable, Sendable {
    /// Message type
    public let type: CymaxControlMessageType
    
    /// Message payload (JSON-encoded specific message)
    public let payload: Data
    
    /// Timestamp when message was created (Unix time ms)
    public let timestamp: UInt64
    
    public init(type: CymaxControlMessageType, payload: Data) {
        self.type = type
        self.payload = payload
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
    }
    
    /// Create a control message with a Codable payload
    public static func create<T: Codable>(_ type: CymaxControlMessageType, payload: T) throws -> CymaxControlMessage {
        let data = try JSONEncoder().encode(payload)
        return CymaxControlMessage(type: type, payload: data)
    }
    
    /// Decode the payload to a specific type
    public func decodePayload<T: Codable>(_ type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: payload)
    }
}

// MARK: - Specific Message Payloads

/// Hello message - sent by Mac menubar app to iOS when connecting
public struct CymaxHelloMessage: Codable, Sendable {
    /// Mac's device name
    public let deviceName: String
    
    /// Protocol version
    public let protocolVersion: String
    
    /// Preferred stream format
    public let preferredFormat: CymaxStreamFormat
    
    /// UDP port the Mac will send audio to
    public let audioPort: UInt16
    
    public init(deviceName: String, preferredFormat: CymaxStreamFormat, audioPort: UInt16 = CymaxBonjour.audioUDPPort) {
        self.deviceName = deviceName
        self.protocolVersion = CymaxBonjour.protocolVersion
        self.preferredFormat = preferredFormat
        self.audioPort = audioPort
    }
}

/// Hello acknowledgment - sent by iOS in response to hello
public struct CymaxHelloAckMessage: Codable, Sendable {
    /// iOS device name
    public let deviceName: String
    
    /// Protocol version
    public let protocolVersion: String
    
    /// Whether the iOS device accepts the connection
    public let accepted: Bool
    
    /// Reason for rejection (if not accepted)
    public let rejectionReason: String?
    
    /// Supported sample rates
    public let supportedSampleRates: [UInt32]
    
    /// Maximum channels supported
    public let maxChannels: UInt16
    
    public init(
        deviceName: String,
        accepted: Bool,
        rejectionReason: String? = nil,
        supportedSampleRates: [UInt32] = [44100, 48000],
        maxChannels: UInt16 = 2
    ) {
        self.deviceName = deviceName
        self.protocolVersion = CymaxBonjour.protocolVersion
        self.accepted = accepted
        self.rejectionReason = rejectionReason
        self.supportedSampleRates = supportedSampleRates
        self.maxChannels = maxChannels
    }
}

/// Format request - Mac requesting a specific format
public struct CymaxFormatRequestMessage: Codable, Sendable {
    /// Requested stream format
    public let format: CymaxStreamFormat
    
    public init(format: CymaxStreamFormat) {
        self.format = format
    }
}

/// Format acknowledgment - iOS confirming or countering format
public struct CymaxFormatAckMessage: Codable, Sendable {
    /// Whether the format was accepted
    public let accepted: Bool
    
    /// Actual format to use (may differ from request)
    public let format: CymaxStreamFormat
    
    /// Target jitter buffer size in milliseconds
    public let jitterBufferMs: UInt16
    
    public init(accepted: Bool, format: CymaxStreamFormat, jitterBufferMs: UInt16 = 15) {
        self.accepted = accepted
        self.format = format
        self.jitterBufferMs = jitterBufferMs
    }
}

/// Statistics message - periodic stats from iOS to Mac
public struct CymaxStatsMessage: Codable, Sendable {
    /// Packet statistics
    public let packetsReceived: UInt64
    public let packetsLost: UInt64
    public let packetsDropped: UInt64
    
    /// Jitter estimate in milliseconds
    public let jitterMs: Double
    
    /// Current buffer level in milliseconds
    public let bufferLevelMs: Double
    
    /// Audio output latency in milliseconds
    public let outputLatencyMs: Double
    
    /// Packet loss percentage
    public let lossPercentage: Double
    
    public init(
        packetsReceived: UInt64,
        packetsLost: UInt64,
        packetsDropped: UInt64,
        jitterMs: Double,
        bufferLevelMs: Double,
        outputLatencyMs: Double
    ) {
        self.packetsReceived = packetsReceived
        self.packetsLost = packetsLost
        self.packetsDropped = packetsDropped
        self.jitterMs = jitterMs
        self.bufferLevelMs = bufferLevelMs
        self.outputLatencyMs = outputLatencyMs
        
        let total = packetsReceived + packetsLost
        self.lossPercentage = total > 0 ? Double(packetsLost) / Double(total) * 100.0 : 0
    }
}

/// Disconnect message - graceful disconnect notification
public struct CymaxDisconnectMessage: Codable, Sendable {
    /// Reason for disconnect
    public let reason: String
    
    public init(reason: String) {
        self.reason = reason
    }
}

// MARK: - Message Framing

/// Wire format for control messages over TCP
/// Each message is framed as: [4-byte length][JSON payload]
public enum CymaxControlFraming {
    /// Maximum message size (64KB should be plenty)
    public static let maxMessageSize = 65536
    
    /// Frame a message for transmission
    public static func frame(_ message: CymaxControlMessage) throws -> Data {
        let json = try JSONEncoder().encode(message)
        guard json.count <= maxMessageSize else {
            throw CymaxControlError.messageTooLarge
        }
        
        var data = Data(capacity: 4 + json.count)
        var length = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(json)
        return data
    }
    
    /// Parse message length from header
    public static func parseLength(_ data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return data.withUnsafeBytes { buffer in
            buffer.load(as: UInt32.self).littleEndian
        }
    }
}

/// Control channel errors
public enum CymaxControlError: Error, LocalizedError {
    case messageTooLarge
    case invalidMessage
    case connectionClosed
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .messageTooLarge: return "Control message too large"
        case .invalidMessage: return "Invalid control message"
        case .connectionClosed: return "Connection closed"
        case .timeout: return "Connection timeout"
        }
    }
}



