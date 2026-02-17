//
//  BonjourConstants.swift
//  CymaxAudioProtocol
//
//  Bonjour service discovery constants for Cymax Phone Audio MVP
//

import Foundation

/// Bonjour and network constants for the Cymax Phone Audio system
public enum CymaxBonjour {
    /// Bonjour service type for audio streaming (UDP-based)
    /// Format: _servicename._protocol
    public static let serviceType = "_cymaxaudio._udp."
    
    /// Bonjour service domain (local network)
    public static let serviceDomain = "local."
    
    /// Default service name prefix for iOS receivers
    public static let serviceNamePrefix = "CymaxReceiver"
    
    /// UDP port for audio data packets
    /// Using a high port number to avoid conflicts
    public static let audioUDPPort: UInt16 = 19620
    
    /// TCP port for control channel (format negotiation, stats)
    /// Only used by menubar app and iOS app - NOT by the AudioServerPlugIn
    public static let controlTCPPort: UInt16 = 19621
    
    /// TXT record keys for Bonjour service advertisement
    public enum TXTRecordKey {
        /// Device friendly name
        public static let deviceName = "name"
        /// Protocol version
        public static let protocolVersion = "ver"
        /// Supported sample rates (comma-separated)
        public static let sampleRates = "rates"
        /// Maximum channels supported
        public static let maxChannels = "ch"
    }
    
    /// Current protocol version string
    public static let protocolVersion = "1.0"
}

/// Network configuration constants
public enum CymaxNetwork {
    /// Maximum UDP packet size (avoid fragmentation)
    /// MTU is typically 1500, minus IP header (20) and UDP header (8)
    public static let maxUDPPayload = 1472
    
    /// Audio packet header size in bytes (actual header is 28 bytes)
    /// Struct: magic(4) + seq(4) + timestamp(8) + sampleRate(4) + channels(2) + frameCount(2) + format(2) + flags(2) = 28
    public static let audioHeaderSize = 28
    
    /// Maximum audio payload per packet (bytes)
    public static let maxAudioPayload = maxUDPPayload - audioHeaderSize
    
    /// Default frames per UDP packet
    /// At 48kHz stereo Float32: 128 frames * 2ch * 4 bytes = 1024 bytes
    /// Total packet: 28 header + 1024 audio = 1052 bytes (well under MTU)
    public static let defaultFramesPerPacket: UInt16 = 128
    
    /// Socket receive buffer size (bytes)
    public static let socketReceiveBuffer = 262144  // 256KB
    
    /// Socket send buffer size (bytes)
    public static let socketSendBuffer = 262144  // 256KB
    
    /// Non-blocking socket timeout for select() in microseconds
    public static let selectTimeoutMicros: Int32 = 1000  // 1ms
}

