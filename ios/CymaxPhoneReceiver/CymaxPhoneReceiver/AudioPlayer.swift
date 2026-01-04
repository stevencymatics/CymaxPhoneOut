//
//  AudioPlayer.swift
//  CymaxPhoneReceiver
//
//  AVAudioEngine-based audio playback using AVAudioSourceNode (pull model)
//
//  IMPORTANT: Uses AVAudioSourceNode for lowest latency playback.
//  The source node pulls samples directly from the jitter buffer
//  in the audio render callback.
//

import Foundation
import AVFoundation

/// Audio playback engine using AVAudioSourceNode
class AudioPlayer {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var jitterBuffer: JitterBuffer
    
    private var sampleRate: Double
    private var channels: Int
    private var targetJitterBufferMs: Double  // Store the target, not current level
    private var isPlaying = false
    
    // Audio receiver reference for packet delivery
    private weak var audioReceiver: AudioReceiver?
    
    init(sampleRate: Double, channels: Int, jitterBufferMs: Double) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.targetJitterBufferMs = jitterBufferMs
        self.jitterBuffer = JitterBuffer(
            targetDelayMs: jitterBufferMs,
            maxDelayMs: jitterBufferMs * 3,
            sampleRate: sampleRate,
            channels: channels
        )
        
        setupEngine()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Setup
    
    private func setupEngine() {
        engine = AVAudioEngine()
        
        guard let engine = engine else { return }
        
        // Create format for source node
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channels)
        )!
        
        // Create source node with render callback
        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            return self?.renderCallback(frameCount: frameCount, audioBufferList: audioBufferList) ?? noErr
        }
        
        guard let sourceNode = sourceNode else { return }
        
        // Attach and connect nodes
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        
        // Prepare engine
        engine.prepare()
    }
    
    private func renderCallback(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        // CRITICAL: This is the audio render callback
        // Must be fast and not block
        
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        
        // Pull samples from jitter buffer
        if let samples = jitterBuffer.pull(frameCount: Int(frameCount)) {
            // Copy interleaved samples to buffer
            for bufferIndex in 0..<ablPointer.count {
                let buffer = ablPointer[bufferIndex]
                if let data = buffer.mData {
                    let floatBuffer = data.assumingMemoryBound(to: Float.self)
                    
                    // For stereo, samples are interleaved
                    // AVAudioSourceNode expects non-interleaved for multi-channel
                    // But our format is interleaved stereo in one buffer
                    
                    for frame in 0..<Int(frameCount) {
                        let sampleIndex = frame * channels + bufferIndex
                        if sampleIndex < samples.count {
                            floatBuffer[frame] = samples[sampleIndex]
                        } else {
                            floatBuffer[frame] = 0
                        }
                    }
                }
            }
        } else {
            // No data - output silence
            for bufferIndex in 0..<ablPointer.count {
                let buffer = ablPointer[bufferIndex]
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
        }
        
        return noErr
    }
    
    // MARK: - Control
    
    func setAudioSource(_ receiver: AudioReceiver) {
        audioReceiver = receiver
        
        // Set up packet handler to feed jitter buffer
        receiver.setPacketHandler { [weak self] packet in
            self?.handlePacket(packet)
        }
    }
    
    private var packetLogCounter = 0
    
    private func handlePacket(_ packet: ReceivedAudioPacket) {
        // Convert Data to Float array
        let floatCount = packet.audioData.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: floatCount)
        
        packet.audioData.withUnsafeBytes { buffer in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            for i in 0..<floatCount {
                samples[i] = floatBuffer[i]
            }
        }
        
        // Log first few packets with sample values to verify format
        packetLogCounter += 1
        if packetLogCounter <= 3 {
            // Show first few sample values
            let samplePreview = samples.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            let maxVal = samples.map { abs($0) }.max() ?? 0
            print("AudioPlayer: Packet \(packetLogCounter) seq=\(packet.sequence) samples=\(floatCount) max=\(String(format: "%.4f", maxVal))")
            print("  First 8 samples: [\(samplePreview)]")
        } else if packetLogCounter % 500 == 0 {
            let maxVal = samples.map { abs($0) }.max() ?? 0
            print("AudioPlayer: Packet \(packetLogCounter) seq=\(packet.sequence) max=\(String(format: "%.4f", maxVal))")
        }
        
        // Push to jitter buffer
        jitterBuffer.push(
            sequence: packet.sequence,
            timestamp: packet.timestamp,
            samples: samples
        )
    }
    
    func start() {
        guard !isPlaying else {
            print("AudioPlayer: Already playing")
            return
        }
        guard let engine = engine else {
            print("AudioPlayer: No engine!")
            return
        }
        
        do {
            try engine.start()
            isPlaying = true
            print("AudioPlayer: Started successfully")
            
            // Start a debug timer to show stats
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.printDebugStats()
            }
        } catch {
            print("AudioPlayer: Failed to start - \(error)")
        }
    }
    
    private func printDebugStats() {
        guard isPlaying else { return }
        let stats = jitterBuffer.getStats()
        print("AudioPlayer: rcvd=\(stats.received) played=\(stats.played) late=\(stats.droppedLate) buf=\(stats.buffered)")
        
        // Continue printing stats
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.printDebugStats()
        }
    }
    
    func stop() {
        guard isPlaying, let engine = engine else { return }
        
        engine.stop()
        isPlaying = false
        jitterBuffer.reset()
        print("AudioPlayer: Stopped")
    }
    
    func updateFormat(sampleRate: Double, channels: Int) {
        let wasPlaying = isPlaying
        
        if wasPlaying {
            stop()
        }
        
        self.sampleRate = sampleRate
        self.channels = channels
        
        // Recreate jitter buffer with SAME target delay (not current buffer level!)
        jitterBuffer = JitterBuffer(
            targetDelayMs: targetJitterBufferMs,
            maxDelayMs: targetJitterBufferMs * 3,
            sampleRate: sampleRate,
            channels: channels
        )
        
        // Recreate engine
        engine?.stop()
        engine = nil
        sourceNode = nil
        setupEngine()
        
        // Re-attach audio source
        if let receiver = audioReceiver {
            setAudioSource(receiver)
        }
        
        if wasPlaying {
            start()
        }
    }
    
    func setJitterBufferTarget(_ targetMs: Double) {
        targetJitterBufferMs = targetMs
        jitterBuffer.setTargetDelay(targetMs)
    }
    
    func getBufferLevelMs() -> Double {
        return jitterBuffer.getBufferLevelMs()
    }
}

