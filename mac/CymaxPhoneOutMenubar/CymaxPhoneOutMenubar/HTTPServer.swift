//
//  HTTPServer.swift
//  CymaxPhoneOutMenubar
//
//  Simple HTTP server to serve the web audio player
//

import Foundation
import Network

/// Simple HTTP server for serving the web player
class HTTPServer {
    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.cymax.http")
    
    private var isRunning = false
    
    /// The HTML content to serve
    var htmlContent: String = ""
    
    /// WebSocket port for the player to connect to
    var webSocketPort: UInt16 = 19622
    
    init(port: UInt16 = 8080) {
        self.port = port
    }
    
    deinit {
        stop()
    }
    
    /// Start the HTTP server
    func start() {
        guard !isRunning else { return }
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("HTTPServer: Listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    print("HTTPServer: Failed - \(error)")
                    self?.isRunning = false
                case .cancelled:
                    print("HTTPServer: Cancelled")
                    self?.isRunning = false
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: queue)
            isRunning = true
            
        } catch {
            print("HTTPServer: Error starting - \(error)")
        }
    }
    
    /// Stop the server
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                print("HTTPServer: Connection failed - \(error)")
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        
        // Receive HTTP request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("HTTPServer: Receive error - \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
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
            
            print("HTTPServer: \(method) \(path)")
            
            // Handle request
            self?.sendResponse(connection: connection, path: path)
        }
    }
    
    private func sendResponse(connection: NWConnection, path: String) {
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
}


