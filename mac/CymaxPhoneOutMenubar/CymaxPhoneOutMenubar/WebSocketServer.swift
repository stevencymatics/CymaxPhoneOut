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
    private var connectionAttempts = 0
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] WS: \(message)")
    }
    
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
                    self?.log("✅ LISTENING on port \(self?.port ?? 0)")
                case .waiting(let error):
                    self?.log("⏳ Waiting - \(error)")
                case .failed(let error):
                    self?.log("❌ FAILED - \(error)")
                    self?.isRunning = false
                case .cancelled:
                    self?.log("🛑 Cancelled")
                    self?.isRunning = false
                case .setup:
                    self?.log("🔧 Setting up...")
                @unknown default:
                    self?.log("Unknown state: \(state)")
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.connectionAttempts += 1
                self?.log(">>> INCOMING #\(self?.connectionAttempts ?? 0) from \(connection.endpoint)")
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
        let endpoint = "\(connection.endpoint)"
        log("📥 handleNewConnection: \(endpoint)")
        log("   Initial state: \(connection.state)")
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .setup:
                self?.log("   [\(endpoint)] State: setup")
            case .preparing:
                self?.log("   [\(endpoint)] State: preparing (WebSocket handshake...)")
            case .ready:
                self?.log("✅ [\(endpoint)] State: READY - Client connected!")
                self?.addConnection(connection)
            case .waiting(let error):
                self?.log("⏳ [\(endpoint)] State: waiting - \(error)")
            case .failed(let error):
                self?.log("❌ [\(endpoint)] State: FAILED - \(error)")
                self?.removeConnection(connection)
            case .cancelled:
                self?.log("🛑 [\(endpoint)] State: cancelled - Client disconnected")
                self?.removeConnection(connection)
            @unknown default:
                self?.log("   [\(endpoint)] State: unknown (\(state))")
            }
        }
        
        log("   Starting connection...")
        connection.start(queue: queue)
        
        // Start receiving (for pings/pongs and close frames)
        receiveMessage(on: connection)
    }
    
    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            let endpoint = "\(connection.endpoint)"
            
            if let error = error {
                self?.log("📨 [\(endpoint)] Receive error: \(error)")
                return
            }
            
            // Handle WebSocket control frames (pings are auto-replied)
            if let context = context,
               let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch metadata.opcode {
                case .close:
                    self?.log("📨 [\(endpoint)] Received CLOSE frame")
                    connection.cancel()
                    return
                case .ping:
                    self?.log("📨 [\(endpoint)] Received PING (auto-reply)")
                case .pong:
                    self?.log("📨 [\(endpoint)] Received PONG")
                case .text:
                    if let data = data, let text = String(data: data, encoding: .utf8) {
                        self?.log("📨 [\(endpoint)] Received TEXT: \(text.prefix(100))")
                    }
                case .binary:
                    self?.log("📨 [\(endpoint)] Received BINARY (\(data?.count ?? 0) bytes)")
                default:
                    self?.log("📨 [\(endpoint)] Received opcode: \(metadata.opcode)")
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
        
        log("➕ Added connection. Total clients: \(count)")
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(count)
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        let beforeCount = connections.count
        connections.removeAll { $0 === connection }
        let afterCount = connections.count
        connectionsLock.unlock()
        
        if beforeCount != afterCount {
            log("➖ Removed connection. Total clients: \(afterCount)")
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(afterCount)
        }
    }
}


