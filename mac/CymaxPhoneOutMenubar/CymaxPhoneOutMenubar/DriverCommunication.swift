//
//  DriverCommunication.swift
//  CymaxPhoneOutMenubar
//
//  Communication with the AudioServerPlugIn driver
//
//  The menubar app communicates with the driver to:
//  - Set the destination IP address for UDP audio packets
//  - Query/set sample rate and buffer size
//
//  MVP Implementation:
//  Uses a file at /tmp/cymax_dest_ip.txt as a simple IPC mechanism.
//  The driver reads from this file when startIO() is called.
//
//  For web mode, we set the destination to 127.0.0.1 (localhost)
//  so the audio is sent to the menubar app's UDP receiver,
//  which then forwards it via WebSocket to browser clients.
//

import Foundation
import CoreAudio

/// Communication with the Cymax Phone Out audio driver
class DriverCommunication {
    /// File path for destination IP (shared with driver)
    private let destIPFilePath = "/tmp/cymax_dest_ip.txt"
    
    /// CFPreferences domain for driver communication (legacy)
    private let preferencesDomain = "com.cymax.phoneoutdriver" as CFString
    
    /// Keys for preferences
    private enum PrefKey {
        static let destinationIP = "DestinationIP" as CFString
        static let sampleRate = "SampleRate" as CFString
        static let bufferSize = "BufferSize" as CFString
    }
    
    /// Device UID for the Cymax Phone Out device
    private let deviceUID = "CymaxPhoneOutMVP"
    
    /// Logger callback
    var onLog: ((String) -> Void)?
    
    private func log(_ message: String) {
        print("DriverCommunication: \(message)")
        onLog?(message)
    }
    
    init() {
        // Ensure preferences are synchronized
        CFPreferencesAppSynchronize(preferencesDomain)
    }
    
    // MARK: - Destination IP
    
    /// Set the destination IP address for UDP audio packets
    /// For web mode, use "127.0.0.1" to send to local UDP receiver
    func setDestinationIP(_ ipAddress: String) {
        log("Setting destination IP to \(ipAddress)")
        
        // Write to /tmp which is accessible to everyone including coreaudiod
        do {
            try ipAddress.write(toFile: destIPFilePath, atomically: true, encoding: .utf8)
            // Make sure it's world-readable
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destIPFilePath)
            log("✓ Wrote IP to \(destIPFilePath)")
        } catch {
            log("⚠ Failed to write IP file: \(error.localizedDescription)")
        }
    }
    
    /// Clear the destination IP address
    func clearDestinationIP() {
        log("Clearing destination IP")
        
        // Remove the file
        do {
            if FileManager.default.fileExists(atPath: destIPFilePath) {
                try FileManager.default.removeItem(atPath: destIPFilePath)
                log("✓ Removed IP file")
            }
        } catch {
            log("⚠ Failed to remove IP file: \(error.localizedDescription)")
        }
    }
    
    /// Get the current destination IP address from file
    func getDestinationIP() -> String? {
        do {
            let ip = try String(contentsOfFile: destIPFilePath, encoding: .utf8)
            return ip.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    // MARK: - Sample Rate
    
    /// Set the sample rate
    func setSampleRate(_ rate: UInt32) {
        CFPreferencesSetValue(
            PrefKey.sampleRate,
            rate as CFNumber,
            preferencesDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesAppSynchronize(preferencesDomain)
    }
    
    /// Get the current sample rate
    func getSampleRate() -> UInt32 {
        let value = CFPreferencesCopyValue(
            PrefKey.sampleRate,
            preferencesDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return (value as? UInt32) ?? 48000
    }
    
    // MARK: - Buffer Size
    
    /// Set the buffer size in frames
    func setBufferSize(_ frames: UInt32) {
        CFPreferencesSetValue(
            PrefKey.bufferSize,
            frames as CFNumber,
            preferencesDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesAppSynchronize(preferencesDomain)
    }
    
    /// Get the current buffer size
    func getBufferSize() -> UInt32 {
        let value = CFPreferencesCopyValue(
            PrefKey.bufferSize,
            preferencesDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return (value as? UInt32) ?? 256
    }
    
    // MARK: - Driver Property Access
    
    /// Find the Cymax Phone Out device
    private func findDevice() -> AudioObjectID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            log("Failed to get device list size, status: \(status)")
            return nil
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        )
        
        guard status == noErr else {
            log("Failed to get devices, status: \(status)")
            return nil
        }
        
        log("Scanning \(deviceCount) audio devices...")
        
        // Find our device by UID
        for device in devices {
            let uid = getDeviceUID(device)
            if uid == deviceUID {
                log("Found device '\(deviceUID)' with ID \(device)")
                return device
            }
        }
        
        log("Device '\(deviceUID)' not found in \(deviceCount) devices")
        return nil
    }
    
    /// Get device UID
    private func getDeviceUID(_ deviceID: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )
        
        guard status == noErr else { return nil }
        return uid as String?
    }
}
