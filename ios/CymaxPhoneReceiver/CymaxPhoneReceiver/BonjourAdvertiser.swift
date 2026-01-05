//
//  BonjourAdvertiser.swift
//  CymaxPhoneReceiver
//
//  Bonjour service advertising for discovery by Mac
//

import Foundation
import Network

/// Advertises this device as a Cymax audio receiver
class BonjourAdvertiser {
    private var listener: NWListener?
    private let deviceName: String
    private let onError: (String) -> Void
    
    init(deviceName: String, onError: @escaping (String) -> Void) {
        self.deviceName = deviceName
        self.onError = onError
    }
    
    deinit {
        stopAdvertising()
    }
    
    func startAdvertising() {
        do {
            // Create UDP listener for Bonjour advertisement
            let parameters = NWParameters.udp
            parameters.includePeerToPeer = true
            
            // Set up Bonjour service
            parameters.serviceClass = .interactiveVideo  // Low latency
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: 19620)!)
            
            // Advertise as Bonjour service
            listener?.service = NWListener.Service(
                name: deviceName,
                type: "_cymaxaudio._udp.",
                domain: "local.",
                txtRecord: createTXTRecord()
            )
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("BonjourAdvertiser: Ready, advertising as '\(self?.deviceName ?? "")'")
                case .failed(let error):
                    print("BonjourAdvertiser: Failed - \(error)")
                    self?.onError("Bonjour failed: \(error.localizedDescription)")
                case .cancelled:
                    print("BonjourAdvertiser: Cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { connection in
                // We don't accept connections on the advertiser listener
                // Audio comes via separate UDP socket
                connection.cancel()
            }
            
            listener?.start(queue: .main)
            
        } catch {
            print("BonjourAdvertiser: Failed to create listener - \(error)")
            onError("Failed to start advertising: \(error.localizedDescription)")
        }
    }
    
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
    }
    
    private func createTXTRecord() -> NWTXTRecord {
        var txtRecord = NWTXTRecord()
        txtRecord["name"] = deviceName
        txtRecord["ver"] = "1.0"
        txtRecord["rates"] = "44100,48000"
        txtRecord["ch"] = "2"
        return txtRecord
    }
}


