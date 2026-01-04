//
//  JitterBuffer.swift
//  CymaxPhoneReceiver
//
//  Simple circular sample buffer for audio streaming
//
//  This implementation uses a continuous sample buffer instead of
//  discrete packets to handle variable pull sizes from the audio engine.
//

import Foundation

/// Simple circular buffer for audio samples
class JitterBuffer {
    // Configuration
    private let sampleRate: Double
    private let channels: Int
    
    // Circular buffer for samples
    private var buffer: [Float]
    private var writePos: Int = 0
    private var readPos: Int = 0
    private var samplesInBuffer: Int = 0
    private let bufferCapacity: Int
    
    private let lock = NSLock()
    
    // State
    private var hasReceivedAnyPacket = false
    private var isBuffering = true
    private let minBufferSamples: Int  // Samples to buffer before starting
    
    // Crossfade for smooth transitions
    private var fadeInRemaining: Int = 0
    private let fadeInSamples: Int = 2048  // ~21ms fade-in at 48kHz stereo
    
    // Stats
    private(set) var packetsReceived: Int = 0
    private(set) var packetsPlayed: Int = 0
    private(set) var packetsDroppedLate: Int = 0
    private(set) var packetsDroppedOverflow: Int = 0
    
    init(targetDelayMs: Double, maxDelayMs: Double, sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        
        // Buffer CAPACITY: Always large (2 seconds) to handle DAW bursts
        // This doesn't add latency - it's just max storage
        self.bufferCapacity = Int(sampleRate) * 2 * channels  // 2 seconds capacity
        self.buffer = [Float](repeating: 0, count: bufferCapacity)
        
        // Pre-buffer: How much we wait before starting (THIS determines latency)
        self.minBufferSamples = Int(targetDelayMs / 1000.0 * sampleRate) * channels
        
        print("JitterBuffer: capacity=2s, prebuffer=\(Int(targetDelayMs))ms")
    }
    
    func setTargetDelay(_ delayMs: Double) {
        // Not used in this simple implementation
    }
    
    /// Add samples to the buffer
    func push(sequence: UInt32, timestamp: UInt64, samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        
        packetsReceived += 1
        hasReceivedAnyPacket = true
        
        // Log first packet
        if packetsReceived == 1 {
            print("JitterBuffer: First packet seq=\(sequence), \(samples.count) samples")
        }
        
        // Check if we have room
        let spaceAvailable = bufferCapacity - samplesInBuffer
        if samples.count > spaceAvailable {
            // Buffer overflow - drop oldest samples to make room
            let toDrop = samples.count - spaceAvailable
            readPos = (readPos + toDrop) % bufferCapacity
            samplesInBuffer -= toDrop
            packetsDroppedOverflow += 1
        }
        
        // Write samples to circular buffer
        for sample in samples {
            buffer[writePos] = sample
            writePos = (writePos + 1) % bufferCapacity
        }
        samplesInBuffer += samples.count
    }
    
    /// Get samples for playback
    func pull(frameCount: Int) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        
        let sampleCount = frameCount * channels
        
        // Don't start until we've received data
        if !hasReceivedAnyPacket {
            return [Float](repeating: 0, count: sampleCount)
        }
        
        // Determine rebuffer threshold
        // First start: use full prebuffer for good initial experience
        // After underrun: use quick rebuffer (50ms) for fast recovery
        let hasPlayedBefore = packetsPlayed > 0
        let rebufferThreshold = hasPlayedBefore ? Int(0.050 * sampleRate) * channels : minBufferSamples
        
        // Wait for buffer to fill
        if isBuffering {
            if samplesInBuffer >= rebufferThreshold {
                isBuffering = false
                fadeInRemaining = fadeInSamples  // Start fade-in to avoid pop
                let thresholdMs = hasPlayedBefore ? 50 : Int(Double(minBufferSamples) / sampleRate / Double(channels) * 1000)
                print("JitterBuffer: Resuming with \(samplesInBuffer) samples (\(thresholdMs)ms threshold)")
            } else {
                return [Float](repeating: 0, count: sampleCount)
            }
        }
        
        // If buffer runs out, go to rebuffer mode
        if samplesInBuffer < sampleCount {
            isBuffering = true
            return [Float](repeating: 0, count: sampleCount)
        }
        
        // Read samples from buffer
        var output = [Float](repeating: 0, count: sampleCount)
        
        for i in 0..<sampleCount {
            output[i] = buffer[readPos]
            readPos = (readPos + 1) % bufferCapacity
        }
        samplesInBuffer -= sampleCount
        packetsPlayed += 1
        
        // Apply fade-in if we just resumed from rebuffering
        if fadeInRemaining > 0 {
            let samplesToFade = min(fadeInRemaining, sampleCount)
            for i in 0..<samplesToFade {
                let fadeProgress = Float(fadeInSamples - fadeInRemaining + i) / Float(fadeInSamples)
                output[i] *= fadeProgress
            }
            fadeInRemaining -= samplesToFade
        }
        
        return output
    }
    
    func getBufferLevelMs() -> Double {
        lock.lock()
        defer { lock.unlock() }
        
        let frames = Double(samplesInBuffer) / Double(channels)
        return (frames / sampleRate) * 1000.0
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        writePos = 0
        readPos = 0
        samplesInBuffer = 0
        hasReceivedAnyPacket = false
        isBuffering = true
        fadeInRemaining = 0
        packetsReceived = 0
        packetsPlayed = 0
        packetsDroppedLate = 0
        packetsDroppedOverflow = 0
    }
    
    func getStats() -> (received: Int, played: Int, droppedLate: Int, droppedOverflow: Int, buffered: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (packetsReceived, packetsPlayed, packetsDroppedLate, packetsDroppedOverflow, samplesInBuffer / max(channels, 1))
    }
}

