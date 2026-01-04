//
//  StreamFormat.swift
//  CymaxAudioProtocol
//
//  Audio stream format definitions for Cymax Phone Audio MVP
//

import Foundation

/// Supported audio sample formats
public enum CymaxSampleFormat: UInt16, Codable, CaseIterable, Sendable {
    /// 32-bit floating point (-1.0 to 1.0)
    case float32 = 1
    /// 16-bit signed integer
    case int16 = 2
    
    /// Bytes per sample for this format
    public var bytesPerSample: Int {
        switch self {
        case .float32: return 4
        case .int16: return 2
        }
    }
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .float32: return "Float32"
        case .int16: return "Int16"
        }
    }
}

/// Audio stream format configuration
public struct CymaxStreamFormat: Codable, Equatable, Sendable {
    /// Sample rate in Hz (e.g., 44100, 48000)
    public let sampleRate: UInt32
    
    /// Number of audio channels (1 = mono, 2 = stereo)
    public let channels: UInt16
    
    /// Sample format
    public let format: CymaxSampleFormat
    
    /// Frames per UDP packet
    public let framesPerPacket: UInt16
    
    public init(
        sampleRate: UInt32 = 48000,
        channels: UInt16 = 2,
        format: CymaxSampleFormat = .float32,
        framesPerPacket: UInt16 = CymaxNetwork.defaultFramesPerPacket
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.format = format
        self.framesPerPacket = framesPerPacket
    }
    
    /// Bytes per frame (all channels)
    public var bytesPerFrame: Int {
        return Int(channels) * format.bytesPerSample
    }
    
    /// Bytes per packet (audio data only, excluding header)
    public var bytesPerPacket: Int {
        return Int(framesPerPacket) * bytesPerFrame
    }
    
    /// Duration of one packet in seconds
    public var packetDuration: Double {
        return Double(framesPerPacket) / Double(sampleRate)
    }
    
    /// Duration of one packet in milliseconds
    public var packetDurationMs: Double {
        return packetDuration * 1000.0
    }
}

/// Supported sample rates
public enum CymaxSupportedSampleRate: UInt32, CaseIterable, Sendable {
    case rate44100 = 44100
    case rate48000 = 48000
    
    public var description: String {
        return "\(self.rawValue) Hz"
    }
}

/// Buffer size options (in frames)
public enum CymaxBufferSize: UInt32, CaseIterable, Sendable {
    case frames64 = 64
    case frames128 = 128
    case frames256 = 256
    case frames512 = 512
    
    /// Duration in milliseconds at 48kHz
    public var durationMs48k: Double {
        return Double(self.rawValue) / 48.0
    }
    
    /// Duration in milliseconds at 44.1kHz
    public var durationMs44k: Double {
        return Double(self.rawValue) / 44.1
    }
    
    public var description: String {
        return "\(self.rawValue) frames (~\(String(format: "%.1f", durationMs48k))ms)"
    }
}

