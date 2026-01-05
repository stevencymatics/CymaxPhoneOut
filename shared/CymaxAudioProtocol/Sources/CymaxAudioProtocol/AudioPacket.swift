//
//  AudioPacket.swift
//  CymaxAudioProtocol
//
//  UDP audio packet structures for Cymax Phone Audio MVP
//
//  Packet Layout (24-byte header + audio data):
//  ┌──────────────────────────────────────────────────────────────┐
//  │ Offset │ Size │ Field       │ Description                    │
//  ├──────────────────────────────────────────────────────────────┤
//  │ 0      │ 4    │ magic       │ 'CMAX' (0x43 0x4D 0x41 0x58)   │
//  │ 4      │ 4    │ sequence    │ Packet sequence number          │
//  │ 8      │ 8    │ timestamp   │ Host time in nanoseconds        │
//  │ 16     │ 4    │ sampleRate  │ Sample rate in Hz               │
//  │ 20     │ 2    │ channels    │ Number of channels              │
//  │ 22     │ 2    │ frameCount  │ Number of frames in packet      │
//  │ 24     │ 2    │ format      │ Sample format (1=f32, 2=i16)    │
//  │ 26     │ 2    │ flags       │ Reserved flags                  │
//  │ 28     │ N    │ audioData   │ Interleaved audio samples       │
//  └──────────────────────────────────────────────────────────────┘
//

import Foundation

/// Magic bytes identifying a Cymax audio packet: "CMAX"
public let CymaxAudioPacketMagic: UInt32 = 0x584D4143  // 'XMAC' in little-endian = 'CMAX'

/// Audio packet header - 28 bytes total
/// This struct is designed for direct memory mapping from network bytes
@frozen
public struct CymaxAudioPacketHeader: Sendable {
    /// Magic number for packet validation ('CMAX')
    public var magic: UInt32
    
    /// Monotonically increasing sequence number (wraps at UInt32.max)
    public var sequence: UInt32
    
    /// Timestamp in nanoseconds (mach_absolute_time converted)
    public var timestamp: UInt64
    
    /// Sample rate in Hz
    public var sampleRate: UInt32
    
    /// Number of audio channels
    public var channels: UInt16
    
    /// Number of audio frames in this packet
    public var frameCount: UInt16
    
    /// Sample format (CymaxSampleFormat raw value)
    public var format: UInt16
    
    /// Reserved flags for future use
    public var flags: UInt16
    
    /// Header size in bytes
    public static let size = 28
    
    public init(
        sequence: UInt32,
        timestamp: UInt64,
        sampleRate: UInt32,
        channels: UInt16,
        frameCount: UInt16,
        format: CymaxSampleFormat,
        flags: UInt16 = 0
    ) {
        self.magic = CymaxAudioPacketMagic
        self.sequence = sequence
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.channels = channels
        self.frameCount = frameCount
        self.format = format.rawValue
        self.flags = flags
    }
    
    /// Validate the magic number
    public var isValid: Bool {
        return magic == CymaxAudioPacketMagic
    }
    
    /// Get the sample format enum
    public var sampleFormat: CymaxSampleFormat? {
        return CymaxSampleFormat(rawValue: format)
    }
    
    /// Calculate expected audio data size in bytes
    public var audioDataSize: Int {
        guard let fmt = sampleFormat else { return 0 }
        return Int(frameCount) * Int(channels) * fmt.bytesPerSample
    }
    
    /// Total packet size including header
    public var totalPacketSize: Int {
        return Self.size + audioDataSize
    }
}

// MARK: - Byte Serialization

extension CymaxAudioPacketHeader {
    /// Serialize header to bytes (little-endian)
    public func toBytes() -> Data {
        var data = Data(capacity: Self.size)
        
        // Write each field in little-endian
        withUnsafeBytes(of: magic.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sequence.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: timestamp.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRate.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: channels.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: frameCount.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: format.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: flags.littleEndian) { data.append(contentsOf: $0) }
        
        return data
    }
    
    /// Parse header from bytes (little-endian)
    public static func fromBytes(_ data: Data) -> CymaxAudioPacketHeader? {
        guard data.count >= Self.size else { return nil }
        
        return data.withUnsafeBytes { buffer -> CymaxAudioPacketHeader? in
            let ptr = buffer.baseAddress!
            
            let magic = ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian
            guard magic == CymaxAudioPacketMagic else { return nil }
            
            let sequence = ptr.load(fromByteOffset: 4, as: UInt32.self).littleEndian
            let timestamp = ptr.load(fromByteOffset: 8, as: UInt64.self).littleEndian
            let sampleRate = ptr.load(fromByteOffset: 16, as: UInt32.self).littleEndian
            let channels = ptr.load(fromByteOffset: 20, as: UInt16.self).littleEndian
            let frameCount = ptr.load(fromByteOffset: 22, as: UInt16.self).littleEndian
            let format = ptr.load(fromByteOffset: 24, as: UInt16.self).littleEndian
            let flags = ptr.load(fromByteOffset: 26, as: UInt16.self).littleEndian
            
            guard let sampleFormat = CymaxSampleFormat(rawValue: format) else { return nil }
            
            return CymaxAudioPacketHeader(
                sequence: sequence,
                timestamp: timestamp,
                sampleRate: sampleRate,
                channels: channels,
                frameCount: frameCount,
                format: sampleFormat,
                flags: flags
            )
        }
    }
}

// MARK: - Full Packet with Audio Data

/// Complete audio packet with header and audio data
public struct CymaxAudioPacket: Sendable {
    /// Packet header
    public let header: CymaxAudioPacketHeader
    
    /// Raw audio data (interleaved samples)
    public let audioData: Data
    
    public init(header: CymaxAudioPacketHeader, audioData: Data) {
        self.header = header
        self.audioData = audioData
    }
    
    /// Serialize entire packet to bytes
    public func toBytes() -> Data {
        var data = header.toBytes()
        data.append(audioData)
        return data
    }
    
    /// Parse packet from bytes
    public static func fromBytes(_ data: Data) -> CymaxAudioPacket? {
        guard let header = CymaxAudioPacketHeader.fromBytes(data) else { return nil }
        
        let audioStart = CymaxAudioPacketHeader.size
        let expectedSize = audioStart + header.audioDataSize
        
        guard data.count >= expectedSize else { return nil }
        
        let audioData = data.subdata(in: audioStart..<expectedSize)
        return CymaxAudioPacket(header: header, audioData: audioData)
    }
}

// MARK: - Packet Statistics

/// Statistics for packet reception (used by iOS receiver)
public struct CymaxPacketStats: Sendable {
    /// Total packets received
    public var packetsReceived: UInt64 = 0
    
    /// Packets lost (detected via sequence gaps)
    public var packetsLost: UInt64 = 0
    
    /// Packets dropped due to jitter buffer overflow
    public var packetsDropped: UInt64 = 0
    
    /// Packets arrived out of order
    public var packetsReordered: UInt64 = 0
    
    /// Packets arrived too late for playback
    public var packetsTooLate: UInt64 = 0
    
    /// Last received sequence number
    public var lastSequence: UInt32 = 0
    
    /// Current jitter estimate in milliseconds
    public var jitterMs: Double = 0
    
    /// Packet loss percentage
    public var lossPercentage: Double {
        let total = packetsReceived + packetsLost
        guard total > 0 else { return 0 }
        return Double(packetsLost) / Double(total) * 100.0
    }
    
    public init() {}
}


