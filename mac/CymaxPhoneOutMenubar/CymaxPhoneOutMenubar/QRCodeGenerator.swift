//
//  QRCodeGenerator.swift
//  CymaxPhoneOutMenubar
//
//  QR code generation for easy connection
//

import Foundation
import CoreImage
import AppKit

/// QR Code generator using CoreImage
class QRCodeGenerator {
    
    /// Generate a QR code image for the given URL
    /// - Parameters:
    ///   - url: The URL to encode
    ///   - size: The desired size of the QR code
    /// - Returns: NSImage of the QR code, or nil if generation fails
    static func generate(url: String, size: CGFloat = 200) -> NSImage? {
        // Create the QR code filter
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            print("QRCodeGenerator: Failed to create filter")
            return nil
        }
        
        // Set the message data
        guard let data = url.data(using: .utf8) else {
            print("QRCodeGenerator: Failed to encode URL")
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        // Get the output image
        guard let ciImage = filter.outputImage else {
            print("QRCodeGenerator: No output image")
            return nil
        }
        
        // Scale the image to the desired size
        let scaleX = size / ciImage.extent.size.width
        let scaleY = size / ciImage.extent.size.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Convert to NSImage
        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: NSSize(width: size, height: size))
        nsImage.addRepresentation(rep)
        
        return nsImage
    }
    
    /// Get the local IP address of the Mac
    static func getLocalIPAddress() -> String? {
        var address: String?
        
        // Get list of all interfaces
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            
            // Check for IPv4
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                // Get interface name
                let name = String(cString: interface.ifa_name)
                
                // Prefer en0 (WiFi) or en1, skip lo0 (localhost)
                if name == "en0" || name == "en1" || name.hasPrefix("en") {
                    // Convert address to string
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        // Prefer WiFi (en0)
                        if name == "en0" {
                            return ip
                        }
                        if address == nil {
                            address = ip
                        }
                    }
                }
            }
        }
        
        return address
    }
    
    /// Generate the full URL for the web player
    static func getWebPlayerURL(httpPort: UInt16 = 8080) -> String? {
        guard let ip = getLocalIPAddress() else {
            return nil
        }
        return "http://\(ip):\(httpPort)"
    }
}


