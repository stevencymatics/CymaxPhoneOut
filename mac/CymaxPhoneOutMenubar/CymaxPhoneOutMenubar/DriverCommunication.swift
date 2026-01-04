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
//  Uses CFPreferences as a simple IPC mechanism.
//  The driver reads from the same preference domain.
//
//  Production Migration:
//  Should use custom AudioObject properties via AudioObjectSetPropertyData
//  or XPC + shared memory for better architecture.
//

import Foundation
import CoreAudio

/// Communication with the Cymax Phone Out audio driver
class DriverCommunication {
    /// CFPreferences domain for driver communication
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
    func setDestinationIP(_ ipAddress: String) {
        log("Setting destination IP to \(ipAddress)")
        
        // Write to /tmp which is accessible to everyone including coreaudiod
        let filePath = "/tmp/cymax_dest_ip.txt"
        
        do {
            try ipAddress.write(toFile: filePath, atomically: true, encoding: .utf8)
            // Make sure it's world-readable
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: filePath)
            log("✓ Wrote IP to \(filePath)")
        } catch {
            log("⚠ Failed to write IP file: \(error.localizedDescription)")
        }
    }
    
    /// Clear the destination IP address
    func clearDestinationIP() {
        CFPreferencesSetValue(
            PrefKey.destinationIP,
            nil,
            preferencesDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesAppSynchronize(preferencesDomain)
        
        setDriverProperty(selector: 0x44737449 /* 'DstI' */, value: "")
    }
    
    /// Get the current destination IP address
    func getDestinationIP() -> String? {
        let value = CFPreferencesCopyValue(
            PrefKey.destinationIP,
            preferencesDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        return value as? String
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
    
    /// Set a custom property on the driver
    private func setDriverProperty(selector: AudioObjectPropertySelector, value: String) {
        guard let deviceID = findDevice() else {
            log("⚠ Driver not found - IP not sent to driver")
            return
        }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Check if property exists
        let hasProperty = AudioObjectHasProperty(deviceID, &propertyAddress)
        
        guard hasProperty else {
            log("⚠ Property not found on driver")
            return
        }
        
        // Set the property
        var cString = Array(value.utf8CString)
        let dataSize = UInt32(cString.count)
        
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &cString
        )
        
        if status == noErr {
            log("✓ Destination IP sent to driver")
        } else {
            log("⚠ Failed to set driver IP, error: \(status)")
        }
    }
}

