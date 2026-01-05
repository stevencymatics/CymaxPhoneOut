//
//  JitterBuffer.swift
//  CymaxPhoneReceiver
//
//  Simple circular buffer for audio streaming with NSLock for thread safety
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
    
    // Thread safety
    private let lock = NSLock()
    
    // State
    private var hasReceivedAnyPacket = false
    private var isBuffering = true
    private let minBufferSamples: Int  // Samples to buffer before starting
    private let quickRebufferSamples: Int  // Quick rebuffer after underrun
    
    // Crossfade for smooth transitions
    private var fadeInRemaining: Int = 0
    private let fadeInSamples: Int = 2048  // ~21ms fade-in at 48kHz stereo
    
    // Stats
    private(set) var packetsReceived: Int = 0
    private(set) var packetsPlayed: Int = 0
    private(set) var underrunCount: Int = 0
    private(set) var overflowCount: Int = 0
    
    init(targetDelayMs: Double, maxDelayMs: Double, sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        
        // Buffer CAPACITY: Always large (3 seconds) to handle DAW bursts and network hiccups
        self.bufferCapacity = Int(sampleRate) * 3 * channels
        self.buffer = [Float](repeating: 0, count: bufferCapacity)
        
        // Pre-buffer thresholds - more conservative for stability
        // Initial prebuffer: wait for targetDelayMs before starting
        self.minBufferSamples = Int(targetDelayMs / 1000.0 * sampleRate) * channels
        // Quick rebuffer: 200ms to absorb network jitter after underrun
        self.quickRebufferSamples = Int(0.200 * sampleRate) * channels
        
        print("JitterBuffer: capacity=3s, prebuffer=\(Int(targetDelayMs))ms, quick=200ms")
    }
    
    func setTargetDelay(_ delayMs: Double) {
        // Not used in this implementation
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
            overflowCount += 1
        }
        
        // Write samples to circular buffer
        for sample in samples {
            buffer[writePos] = sample
            writePos = (writePos + 1) % bufferCapacity
        }
        samplesInBuffer += samples.count
    }
    
    /// Add samples from pointer (zero-copy from packet data)
    func push(sequence: UInt32, timestamp: UInt64, samples: UnsafePointer<Float>, count: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        packetsReceived += 1
        hasReceivedAnyPacket = true
        
        // Log first packet
        if packetsReceived == 1 {
            print("JitterBuffer: First packet seq=\(sequence), \(count) samples")
        }
        
        // Check if we have room
        let spaceAvailable = bufferCapacity - samplesInBuffer
        if count > spaceAvailable {
            // Buffer overflow - drop oldest samples to make room
            let toDrop = count - spaceAvailable
            readPos = (readPos + toDrop) % bufferCapacity
            samplesInBuffer -= toDrop
            overflowCount += 1
        }
        
        // Write samples to circular buffer
        for i in 0..<count {
            buffer[writePos] = samples[i]
            writePos = (writePos + 1) % bufferCapacity
        }
        samplesInBuffer += count
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
        let hasPlayedBefore = packetsPlayed > 0
        let rebufferThreshold = hasPlayedBefore ? quickRebufferSamples : minBufferSamples
        
        // Wait for buffer to fill
        if isBuffering {
            if samplesInBuffer >= rebufferThreshold {
                isBuffering = false
                fadeInRemaining = fadeInSamples
                let thresholdMs = hasPlayedBefore ? 100 : Int(Double(minBufferSamples) / sampleRate / Double(channels) * 1000)
                print("JitterBuffer: Resuming with \(samplesInBuffer) samples (\(thresholdMs)ms threshold)")
            } else {
                return [Float](repeating: 0, count: sampleCount)
            }
        }
        
        // If buffer runs out, go to rebuffer mode
        if samplesInBuffer < sampleCount {
            isBuffering = true
            underrunCount += 1
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
        underrunCount = 0
        overflowCount = 0
    }
    
    func getStats() -> (received: Int, played: Int, droppedLate: Int, droppedOverflow: Int, buffered: Int, underruns: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (packetsReceived, packetsPlayed, 0, overflowCount, samplesInBuffer / max(channels, 1), underrunCount)
    }
    
    func getUnderrunCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return underrunCount
    }
}
