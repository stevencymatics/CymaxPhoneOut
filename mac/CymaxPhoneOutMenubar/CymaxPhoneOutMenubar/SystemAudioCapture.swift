//
//  SystemAudioCapture.swift
//  CymaxPhoneOutMenubar
//
//  Captures system audio using ScreenCaptureKit
//  No need to change audio output device!
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreGraphics

/// Captures system audio using ScreenCaptureKit
@available(macOS 13.0, *)
class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    
    private var stream: SCStream?
    private var isCapturing = false
    private var hasCheckedPermission = false
    
    /// Callback for captured audio samples
    var onAudioSamples: (([Float], Int, Int) -> Void)?  // samples, sampleRate, channels
    
    /// Callback for errors
    var onError: ((String) -> Void)?
    
    /// Callback for status updates
    var onStatusUpdate: ((String) -> Void)?
    
    // Audio format
    private let sampleRate: Int = 48000
    private let channels: Int = 2
    
    // Packet sequencing
    private var sequenceNumber: UInt32 = 0
    
    override init() {
        super.init()
    }
    
    deinit {
        stop()
    }
    
    /// Quick synchronous permission check using CGPreflight (may not reflect ScreenCaptureKit permission on macOS 15+)
    static func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Reliable async permission check using ScreenCaptureKit directly.
    /// On macOS 15+, ScreenCaptureKit has its own permission separate from the legacy CGWindowList-based Screen Recording.
    static func checkPermissionAsync() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }

    /// Open System Settings to Screen Recording pane
    static func openSystemSettings() {
        // Try macOS 15+ URL first, fall back to legacy
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
    
    /// Start capturing system audio
    func start() async throws {
        guard !isCapturing else { return }
        
        // Check permission using ScreenCaptureKit (reliable on macOS 15+)
        let hasPermission = await SystemAudioCapture.checkPermissionAsync()
        if !hasPermission {
            throw CaptureError.notAuthorized
        }
        
        onStatusUpdate?("Setting up audio capture...")

        // Get available content
        let availableContent: SCShareableContent
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            throw error
        }
        
        // We need at least one display to create a stream
        guard let display = availableContent.displays.first else {
            throw CaptureError.noDisplay
        }
        
        onStatusUpdate?("Setting up audio capture...")
        
        // Create filter - we want system audio, not specific windows
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure stream - audio only (we'll ignore video)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Don't capture our own audio
        config.sampleRate = sampleRate
        config.channelCount = channels
        
        // Minimal video settings (required but we'll ignore it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS minimum
        config.showsCursor = false
        
        // Create stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Add audio output
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.cymax.audiocapture"))
        
        onStatusUpdate?("Starting audio capture...")
        
        // Start capture
        try await stream?.startCapture()
        
        isCapturing = true
        onStatusUpdate?("Capturing system audio")
        print("SystemAudioCapture: Started capturing system audio")
    }
    
    /// Stop capturing
    func stop() {
        guard isCapturing else { return }
        
        Task {
            try? await stream?.stopCapture()
            stream = nil
            isCapturing = false
            sequenceNumber = 0
            print("SystemAudioCapture: Stopped")
        }
    }
    
    // MARK: - SCStreamOutput
    
    // Track actual sample rate from audio buffers
    private var detectedSampleRate: Int = 48000
    private var hasLoggedFormat = false
    private var bufferCount = 0
    private var totalSamplesReceived = 0
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio
        guard type == .audio else { return }
        
        bufferCount += 1

        // Get the ACTUAL sample rate from the format description
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
            let actualRate = Int(asbd.mSampleRate)
            let actualChannels = Int(asbd.mChannelsPerFrame)
            
            // Log format once
            if !hasLoggedFormat {
                hasLoggedFormat = true
                print("SystemAudioCapture: Actual format - rate=\(actualRate)Hz, channels=\(actualChannels)")
                if actualRate != sampleRate {
                    print("SystemAudioCapture: ⚠️ Sample rate mismatch! Requested \(sampleRate)Hz but got \(actualRate)Hz")
                }
            }
            
            detectedSampleRate = actualRate
        }
        
        // Get audio buffer
        guard let audioBuffer = sampleBuffer.dataBuffer else { return }
        
        // Get the audio data
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            audioBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer, length > 0 else {
            return
        }
        
        // Convert to Float32 samples
        // ScreenCaptureKit outputs Float32 NON-INTERLEAVED (all L samples, then all R samples)
        let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
        let sampleCount = length / MemoryLayout<Float>.size
        let frameCount = sampleCount / channels  // frames = total samples / channels
        
        totalSamplesReceived += sampleCount

        // Convert from NON-INTERLEAVED to INTERLEAVED format
        // Input:  [L0, L1, L2, ..., L(n-1), R0, R1, R2, ..., R(n-1)]
        // Output: [L0, R0, L1, R1, L2, R2, ..., L(n-1), R(n-1)]
        var interleavedSamples = [Float](repeating: 0, count: sampleCount)
        for frame in 0..<frameCount {
            let leftSample = floatPointer[frame]                    // Left channel: first half
            let rightSample = floatPointer[frameCount + frame]      // Right channel: second half
            interleavedSamples[frame * 2] = leftSample
            interleavedSamples[frame * 2 + 1] = rightSample
        }
        
        // Call the handler with INTERLEAVED samples and the ACTUAL detected sample rate
        onAudioSamples?(interleavedSamples, detectedSampleRate, channels)
    }
    
    // MARK: - SCStreamDelegate
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("SystemAudioCapture: Stream stopped with error: \(error)")
        isCapturing = false
        onError?("Capture stopped: \(error.localizedDescription)")
    }
}

// MARK: - Errors

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case notAuthorized
    case captureFailedToStart
    
    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display found"
        case .notAuthorized:
            return "Screen recording permission not granted"
        case .captureFailedToStart:
            return "Failed to start capture"
        }
    }
}


