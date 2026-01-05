//
//  WebSocketServer.swift
//  CymaxPhoneOutMenubar
//
//  WebSocket server to stream audio to browser clients
//

import Foundation
import Network

/// WebSocket server for streaming audio to browsers
class WebSocketServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.cymax.websocket")
    private let connectionsLock = NSLock()
    
    private var isRunning = false
    
    // Stats
    var connectedClients: Int {
        connectionsLock.lock()
        defer { connectionsLock.unlock() }
        return connections.count
    }
    
    /// Callback when client count changes
    var onClientCountChanged: ((Int) -> Void)?
    
    init(port: UInt16 = 19622) {
        self.port = port
    }
    
    deinit {
        stop()
    }
    
    /// Start the WebSocket server
    func start() {
        guard !isRunning else { return }
        
        do {
            // Create WebSocket parameters
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            // Add WebSocket options
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("WebSocketServer: Listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    print("WebSocketServer: Failed - \(error)")
                    self?.isRunning = false
                case .cancelled:
                    print("WebSocketServer: Cancelled")
                    self?.isRunning = false
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: queue)
            isRunning = true
            
        } catch {
            print("WebSocketServer: Error starting - \(error)")
        }
    }
    
    /// Stop the server
    func stop() {
        listener?.cancel()
        listener = nil
        
        connectionsLock.lock()
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        connectionsLock.unlock()
        
        isRunning = false
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(0)
        }
    }
    
    /// Broadcast audio packet to all connected clients
    func broadcast(_ packet: AudioPacket) {
        // Convert packet to data on calling thread
        let data = packet.toWebSocketData()
        
        // Dispatch to WebSocket queue for thread safety with Network framework
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.connectionsLock.lock()
            let conns = self.connections
            self.connectionsLock.unlock()
            
            guard !conns.isEmpty else { return }
            
            // Create WebSocket binary frame
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "audio", metadata: [metadata])
            
            for conn in conns {
                conn.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                    if let error = error {
                        // Connection likely dropped - will be cleaned up on next state change
                        print("WebSocketServer: Send error - \(error)")
                    }
                })
            }
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("WebSocketServer: New connection from \(connection.endpoint)")
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("WebSocketServer: Client connected")
                self?.addConnection(connection)
                
            case .failed(let error):
                print("WebSocketServer: Client failed - \(error)")
                self?.removeConnection(connection)
                
            case .cancelled:
                print("WebSocketServer: Client disconnected")
                self?.removeConnection(connection)
                
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        // Start receiving (for pings/pongs and close frames)
        receiveMessage(on: connection)
    }
    
    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            if let error = error {
                print("WebSocketServer: Receive error - \(error)")
                return
            }
            
            // Handle WebSocket control frames (pings are auto-replied)
            if let context = context,
               let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch metadata.opcode {
                case .close:
                    print("WebSocketServer: Client sent close frame")
                    connection.cancel()
                    return
                default:
                    break
                }
            }
            
            // Continue receiving
            self?.receiveMessage(on: connection)
        }
    }
    
    private func addConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.append(connection)
        let count = connections.count
        connectionsLock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(count)
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.removeAll { $0 === connection }
        let count = connections.count
        connectionsLock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(count)
        }
    }
}


