//
//  UDPAudioReceiver.swift
//  CymaxPhoneOutMenubar
//
//  Receives UDP audio packets from the driver on localhost
//

import Foundation

/// Received audio packet from driver
struct AudioPacket {
    let sequence: UInt32
    let timestamp: UInt32
    let sampleRate: UInt32
    let channels: UInt16
    let frameCount: UInt16
    let audioData: Data
    
    /// Parse from raw UDP data
    static func parse(from data: Data) -> AudioPacket? {
        // Header: seq(4) + timestamp(4) + sampleRate(4) + channels(2) + frameCount(2) + format(2) + reserved(10) = 28 bytes
        guard data.count >= 28 else { return nil }
        
        let sequence = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let timestamp = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let sampleRate = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
        let channels = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt16.self) }
        let frameCount = data.withUnsafeBytes { $0.load(fromByteOffset: 14, as: UInt16.self) }
        // format at offset 16, reserved at 18-27
        
        let audioData = data.subdata(in: 28..<data.count)
        
        return AudioPacket(
            sequence: sequence,
            timestamp: timestamp,
            sampleRate: sampleRate,
            channels: channels,
            frameCount: frameCount,
            audioData: audioData
        )
    }
    
    /// Convert to binary data for WebSocket transmission (simplified header)
    func toWebSocketData() -> Data {
        var data = Data()
        
        // Write simplified header (16 bytes for web)
        var seq = sequence
        var ts = timestamp
        var sr = sampleRate
        var ch = channels
        var fc = frameCount
        
        data.append(Data(bytes: &seq, count: 4))
        data.append(Data(bytes: &ts, count: 4))
        data.append(Data(bytes: &sr, count: 4))
        data.append(Data(bytes: &ch, count: 2))
        data.append(Data(bytes: &fc, count: 2))
        
        // Append audio data
        data.append(audioData)
        
        return data
    }
}

/// Callback for received audio packets
typealias AudioPacketHandler = (AudioPacket) -> Void

/// UDP Audio Receiver - listens on localhost for audio from driver
/// Uses BSD sockets for reliable UDP reception
class UDPAudioReceiver {
    private var socketFD: Int32 = -1
    private let port: UInt16
    private var receiveThread: Thread?
    private var isRunning = false
    
    private var packetHandler: AudioPacketHandler?
    
    // Stats
    private(set) var packetsReceived: Int = 0
    
    init(port: UInt16 = 19620) {
        self.port = port
    }
    
    deinit {
        stop()
    }
    
    /// Set the callback for received audio packets
    func setPacketHandler(_ handler: @escaping AudioPacketHandler) {
        self.packetHandler = handler
    }
    
    /// Start listening for UDP packets on localhost
    func start() {
        guard !isRunning else { return }
        
        // Create UDP socket
        socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else {
            print("UDPAudioReceiver: Failed to create socket")
            return
        }
        
        // Allow address reuse
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        
        // Bind to localhost:port
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult == 0 else {
            print("UDPAudioReceiver: Failed to bind to port \(port), error: \(errno)")
            close(socketFD)
            socketFD = -1
            return
        }
        
        print("UDPAudioReceiver: Listening on localhost:\(port)")
        isRunning = true
        
        // Start receive thread
        receiveThread = Thread { [weak self] in
            self?.receiveLoop()
        }
        receiveThread?.name = "UDPAudioReceiver"
        receiveThread?.start()
    }
    
    /// Stop listening
    func stop() {
        isRunning = false
        
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        
        receiveThread = nil
        packetsReceived = 0
        print("UDPAudioReceiver: Stopped")
    }
    
    private func receiveLoop() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        
        while isRunning && socketFD >= 0 {
            let bytesRead = recv(socketFD, &buffer, buffer.count, 0)
            
            if bytesRead > 0 {
                packetsReceived += 1
                
                let data = Data(bytes: buffer, count: bytesRead)
                
                if let packet = AudioPacket.parse(from: data) {
                    // Log first packet
                    if packetsReceived == 1 {
                        print("UDPAudioReceiver: First packet! seq=\(packet.sequence), rate=\(packet.sampleRate), frames=\(packet.frameCount)")
                    }
                    
                    packetHandler?(packet)
                }
            } else if bytesRead < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                if isRunning {
                    print("UDPAudioReceiver: recv error: \(errno)")
                }
                break
            }
        }
    }
}
