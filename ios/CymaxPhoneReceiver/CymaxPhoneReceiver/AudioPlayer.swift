//
//  AudioPlayer.swift
//  CymaxPhoneReceiver
//
//  AVAudioEngine-based audio playback using AVAudioSourceNode (pull model)
//
//  CRITICAL REAL-TIME CONSTRAINTS:
//  - Render callback must NEVER allocate memory
//  - Render callback must NEVER lock
//  - Uses zero-allocation pullInto() from JitterBuffer
//

import Foundation
import AVFoundation

/// Audio playback engine using AVAudioSourceNode
class AudioPlayer {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var jitterBuffer: JitterBuffer
    
    private var sampleRate: Double          // Engine playback rate (iOS hardware rate)
    private var incomingSampleRate: Double   // Rate from Mac packets (may differ)
    private var channels: Int
    private var targetJitterBufferMs: Double
    private var isPlaying = false
    
    // Audio receiver reference for packet delivery
    private weak var audioReceiver: AudioReceiver?
    
    // Stats for logging (updated outside render callback)
    private var packetLogCounter = 0
    
    // Prevent infinite reconfigure loop
    private var hasLoggedRateMismatch = false
    
    init(sampleRate: Double, channels: Int, jitterBufferMs: Double) {
        self.sampleRate = sampleRate
        self.incomingSampleRate = sampleRate
        self.channels = channels
        self.targetJitterBufferMs = jitterBufferMs
        self.jitterBuffer = JitterBuffer(
            targetDelayMs: jitterBufferMs,
            maxDelayMs: jitterBufferMs * 3,
            sampleRate: sampleRate,
            channels: channels
        )
        
        // Configure audio session FIRST
        configureAudioSession()
        
        setupEngine()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Setup
    
    /// Configure AVAudioSession - uses iOS native rate (48000Hz)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // Set category for playback
            try session.setCategory(.playback, mode: .default, options: [])
            
            // Use iOS native sample rate (48000Hz) - don't try to change it
            // AVAudioEngine will handle resampling if Mac sends different rate
            try session.setPreferredSampleRate(48000.0)
            
            // Set preferred buffer duration for low latency
            try session.setPreferredIOBufferDuration(256.0 / 48000.0)
            
            // Activate the session
            try session.setActive(true)
            
            // Get actual sample rate from iOS
            let actualSampleRate = session.sampleRate
            self.sampleRate = actualSampleRate  // Use whatever iOS gives us
            print("AudioPlayer: Audio session configured - using iOS rate: \(Int(actualSampleRate))Hz")
            
        } catch {
            print("AudioPlayer: Failed to configure audio session - \(error)")
        }
    }
    
    private func setupEngine() {
        engine = AVAudioEngine()
        
        guard let engine = engine else { return }
        
        // Use standard (non-interleaved) format - required by AVAudioEngine
        // We'll de-interleave the incoming audio in the render callback
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channels)
        )!
        
        print("AudioPlayer: Engine format - \(Int(sampleRate))Hz, \(channels)ch, interleaved=\(format.isInterleaved)")
        
        // Create source node with render callback
        // CRITICAL: This callback must be RT-safe (no allocs, no locks)
        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            return self?.renderCallback(frameCount: frameCount, audioBufferList: audioBufferList) ?? noErr
        }
        
        guard let sourceNode = sourceNode else { return }
        
        // Attach and connect nodes
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        
        // Prepare engine
        engine.prepare()
        
        // Log the actual output format to detect sample rate issues
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        print("AudioPlayer: MainMixer output - \(Int(outputFormat.sampleRate))Hz, \(outputFormat.channelCount)ch")
        
        if abs(outputFormat.sampleRate - sampleRate) > 100 {
            print("AudioPlayer: ⚠️ SAMPLE RATE MISMATCH! Source=\(Int(sampleRate))Hz, Output=\(Int(outputFormat.sampleRate))Hz")
        }
    }
    
    // Debug counter for render callback (only log occasionally)
    private var renderLogCounter = 0
    
    /// CRITICAL: This is the audio render callback - must be RT-safe
    /// Incoming audio is INTERLEAVED: [L0, R0, L1, R1, L2, R2, ...]
    /// Output format is NON-INTERLEAVED: buffer[0]=[L0,L1,L2...], buffer[1]=[R0,R1,R2...]
    private func renderCallback(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let numFrames = Int(frameCount)
        
        // Debug log occasionally (not RT-safe but OK for debugging)
        renderLogCounter += 1
        if renderLogCounter == 1 || renderLogCounter == 100 {
            print("AudioPlayer: RenderCallback buffers=\(ablPointer.count) frameCount=\(frameCount) channels=\(channels)")
        }
        
        // Pull interleaved samples from jitter buffer
        // samples = [L0, R0, L1, R1, L2, R2, ...]
        if let samples = jitterBuffer.pull(frameCount: numFrames) {
            // De-interleave to separate channel buffers
            // For stereo: buffer[0] = left, buffer[1] = right
            for bufferIndex in 0..<min(ablPointer.count, channels) {
                guard let data = ablPointer[bufferIndex].mData else { continue }
                let floatBuffer = data.assumingMemoryBound(to: Float.self)
                
                for frame in 0..<numFrames {
                    // Interleaved index: frame * channels + channelIndex
                    let sampleIndex = frame * channels + bufferIndex
                    if sampleIndex < samples.count {
                        floatBuffer[frame] = samples[sampleIndex]
                    } else {
                        floatBuffer[frame] = 0
                    }
                }
            }
        } else {
            // No data - output silence to all buffers
            for bufferIndex in 0..<ablPointer.count {
                if let data = ablPointer[bufferIndex].mData {
                    memset(data, 0, Int(ablPointer[bufferIndex].mDataByteSize))
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
    
    /// Handle incoming audio packet - called from network thread
    /// Optimized to minimize allocations
    private func handlePacket(_ packet: ReceivedAudioPacket) {
        // Track incoming sample rate (may differ from iOS playback rate)
        let incomingRate = Double(packet.sampleRate)
        if abs(incomingRate - incomingSampleRate) > 100 {
            incomingSampleRate = incomingRate
        }
        
        // Log sample rate mismatch once (don't try to reconfigure - iOS hardware is fixed)
        if abs(incomingRate - sampleRate) > 100 && !hasLoggedRateMismatch {
            hasLoggedRateMismatch = true
            print("AudioPlayer: ⚠️ Rate mismatch - Mac sends \(Int(incomingRate))Hz, iOS plays \(Int(sampleRate))Hz")
            print("AudioPlayer: Audio may be pitched. Fix: set Mac system audio to 48kHz")
        }
        
        // Push directly from Data to jitter buffer - avoid intermediate [Float] array
        packet.audioData.withUnsafeBytes { rawBuffer in
            guard let floatPtr = rawBuffer.baseAddress?.assumingMemoryBound(to: Float.self) else {
                print("AudioPlayer: ERROR - could not get baseAddress from packet")
                return
            }
            let floatCount = packet.audioData.count / MemoryLayout<Float>.size
            
            // Log first few packets (this allocation is OK, we're on network thread)
            packetLogCounter += 1
            if packetLogCounter <= 5 {
                // Calculate max sample value for debugging
                var maxVal: Float = 0
                var nonZeroCount = 0
                for i in 0..<min(floatCount, 100) {
                    let absVal = abs(floatPtr[i])
                    if absVal > maxVal { maxVal = absVal }
                    if absVal > 0.0001 { nonZeroCount += 1 }
                }
                
                // Also show raw bytes to debug
                let rawBytes = packet.audioData.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                // Show PACKET sample rate to debug sample rate mismatch
                print("AudioPlayer: Packet \(packetLogCounter) seq=\(packet.sequence) pktRate=\(packet.sampleRate)Hz bytes=\(packet.audioData.count) frames=\(packet.frameCount)")
                print("  max=\(String(format: "%.6f", maxVal)) nonZero=\(nonZeroCount)/100 rawBytes=[\(rawBytes)]")
            } else if packetLogCounter % 500 == 0 {
                var maxVal: Float = 0
                for i in 0..<min(floatCount, 100) {
                    let absVal = abs(floatPtr[i])
                    if absVal > maxVal { maxVal = absVal }
                }
                print("AudioPlayer: Packet \(packetLogCounter) seq=\(packet.sequence) max=\(String(format: "%.4f", maxVal))")
            }
            
            // Push directly to jitter buffer
            jitterBuffer.push(
                sequence: packet.sequence,
                timestamp: packet.timestamp,
                samples: floatPtr,
                count: floatCount
            )
        }
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
        let bufMs = jitterBuffer.getBufferLevelMs()
        print("AudioPlayer: rcvd=\(stats.received) played=\(stats.played) overflow=\(stats.droppedOverflow) underrun=\(stats.underruns) buf=\(Int(bufMs))ms")
        
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
        
        self.incomingSampleRate = sampleRate
        self.channels = channels
        self.hasLoggedRateMismatch = false  // Reset so we log again if rate changes
        
        // Reconfigure audio session (will set self.sampleRate to iOS native rate)
        configureAudioSession()
        
        // Recreate jitter buffer with iOS playback rate
        jitterBuffer = JitterBuffer(
            targetDelayMs: targetJitterBufferMs,
            maxDelayMs: targetJitterBufferMs * 3,
            sampleRate: self.sampleRate,  // Use iOS hardware rate
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
    
    func getUnderrunCount() -> Int {
        return jitterBuffer.underrunCount
    }
}
