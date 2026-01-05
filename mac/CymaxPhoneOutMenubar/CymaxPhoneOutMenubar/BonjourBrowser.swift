//
//  BonjourBrowser.swift
//  CymaxPhoneOutMenubar
//
//  Bonjour service discovery for finding iPhone receivers
//

import Foundation
import Network

/// Browses for Cymax audio receiver services on the local network
class BonjourBrowser {
    private var browser: NWBrowser?
    private var onDevicesChanged: ([DiscoveredDevice]) -> Void
    private var discoveredServices: [NWBrowser.Result] = []
    private var resolvedDevices: [String: DiscoveredDevice] = [:]
    
    init(onDevicesChanged: @escaping ([DiscoveredDevice]) -> Void) {
        self.onDevicesChanged = onDevicesChanged
    }
    
    deinit {
        stopBrowsing()
    }
    
    func startBrowsing() {
        // Create browser for our service type
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        // Browse for _cymaxaudio._udp services
        browser = NWBrowser(for: .bonjour(type: "_cymaxaudio._udp.", domain: "local."), using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("BonjourBrowser: Ready")
            case .failed(let error):
                print("BonjourBrowser: Failed - \(error)")
            case .cancelled:
                print("BonjourBrowser: Cancelled")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleResultsChanged(results: results, changes: changes)
        }
        
        browser?.start(queue: .main)
    }
    
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        discoveredServices = []
        resolvedDevices = [:]
    }
    
    private func handleResultsChanged(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        discoveredServices = Array(results)
        
        // Resolve each service to get IP addresses
        for result in results {
            resolveService(result)
        }
    }
    
    private func resolveService(_ result: NWBrowser.Result) {
        guard case .service(let name, let type, let domain, _) = result.endpoint else {
            return
        }
        
        // Create a connection to resolve the address
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        
        let connection = NWConnection(to: result.endpoint, using: parameters)
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                // Get the resolved addresses
                if let path = connection.currentPath,
                   let endpoint = path.remoteEndpoint {
                    
                    var ipAddress: String?
                    
                    // Extract IP from endpoint
                    switch endpoint {
                    case .hostPort(let host, let port):
                        switch host {
                        case .ipv4(let addr):
                            ipAddress = "\(addr)"
                        case .ipv6(let addr):
                            ipAddress = "\(addr)"
                        case .name(let hostname, _):
                            ipAddress = hostname
                        @unknown default:
                            break
                        }
                    default:
                        break
                    }
                    
                    let device = DiscoveredDevice(
                        id: "\(name).\(type)\(domain)",
                        name: name,
                        hostName: "\(name).\(domain)",
                        port: 19620,
                        ipAddress: ipAddress
                    )
                    
                    DispatchQueue.main.async {
                        self?.resolvedDevices[device.id] = device
                        self?.notifyDevicesChanged()
                    }
                }
                
                connection.cancel()
            }
        }
        
        connection.start(queue: .global())
        
        // Timeout the resolution
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if connection.state != .cancelled {
                connection.cancel()
            }
        }
    }
    
    private func notifyDevicesChanged() {
        let devices = Array(resolvedDevices.values)
        onDevicesChanged(devices)
    }
}


