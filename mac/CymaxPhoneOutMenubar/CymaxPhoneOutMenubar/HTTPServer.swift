//
//  HTTPServer.swift
//  CymaxPhoneOutMenubar
//
//  Combined HTTP + WebSocket server (same port for Safari compatibility)
//

import Foundation
import Network
import CommonCrypto

/// Combined HTTP and WebSocket server for serving the web player and streaming audio
class HTTPServer {
    private var listener: NWListener?
    private let requestedPort: UInt16
    private(set) var actualPort: UInt16 = 0
    private let queue = DispatchQueue(label: "com.cymax.http")

    private var isRunning = false
    
    // WebSocket connections
    private var wsConnections: [NWConnection] = []
    private let wsLock = NSLock()
    
    /// The HTML content to serve
    var htmlContent: String = ""
    
    /// WebSocket port for the player to connect to (same as HTTP now)
    var webSocketPort: UInt16 { actualPort }
    
    /// Callback when client count changes
    var onClientCountChanged: ((Int) -> Void)?
    
    /// Number of connected WebSocket clients
    var connectedClients: Int {
        wsLock.lock()
        defer { wsLock.unlock() }
        return wsConnections.count
    }
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] HTTP/WS: \(message)")
    }
    
    init(port: UInt16 = 19621) {
        self.requestedPort = port
    }
    
    deinit {
        stop()
    }
    
    /// Start the HTTP server, trying ports from requestedPort to requestedPort+9
    func start() {
        guard !isRunning else { return }

        for portOffset in 0..<10 {
            let tryPort = requestedPort + UInt16(portOffset)
            if tryBind(port: tryPort) {
                return
            }
        }
        log("Error starting - all ports \(requestedPort)-\(requestedPort + 9) in use")
    }

    /// Attempt to bind to a specific port. Returns true on success.
    private func tryBind(port: UInt16) -> Bool {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            newListener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
        } catch {
            log("Cannot create listener on port \(port): \(error)")
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        var bindSucceeded = false

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                bindSucceeded = true
                semaphore.signal()
            case .failed:
                bindSucceeded = false
                semaphore.signal()
            case .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener.start(queue: queue)

        // Wait up to 2 seconds for bind result
        _ = semaphore.wait(timeout: .now() + 2.0)

        if bindSucceeded {
            listener = newListener
            actualPort = port
            isRunning = true

            // Set the permanent state handler now that we're bound
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.log("Listening on port \(port) (HTTP + WebSocket)")
                case .failed(let error):
                    self?.log("Failed - \(error)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }

            log("Listening on port \(port) (HTTP + WebSocket)")
            return true
        } else {
            newListener.cancel()
            log("Port \(port) unavailable, trying next...")
            return false
        }
    }
    
    /// Stop the server
    func stop() {
        listener?.cancel()
        listener = nil
        
        wsLock.lock()
        for conn in wsConnections {
            conn.cancel()
        }
        wsConnections.removeAll()
        wsLock.unlock()
        
        isRunning = false
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(0)
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let endpoint = "\(connection.endpoint)"
        log(">>> NEW CONNECTION from \(endpoint)")
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.log("    [\(endpoint)] ready")
            case .preparing:
                self?.log("    [\(endpoint)] preparing")
            case .failed(let error):
                self?.log("    [\(endpoint)] FAILED - \(error)")
                self?.removeWSConnection(connection)
            case .cancelled:
                self?.log("    [\(endpoint)] cancelled")
                self?.removeWSConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        // Receive HTTP request (or WebSocket upgrade)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if let error = error {
                self?.log("    [\(endpoint)] Receive error - \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                self?.log("    [\(endpoint)] No data or invalid UTF8")
                connection.cancel()
                return
            }
            
            // Log first line of request
            let firstLine = request.components(separatedBy: "\r\n").first ?? "?"
            self?.log("    [\(endpoint)] Request: \(firstLine)")
            
            // Check if this is a WebSocket upgrade request
            let isWebSocket = request.lowercased().contains("upgrade: websocket")
            self?.log("    [\(endpoint)] Is WebSocket: \(isWebSocket)")
            
            if isWebSocket {
                self?.handleWebSocketUpgrade(connection: connection, request: request)
            } else {
                self?.handleHTTPRequest(connection: connection, request: request)
            }
        }
    }
    
    private func handleHTTPRequest(connection: NWConnection, request: String) {
        // Parse request line
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            return
        }
        
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        
        log("HTTP \(method) \(path)")
        
        // Handle request
        sendHTTPResponse(connection: connection, path: path)
    }
    
    private func handleWebSocketUpgrade(connection: NWConnection, request: String) {
        log(">>> WebSocket upgrade request from \(connection.endpoint)")
        
        // Parse Sec-WebSocket-Key
        guard let keyLine = request.components(separatedBy: "\r\n").first(where: { 
            $0.lowercased().hasPrefix("sec-websocket-key:") 
        }) else {
            log("❌ Missing Sec-WebSocket-Key")
            connection.cancel()
            return
        }
        
        let key = keyLine.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        
        // Generate accept key (RFC 6455)
        let acceptKey = generateWebSocketAcceptKey(key: key)
        
        // Send upgrade response
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r
        
        """
        
        let responseData = Data(response.utf8)
        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.log("❌ WebSocket upgrade send error: \(error)")
                connection.cancel()
                return
            }
            
            self?.log("✅ WebSocket upgrade complete for \(connection.endpoint)")
            self?.addWSConnection(connection)
            self?.receiveWebSocketMessages(on: connection)
        })
    }
    
    private func generateWebSocketAcceptKey(key: String) -> String {
        let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magicString
        
        // SHA-1 hash
        let data = Data(combined.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        
        // Base64 encode
        return Data(hash).base64EncodedString()
    }
    
    private func createWebSocketFrame(data: Data, opcode: UInt8) -> Data {
        var frame = Data()
        
        // First byte: FIN + opcode
        frame.append(0x80 | opcode)
        
        // Length (no masking for server->client)
        let length = data.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length < 65536 {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for i in (0..<8).reversed() {
                frame.append(UInt8((length >> (i * 8)) & 0xFF))
            }
        }
        
        // Payload
        frame.append(data)
        
        return frame
    }
    
    private func receiveWebSocketMessages(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                self?.log("WebSocket receive error: \(error)")
                self?.removeWSConnection(connection)
                return
            }
            
            guard let data = data, data.count >= 2 else {
                if isComplete {
                    self?.removeWSConnection(connection)
                }
                return
            }
            
            // Parse WebSocket frame
            let firstByte = data[0]
            let opcode = firstByte & 0x0F
            
            switch opcode {
            case 0x08: // Close
                self?.log("WebSocket close frame received")
                connection.cancel()
                return
            case 0x09: // Ping
                self?.sendPong(on: connection, data: data)
            case 0x0A: // Pong
                break
            default:
                break
            }
            
            // Continue receiving
            self?.receiveWebSocketMessages(on: connection)
        }
    }
    
    private func sendPong(on connection: NWConnection, data: Data) {
        // Echo back as pong
        var pong = Data()
        pong.append(0x8A) // FIN + Pong
        pong.append(0x00) // No payload
        connection.send(content: pong, completion: .idempotent)
    }
    
    private func addWSConnection(_ connection: NWConnection) {
        wsLock.lock()
        wsConnections.append(connection)
        let count = wsConnections.count
        wsLock.unlock()
        
        log("➕ WebSocket client added. Total: \(count)")
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(count)
        }
    }
    
    private func removeWSConnection(_ connection: NWConnection) {
        wsLock.lock()
        let before = wsConnections.count
        wsConnections.removeAll { $0 === connection }
        let after = wsConnections.count
        wsLock.unlock()
        
        if before != after {
            log("➖ WebSocket client removed. Total: \(after)")
            
            DispatchQueue.main.async { [weak self] in
                self?.onClientCountChanged?(after)
            }
        }
    }
    
    private func sendHTTPResponse(connection: NWConnection, path: String) {
        let response: String
        let contentType: String
        let body: String
        
        switch path {
        case "/", "/index.html":
            contentType = "text/html; charset=utf-8"
            body = htmlContent
            
        case "/health":
            contentType = "application/json"
            body = "{\"status\":\"ok\"}"
            
        case "/stream":
            // HTTP streaming endpoint for Safari fallback
            handleHTTPStream(connection: connection)
            return
            
        default:
            // 404 Not Found
            let notFoundBody = "<html><body><h1>404 Not Found</h1></body></html>"
            response = """
            HTTP/1.1 404 Not Found\r
            Content-Type: text/html\r
            Content-Length: \(notFoundBody.utf8.count)\r
            Connection: close\r
            \r
            \(notFoundBody)
            """
            sendAndClose(connection: connection, response: response)
            return
        }
        
        response = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: no-cache\r
        \r
        \(body)
        """
        
        sendAndClose(connection: connection, response: response)
    }
    
    private func sendAndClose(connection: NWConnection, response: String) {
        let data = Data(response.utf8)
        
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("HTTPServer: Send error - \(error)")
            }
            connection.cancel()
        })
    }
    
    // MARK: - HTTP Streaming (Safari fallback)
    
    private var httpStreamConnections: [NWConnection] = []
    private let httpStreamLock = NSLock()
    
    private func handleHTTPStream(connection: NWConnection) {
        log(">>> HTTP STREAM request from \(connection.endpoint)")
        
        // Send streaming headers - NO chunked encoding, just raw bytes
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: application/octet-stream\r
        Cache-Control: no-cache, no-store\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        X-Content-Type-Options: nosniff\r
        \r
        
        """
        
        let headerData = Data(headers.utf8)
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.log("HTTP stream header error: \(error)")
                connection.cancel()
                return
            }
            
            self?.log("✅ HTTP stream started for \(connection.endpoint)")
            self?.addHTTPStreamConnection(connection)
        })
    }
    
    private func addHTTPStreamConnection(_ connection: NWConnection) {
        httpStreamLock.lock()
        httpStreamConnections.append(connection)
        let count = httpStreamConnections.count + wsConnections.count
        httpStreamLock.unlock()
        
        log("➕ HTTP stream client added. Total clients: \(count)")
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(count)
        }
    }
    
    private func removeHTTPStreamConnection(_ connection: NWConnection) {
        httpStreamLock.lock()
        httpStreamConnections.removeAll { $0 === connection }
        let count = httpStreamConnections.count + wsConnections.count
        httpStreamLock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.onClientCountChanged?(count)
        }
    }
    
    /// Broadcast audio to both WebSocket and HTTP stream clients
    func broadcast(_ packet: AudioPacket) {
        let data = packet.toWebSocketData()
        
        // WebSocket clients
        wsLock.lock()
        let wsConns = wsConnections
        wsLock.unlock()
        
        if !wsConns.isEmpty {
            let frame = createWebSocketFrame(data: data, opcode: 0x02)
            for conn in wsConns {
                conn.send(content: frame, completion: .contentProcessed { error in
                    if let error = error {
                        print("WebSocket send error: \(error)")
                    }
                })
            }
        }
        
        // HTTP stream clients (raw binary data)
        httpStreamLock.lock()
        let httpConns = httpStreamConnections
        httpStreamLock.unlock()
        
        if !httpConns.isEmpty {
            // Send raw audio packet data directly (no chunking overhead)
            for conn in httpConns {
                conn.send(content: data, completion: .contentProcessed { [weak self] error in
                    if error != nil {
                        self?.removeHTTPStreamConnection(conn)
                    }
                })
            }
        }
    }
}
