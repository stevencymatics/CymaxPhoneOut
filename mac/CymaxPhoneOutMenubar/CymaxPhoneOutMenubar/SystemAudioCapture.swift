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
        
        onStatusUpdate?("Setting up audio capture...")

        // Try to get available content — triggers permission prompt if needed
        let availableContent: SCShareableContent
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            print("SystemAudioCapture: SCShareableContent failed: \(error)")
            print("SystemAudioCapture: Requesting permission via CGRequestScreenCaptureAccess...")
            // Try triggering the system permission prompt as fallback
            let granted = CGRequestScreenCaptureAccess()
            print("SystemAudioCapture: CGRequestScreenCaptureAccess returned: \(granted)")
            if granted {
                // Permission was just granted — retry
                do {
                    availableContent = try await SCShareableContent.excludingDesktopWindows(
                        false,
                        onScreenWindowsOnly: false
                    )
                } catch {
                    print("SystemAudioCapture: Retry also failed: \(error)")
                    throw CaptureError.notAuthorized
                }
            } else {
                throw CaptureError.notAuthorized
            }
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

    // Track actual audio format from buffers
    private var detectedSampleRate: Int = 48000
    private var detectedChannels: Int = 2
    private var isNonInterleaved: Bool = true
    private var hasLoggedFormat = false
    private var bufferCount = 0
    private var totalSamplesReceived = 0
    private var zeroBufferCount = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio
        guard type == .audio else { return }

        bufferCount += 1

        // Read the ACTUAL format from the buffer (don't assume anything)
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
            let actualRate = Int(asbd.mSampleRate)
            let actualChannels = Int(asbd.mChannelsPerFrame)
            let nonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

            if !hasLoggedFormat {
                hasLoggedFormat = true
                let layout = nonInterleaved ? "non-interleaved" : "interleaved"
                print("SystemAudioCapture: Format - rate=\(actualRate)Hz, ch=\(actualChannels), \(layout), flags=0x\(String(asbd.mFormatFlags, radix: 16))")
                if actualRate != sampleRate {
                    print("SystemAudioCapture: Sample rate mismatch: requested \(sampleRate)Hz, got \(actualRate)Hz")
                }
                if actualChannels != channels {
                    print("SystemAudioCapture: Channel count mismatch: requested \(channels), got \(actualChannels)")
                }
            }

            detectedSampleRate = actualRate
            detectedChannels = actualChannels
            isNonInterleaved = nonInterleaved
        }

        // Get audio buffer
        guard let audioBuffer = sampleBuffer.dataBuffer else { return }

        // Get the raw audio data
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

        let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
        let totalFloats = length / MemoryLayout<Float>.size

        guard totalFloats > 0 && detectedChannels > 0 else { return }

        let actualCh = detectedChannels
        let frameCount = totalFloats / actualCh

        totalSamplesReceived += totalFloats

        // Build interleaved stereo output regardless of source format
        let outputSampleCount = frameCount * 2 // always output stereo interleaved
        var interleavedSamples = [Float](repeating: 0, count: outputSampleCount)

        if isNonInterleaved {
            // Non-interleaved: [all ch0 samples][all ch1 samples][...]
            for frame in 0..<frameCount {
                let left = floatPointer[frame]
                let right = actualCh >= 2 ? floatPointer[frameCount + frame] : left
                interleavedSamples[frame * 2] = left
                interleavedSamples[frame * 2 + 1] = right
            }
        } else {
            // Interleaved: [ch0, ch1, ch0, ch1, ...] or [ch0, ch1, ch2, ..., ch0, ch1, ch2, ...]
            for frame in 0..<frameCount {
                let left = floatPointer[frame * actualCh]
                let right = actualCh >= 2 ? floatPointer[frame * actualCh + 1] : left
                interleavedSamples[frame * 2] = left
                interleavedSamples[frame * 2 + 1] = right
            }
        }

        // Detect all-zero audio (log periodically for debugging)
        var hasNonZero = false
        for i in stride(from: 0, to: min(interleavedSamples.count, 200), by: 1) {
            if interleavedSamples[i] != 0 {
                hasNonZero = true
                break
            }
        }
        if !hasNonZero {
            zeroBufferCount += 1
            if zeroBufferCount == 100 {
                print("SystemAudioCapture: Warning - 100 consecutive zero-audio buffers (check audio device)")
                onStatusUpdate?("No audio detected - check output device")
            }
        } else {
            zeroBufferCount = 0
        }

        onAudioSamples?(interleavedSamples, detectedSampleRate, 2)
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


