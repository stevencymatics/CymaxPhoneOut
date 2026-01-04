//
//  AudioReceiver.swift
//  CymaxPhoneReceiver
//
//  UDP audio packet receiver
//

import Foundation
import Network

/// Statistics from the audio receiver
struct AudioReceiverStats {
    var packetsReceived: UInt64 = 0
    var packetsLost: UInt64 = 0
    var packetsDropped: UInt64 = 0
    var packetsReordered: UInt64 = 0
    var jitterMs: Double = 0
    var lastSequence: UInt32 = 0
}

/// Audio packet with header and data
struct ReceivedAudioPacket {
    let sequence: UInt32
    let timestamp: UInt64
    let sampleRate: UInt32
    let channels: UInt16
    let frameCount: UInt16
    let audioData: Data
    
    /// Duration in milliseconds
    var durationMs: Double {
        return Double(frameCount) / Double(sampleRate) * 1000.0
    }
}

/// UDP audio packet receiver
class AudioReceiver {
    private var listener: NWListener?
    private let port: UInt16
    
    // Stats
    private var stats = AudioReceiverStats()
    private let statsLock = NSLock()
    
    // Jitter calculation
    private var lastPacketTime: UInt64 = 0
    private var jitterAccumulator: Double = 0
    private var jitterCount: Int = 0
    
    // Packet callback
    private var onPacket: ((ReceivedAudioPacket) -> Void)?
    
    // Packet header magic
    private let packetMagic: UInt32 = 0x584D4143  // 'CMAX'
    
    init(port: UInt16) {
        self.port = port
    }
    
    deinit {
        stop()
    }
    
    func start() {
        do {
            let parameters = NWParameters.udp
            parameters.serviceClass = .interactiveVideo
            parameters.allowLocalEndpointReuse = true  // Allow reuse of port
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    print("AudioReceiver: Listening on port \(self.port)")
                case .failed(let error):
                    print("AudioReceiver: Failed - \(error)")
                    // Try to restart after a delay if port was in use
                    if case .posix(let code) = error, code == .EADDRINUSE {
                        print("AudioReceiver: Port in use, retrying in 1 second...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                            self.listener?.cancel()
                            self.listener = nil
                            self.start()
                        }
                    }
                case .cancelled:
                    print("AudioReceiver: Cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global(qos: .userInteractive))
            
        } catch {
            print("AudioReceiver: Failed to start - \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    func setPacketHandler(_ handler: @escaping (ReceivedAudioPacket) -> Void) {
        onPacket = handler
    }
    
    func getStats() -> AudioReceiverStats {
        statsLock.lock()
        defer { statsLock.unlock() }
        return stats
    }
    
    // MARK: - Private
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receivePackets(from: connection)
            case .failed(let error):
                print("AudioReceiver: Connection failed - \(error)")
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .userInteractive))
    }
    
    private func receivePackets(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data {
                self.processPacket(data)
            }
            
            if let error = error {
                print("AudioReceiver: Receive error - \(error)")
                return
            }
            
            // Continue receiving
            self.receivePackets(from: connection)
        }
    }
    
    private func processPacket(_ data: Data) {
        // Parse header (28 bytes)
        guard data.count >= 28 else {
            return
        }
        
        let header = data.withUnsafeBytes { buffer -> (UInt32, UInt32, UInt64, UInt32, UInt16, UInt16, UInt16, UInt16)? in
            let ptr = buffer.baseAddress!
            
            let magic = ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian
            guard magic == packetMagic else { return nil }
            
            let sequence = ptr.load(fromByteOffset: 4, as: UInt32.self).littleEndian
            let timestamp = ptr.load(fromByteOffset: 8, as: UInt64.self).littleEndian
            let sampleRate = ptr.load(fromByteOffset: 16, as: UInt32.self).littleEndian
            let channels = ptr.load(fromByteOffset: 20, as: UInt16.self).littleEndian
            let frameCount = ptr.load(fromByteOffset: 22, as: UInt16.self).littleEndian
            let format = ptr.load(fromByteOffset: 24, as: UInt16.self).littleEndian
            let flags = ptr.load(fromByteOffset: 26, as: UInt16.self).littleEndian
            
            return (magic, sequence, timestamp, sampleRate, channels, frameCount, format, flags)
        }
        
        guard let (_, sequence, timestamp, sampleRate, channels, frameCount, _, _) = header else {
            return
        }
        
        // Extract audio data
        let audioData = data.subdata(in: 28..<data.count)
        
        // Update stats
        statsLock.lock()
        
        // Detect packet loss
        if stats.packetsReceived > 0 {
            let expectedSeq = (stats.lastSequence + 1) & 0xFFFFFFFF
            if sequence != expectedSeq {
                if sequence > expectedSeq {
                    stats.packetsLost += UInt64(sequence - expectedSeq)
                } else if sequence < stats.lastSequence {
                    // Reordered packet
                    stats.packetsReordered += 1
                }
            }
        }
        
        stats.lastSequence = sequence
        stats.packetsReceived += 1
        
        // Calculate jitter
        let currentTime = mach_absolute_time()
        if lastPacketTime > 0 {
            let timeDiff = Double(currentTime - lastPacketTime) / 1_000_000.0  // Convert to ms approx
            let expectedInterval = Double(frameCount) / Double(sampleRate) * 1000.0
            let jitter = abs(timeDiff - expectedInterval)
            
            jitterAccumulator += jitter
            jitterCount += 1
            
            if jitterCount >= 100 {
                stats.jitterMs = jitterAccumulator / Double(jitterCount)
                jitterAccumulator = 0
                jitterCount = 0
            }
        }
        lastPacketTime = currentTime
        
        statsLock.unlock()
        
        // Create packet and deliver
        let packet = ReceivedAudioPacket(
            sequence: sequence,
            timestamp: timestamp,
            sampleRate: sampleRate,
            channels: channels,
            frameCount: frameCount,
            audioData: audioData
        )
        
        onPacket?(packet)
    }
}

