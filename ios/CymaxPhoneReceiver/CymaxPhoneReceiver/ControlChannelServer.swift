//
//  ControlChannelServer.swift
//  CymaxPhoneReceiver
//
//  TCP control channel server for communication with Mac
//

import Foundation
import Network

/// TCP control channel server
class ControlChannelServer {
    private var listener: NWListener?
    private var connection: NWConnection?
    private let port: UInt16
    
    /// Track connection state to prevent sending on dead connections
    private var isConnected = false
    
    // Callbacks
    private let onHello: (HelloMessage) -> Void
    private let onFormatRequest: (FormatRequest) -> Void
    private let onDisconnect: (String) -> Void
    
    private var receiveBuffer = Data()
    
    init(port: UInt16, 
         onHello: @escaping (HelloMessage) -> Void,
         onFormatRequest: @escaping (FormatRequest) -> Void,
         onDisconnect: @escaping (String) -> Void) {
        self.port = port
        self.onHello = onHello
        self.onFormatRequest = onFormatRequest
        self.onDisconnect = onDisconnect
    }
    
    deinit {
        stop()
    }
    
    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("ControlChannelServer: Listening on port \(self.port)")
                case .failed(let error):
                    print("ControlChannelServer: Failed - \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                // Accept only one connection at a time
                self?.connection?.cancel()
                self?.connection = newConnection
                self?.handleConnection(newConnection)
            }
            
            listener?.start(queue: .main)
            
        } catch {
            print("ControlChannelServer: Failed to start - \(error)")
        }
    }
    
    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }
    
    // MARK: - Sending Messages
    
    func sendHelloAck(_ ack: HelloAckMessage) {
        send(message: .helloAck(ack))
    }
    
    func sendFormatAck(_ ack: FormatAckMessage) {
        send(message: .formatAck(ack))
    }
    
    func sendStats(_ stats: StatsMessage) {
        send(message: .stats(stats))
    }
    
    func sendDisconnect(reason: String) {
        send(message: .disconnect(DisconnectMessage(reason: reason)))
    }
    
    // MARK: - Private
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("ControlChannelServer: Client connected")
                self?.isConnected = true
                self?.startReceiving()
            case .failed(let error):
                print("ControlChannelServer: Connection failed - \(error)")
                self?.isConnected = false
                self?.onDisconnect("Connection failed: \(error.localizedDescription)")
            case .cancelled:
                self?.isConnected = false
                self?.onDisconnect("Connection cancelled")
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func startReceiving() {
        receiveLoop()
    }
    
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.onDisconnect("Receive error: \(error.localizedDescription)")
                return
            }
            
            if let data = data {
                self.receiveBuffer.append(data)
                self.processReceiveBuffer()
            }
            
            if isComplete {
                self.onDisconnect("Connection closed by peer")
                return
            }
            
            // Continue receiving
            self.receiveLoop()
        }
    }
    
    private func processReceiveBuffer() {
        // Message format: [4-byte length][JSON payload]
        while receiveBuffer.count >= 4 {
            let length = receiveBuffer.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            
            guard receiveBuffer.count >= 4 + Int(length) else {
                break
            }
            
            let messageData = receiveBuffer.subdata(in: 4..<(4 + Int(length)))
            receiveBuffer.removeFirst(4 + Int(length))
            
            do {
                let message = try JSONDecoder().decode(ControlMessage.self, from: messageData)
                handleMessage(message)
            } catch {
                print("ControlChannelServer: Failed to decode message - \(error)")
            }
        }
    }
    
    private func handleMessage(_ message: ControlMessage) {
        switch message {
        case .hello(let hello):
            onHello(hello)
            
        case .formatRequest(let request):
            onFormatRequest(request)
            
        case .disconnect(let msg):
            onDisconnect(msg.reason)
            
        case .ping:
            send(message: .pong)
            
        default:
            break
        }
    }
    
    private func send(message: ControlMessage) {
        guard let connection = connection, isConnected else { return }
        
        do {
            let json = try JSONEncoder().encode(message)
            
            var data = Data(capacity: 4 + json.count)
            var length = UInt32(json.count).littleEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(json)
            
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("ControlChannelServer: Send error - \(error)")
                    // Mark as disconnected to prevent further sends
                    self?.isConnected = false
                }
            })
        } catch {
            print("ControlChannelServer: Failed to encode message - \(error)")
        }
    }
}

// MARK: - Message Types (shared with macOS app)

enum ControlMessage: Codable {
    case hello(HelloMessage)
    case helloAck(HelloAckMessage)
    case formatRequest(FormatRequest)
    case formatAck(FormatAckMessage)
    case stats(StatsMessage)
    case disconnect(DisconnectMessage)
    case ping
    case pong
}

struct HelloMessage: Codable {
    let deviceName: String
    let sampleRate: UInt32
    let channels: UInt16
}

struct HelloAckMessage: Codable {
    let deviceName: String
    let accepted: Bool
    let rejectionReason: String?
}

struct FormatRequest: Codable {
    let sampleRate: UInt32
    let channels: UInt16
}

struct FormatAckMessage: Codable {
    let accepted: Bool
    let sampleRate: UInt32
    let channels: UInt16
}

struct StatsMessage: Codable {
    let packetsReceived: UInt64
    let packetsLost: UInt64
    let jitterMs: Double
    let bufferLevelMs: Double
    let lossPercentage: Double
}

struct DisconnectMessage: Codable {
    let reason: String
}

