using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using MixLink.Core.Audio;

namespace MixLink.Core.Network;

/// <summary>
/// Combined HTTP and WebSocket server for serving the web player and streaming audio.
/// Port 19621 - same as Mac for Safari compatibility.
/// </summary>
public sealed class HttpWebSocketServer : IDisposable
{
    private TcpListener? _listener;
    private readonly int _port;
    private bool _isRunning;
    private bool _disposed;
    private CancellationTokenSource? _cts;

    // Connected clients
    private readonly ConcurrentDictionary<string, WebSocketClient> _wsClients = new();
    private readonly ConcurrentDictionary<string, HttpStreamClient> _httpStreamClients = new();

    /// <summary>
    /// The HTML content to serve for the web player.
    /// </summary>
    public string HtmlContent { get; set; } = "";

    /// <summary>
    /// Called when the client count changes.
    /// </summary>
    public event Action<int>? OnClientCountChanged;

    /// <summary>
    /// Called for logging/status messages.
    /// </summary>
    public event Action<string>? OnLog;

    /// <summary>
    /// Number of connected clients (WebSocket + HTTP stream).
    /// </summary>
    public int ConnectedClients => _wsClients.Count + _httpStreamClients.Count;

    /// <summary>
    /// Whether the server is running.
    /// </summary>
    public bool IsRunning => _isRunning;

    /// <summary>
    /// The port the server is listening on.
    /// </summary>
    public int Port => _port;

    public HttpWebSocketServer(int port = 19621)
    {
        _port = port;
    }

    /// <summary>
    /// Start the server.
    /// </summary>
    public void Start()
    {
        if (_isRunning)
            return;

        try
        {
            _cts = new CancellationTokenSource();
            _listener = new TcpListener(IPAddress.Any, _port);
            _listener.Start();
            _isRunning = true;

            Log($"Listening on port {_port} (HTTP + WebSocket)");

            // Start accepting connections
            _ = AcceptConnectionsAsync(_cts.Token);
        }
        catch (Exception ex)
        {
            Log($"Failed to start server: {ex.Message}");
            throw;
        }
    }

    /// <summary>
    /// Stop the server.
    /// </summary>
    public void Stop()
    {
        if (!_isRunning)
            return;

        _isRunning = false;
        _cts?.Cancel();

        try
        {
            _listener?.Stop();
        }
        catch
        {
            // Ignore
        }

        // Close all clients
        foreach (var client in _wsClients.Values)
        {
            try { client.Close(); } catch { }
        }
        foreach (var client in _httpStreamClients.Values)
        {
            try { client.Close(); } catch { }
        }

        _wsClients.Clear();
        _httpStreamClients.Clear();

        OnClientCountChanged?.Invoke(0);
        Log("Server stopped");
    }

    /// <summary>
    /// Broadcast an audio packet to all connected clients.
    /// </summary>
    public void Broadcast(AudioPacket packet)
    {
        var data = packet.ToBytes();

        // WebSocket clients: wrap in binary frame
        var wsFrame = CreateWebSocketFrame(data, 0x02);
        foreach (var kvp in _wsClients)
        {
            try
            {
                kvp.Value.Send(wsFrame);
            }
            catch
            {
                RemoveClient(kvp.Key, isWebSocket: true);
            }
        }

        // HTTP stream clients: send raw bytes
        foreach (var kvp in _httpStreamClients)
        {
            try
            {
                kvp.Value.Send(data);
            }
            catch
            {
                RemoveClient(kvp.Key, isWebSocket: false);
            }
        }
    }

    private async Task AcceptConnectionsAsync(CancellationToken ct)
    {
        while (_isRunning && !ct.IsCancellationRequested)
        {
            try
            {
                var tcpClient = await _listener!.AcceptTcpClientAsync(ct);
                _ = HandleConnectionAsync(tcpClient, ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                if (_isRunning)
                    Log($"Accept error: {ex.Message}");
            }
        }
    }

    private async Task HandleConnectionAsync(TcpClient tcpClient, CancellationToken ct)
    {
        var clientId = Guid.NewGuid().ToString("N")[..8];
        var endpoint = tcpClient.Client.RemoteEndPoint?.ToString() ?? "unknown";

        try
        {
            using var stream = tcpClient.GetStream();
            stream.ReadTimeout = 5000;
            stream.WriteTimeout = 5000;

            // Read HTTP request
            var buffer = new byte[8192];
            var bytesRead = await stream.ReadAsync(buffer, 0, buffer.Length, ct);

            if (bytesRead == 0)
            {
                tcpClient.Close();
                return;
            }

            var request = Encoding.UTF8.GetString(buffer, 0, bytesRead);
            var firstLine = request.Split("\r\n")[0];
            Log($"[{clientId}] {firstLine}");

            // Check if WebSocket upgrade
            if (request.Contains("Upgrade: websocket", StringComparison.OrdinalIgnoreCase))
            {
                await HandleWebSocketUpgrade(tcpClient, stream, clientId, request, ct);
            }
            else
            {
                await HandleHttpRequest(tcpClient, stream, clientId, request, ct);
            }
        }
        catch (Exception ex)
        {
            Log($"[{clientId}] Error: {ex.Message}");
            try { tcpClient.Close(); } catch { }
        }
    }

    private async Task HandleHttpRequest(TcpClient tcpClient, NetworkStream stream, string clientId, string request, CancellationToken ct)
    {
        var lines = request.Split("\r\n");
        var requestLine = lines[0].Split(' ');
        if (requestLine.Length < 2)
        {
            tcpClient.Close();
            return;
        }

        var path = requestLine[1];

        switch (path)
        {
            case "/":
            case "/index.html":
                await SendHttpResponse(stream, "text/html; charset=utf-8", HtmlContent, ct);
                tcpClient.Close();
                break;

            case "/health":
                await SendHttpResponse(stream, "application/json", "{\"status\":\"ok\"}", ct);
                tcpClient.Close();
                break;

            case "/stream":
                await HandleHttpStream(tcpClient, stream, clientId, ct);
                break;

            default:
                await SendHttpResponse(stream, "text/html", "<h1>404 Not Found</h1>", ct, 404);
                tcpClient.Close();
                break;
        }
    }

    private async Task SendHttpResponse(NetworkStream stream, string contentType, string body, CancellationToken ct, int statusCode = 200)
    {
        var statusText = statusCode == 200 ? "OK" : "Not Found";
        var bodyBytes = Encoding.UTF8.GetBytes(body);

        var response = $"HTTP/1.1 {statusCode} {statusText}\r\n" +
                       $"Content-Type: {contentType}\r\n" +
                       $"Content-Length: {bodyBytes.Length}\r\n" +
                       "Connection: close\r\n" +
                       "Access-Control-Allow-Origin: *\r\n" +
                       "Cache-Control: no-cache\r\n" +
                       "\r\n";

        var headerBytes = Encoding.UTF8.GetBytes(response);
        await stream.WriteAsync(headerBytes, ct);
        await stream.WriteAsync(bodyBytes, ct);
        await stream.FlushAsync(ct);
    }

    private async Task HandleHttpStream(TcpClient tcpClient, NetworkStream stream, string clientId, CancellationToken ct)
    {
        Log($"[{clientId}] HTTP stream started");

        // Send streaming headers
        var headers = "HTTP/1.1 200 OK\r\n" +
                      "Content-Type: application/octet-stream\r\n" +
                      "Cache-Control: no-cache, no-store\r\n" +
                      "Connection: keep-alive\r\n" +
                      "Access-Control-Allow-Origin: *\r\n" +
                      "X-Content-Type-Options: nosniff\r\n" +
                      "\r\n";

        var headerBytes = Encoding.UTF8.GetBytes(headers);
        await stream.WriteAsync(headerBytes, ct);
        await stream.FlushAsync(ct);

        // Add to stream clients
        var client = new HttpStreamClient(tcpClient, stream);
        _httpStreamClients[clientId] = client;
        NotifyClientCountChanged();

        // Keep connection alive until closed
        try
        {
            while (_isRunning && tcpClient.Connected && !ct.IsCancellationRequested)
            {
                await Task.Delay(1000, ct);
            }
        }
        catch { }

        RemoveClient(clientId, isWebSocket: false);
    }

    private async Task HandleWebSocketUpgrade(TcpClient tcpClient, NetworkStream stream, string clientId, string request, CancellationToken ct)
    {
        // Parse Sec-WebSocket-Key
        var keyLine = request.Split("\r\n")
            .FirstOrDefault(l => l.StartsWith("Sec-WebSocket-Key:", StringComparison.OrdinalIgnoreCase));

        if (keyLine == null)
        {
            Log($"[{clientId}] Missing Sec-WebSocket-Key");
            tcpClient.Close();
            return;
        }

        var key = keyLine.Split(':')[1].Trim();
        var acceptKey = GenerateWebSocketAcceptKey(key);

        // Send upgrade response
        var response = "HTTP/1.1 101 Switching Protocols\r\n" +
                       "Upgrade: websocket\r\n" +
                       "Connection: Upgrade\r\n" +
                       $"Sec-WebSocket-Accept: {acceptKey}\r\n" +
                       "\r\n";

        var responseBytes = Encoding.UTF8.GetBytes(response);
        await stream.WriteAsync(responseBytes, ct);
        await stream.FlushAsync(ct);

        Log($"[{clientId}] WebSocket upgrade complete");

        // Add to WebSocket clients
        var client = new WebSocketClient(tcpClient, stream);
        _wsClients[clientId] = client;
        NotifyClientCountChanged();

        // Handle WebSocket messages
        await ReceiveWebSocketMessages(client, clientId, ct);
    }

    private async Task ReceiveWebSocketMessages(WebSocketClient client, string clientId, CancellationToken ct)
    {
        var buffer = new byte[65536];

        try
        {
            while (_isRunning && client.IsConnected && !ct.IsCancellationRequested)
            {
                int bytesRead;
                try
                {
                    bytesRead = await client.Stream.ReadAsync(buffer, 0, buffer.Length, ct);
                }
                catch
                {
                    break;
                }

                if (bytesRead < 2)
                    break;

                var opcode = buffer[0] & 0x0F;

                switch (opcode)
                {
                    case 0x08: // Close
                        Log($"[{clientId}] WebSocket close received");
                        goto done;

                    case 0x09: // Ping
                        await SendPong(client);
                        break;

                    case 0x0A: // Pong
                        break;

                    default:
                        break;
                }
            }
        }
        catch { }

    done:
        RemoveClient(clientId, isWebSocket: true);
    }

    private async Task SendPong(WebSocketClient client)
    {
        var pong = new byte[] { 0x8A, 0x00 }; // FIN + Pong, no payload
        try
        {
            await client.Stream.WriteAsync(pong);
        }
        catch { }
    }

    private static string GenerateWebSocketAcceptKey(string key)
    {
        const string magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var combined = key + magicString;
        var hash = SHA1.HashData(Encoding.UTF8.GetBytes(combined));
        return Convert.ToBase64String(hash);
    }

    private static byte[] CreateWebSocketFrame(byte[] data, byte opcode)
    {
        var length = data.Length;

        byte[] frame;
        int headerSize;

        if (length < 126)
        {
            headerSize = 2;
            frame = new byte[headerSize + length];
            frame[0] = (byte)(0x80 | opcode); // FIN + opcode
            frame[1] = (byte)length;
        }
        else if (length < 65536)
        {
            headerSize = 4;
            frame = new byte[headerSize + length];
            frame[0] = (byte)(0x80 | opcode);
            frame[1] = 126;
            frame[2] = (byte)((length >> 8) & 0xFF);
            frame[3] = (byte)(length & 0xFF);
        }
        else
        {
            headerSize = 10;
            frame = new byte[headerSize + length];
            frame[0] = (byte)(0x80 | opcode);
            frame[1] = 127;
            for (int i = 0; i < 8; i++)
            {
                frame[2 + i] = (byte)((length >> ((7 - i) * 8)) & 0xFF);
            }
        }

        Array.Copy(data, 0, frame, headerSize, length);
        return frame;
    }

    private void RemoveClient(string clientId, bool isWebSocket)
    {
        if (isWebSocket)
        {
            if (_wsClients.TryRemove(clientId, out var client))
            {
                try { client.Close(); } catch { }
                Log($"[{clientId}] WebSocket client removed");
            }
        }
        else
        {
            if (_httpStreamClients.TryRemove(clientId, out var client))
            {
                try { client.Close(); } catch { }
                Log($"[{clientId}] HTTP stream client removed");
            }
        }

        NotifyClientCountChanged();
    }

    private void NotifyClientCountChanged()
    {
        OnClientCountChanged?.Invoke(ConnectedClients);
    }

    private void Log(string message)
    {
        OnLog?.Invoke(message);
    }

    public void Dispose()
    {
        if (_disposed)
            return;

        _disposed = true;
        Stop();
        _cts?.Dispose();
    }

    /// <summary>
    /// WebSocket client connection wrapper.
    /// </summary>
    private sealed class WebSocketClient
    {
        public TcpClient TcpClient { get; }
        public NetworkStream Stream { get; }
        public bool IsConnected => TcpClient.Connected;

        private readonly object _sendLock = new();

        public WebSocketClient(TcpClient tcpClient, NetworkStream stream)
        {
            TcpClient = tcpClient;
            Stream = stream;
        }

        public void Send(byte[] data)
        {
            lock (_sendLock)
            {
                Stream.Write(data, 0, data.Length);
            }
        }

        public void Close()
        {
            try
            {
                Stream.Close();
                TcpClient.Close();
            }
            catch { }
        }
    }

    /// <summary>
    /// HTTP stream client connection wrapper.
    /// </summary>
    private sealed class HttpStreamClient
    {
        public TcpClient TcpClient { get; }
        public NetworkStream Stream { get; }
        public bool IsConnected => TcpClient.Connected;

        private readonly object _sendLock = new();

        public HttpStreamClient(TcpClient tcpClient, NetworkStream stream)
        {
            TcpClient = tcpClient;
            Stream = stream;
        }

        public void Send(byte[] data)
        {
            lock (_sendLock)
            {
                Stream.Write(data, 0, data.Length);
                Stream.Flush();
            }
        }

        public void Close()
        {
            try
            {
                Stream.Close();
                TcpClient.Close();
            }
            catch { }
        }
    }
}
