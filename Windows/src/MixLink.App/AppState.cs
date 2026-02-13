using MixLink.Core.Audio;
using MixLink.Core.Network;
using MixLink.Core.Utilities;
using Microsoft.Win32;
using System.Drawing;

namespace MixLink.App;

/// <summary>
/// Central application state management.
/// Coordinates audio capture, server, and UI state.
/// </summary>
public sealed class AppState : IDisposable
{
    private WasapiLoopbackCapture? _audioCapture;
    private HttpWebSocketServer? _httpServer;
    private System.Threading.Timer? _healthCheckTimer;
    private bool _disposed;

    private const int HttpPort = 19621;
    private int _lastPacketCount;
    private int _stalePacketCheckCount;
    private bool _wasRunningBeforeSleep;

    /// <summary>
    /// Whether the server is currently running.
    /// </summary>
    public bool IsServerRunning { get; private set; }

    /// <summary>
    /// Whether audio capture is active.
    /// </summary>
    public bool IsCaptureActive { get; private set; }

    /// <summary>
    /// Number of connected web clients.
    /// </summary>
    public int WebClientsConnected { get; private set; }

    /// <summary>
    /// Total packets sent since server started.
    /// </summary>
    public int PacketsSent { get; private set; }

    /// <summary>
    /// Current capture status message.
    /// </summary>
    public string CaptureStatus { get; private set; } = "Ready";

    /// <summary>
    /// The web player URL.
    /// </summary>
    public string? WebPlayerUrl { get; private set; }

    /// <summary>
    /// QR code bitmap for the web player URL.
    /// </summary>
    public Bitmap? QrCodeImage { get; private set; }

    /// <summary>
    /// Called when client count changes.
    /// </summary>
    public event Action<int>? OnClientCountChanged;

    /// <summary>
    /// Called when state changes (for UI updates).
    /// </summary>
    public event Action? OnStateChanged;

    /// <summary>
    /// Called for log messages.
    /// </summary>
    public event Action<string, LogLevel>? OnLog;

    public AppState()
    {
        Log("Cymatics Link started", LogLevel.Info);
        Log("Ready to stream system audio to your phone", LogLevel.Info);
        UpdateQrCode();
        SetupPowerEvents();
    }

    private void SetupPowerEvents()
    {
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        switch (e.Mode)
        {
            case PowerModes.Suspend:
                HandleSleep();
                break;
            case PowerModes.Resume:
                HandleWake();
                break;
        }
    }

    private void HandleSleep()
    {
        Log("PC going to sleep...", LogLevel.Info);
        _wasRunningBeforeSleep = IsServerRunning;
        if (IsServerRunning)
        {
            StopServer();
            Log("Servers stopped for sleep", LogLevel.Info);
        }
    }

    private void HandleWake()
    {
        Log("PC woke up", LogLevel.Info);

        if (_wasRunningBeforeSleep)
        {
            // Small delay to let network come back up
            Task.Delay(2000).ContinueWith(_ =>
            {
                Log("Auto-restarting servers...", LogLevel.Info);
                StartServer();
            }, TaskScheduler.Default);
        }
    }

    /// <summary>
    /// Start the server and audio capture.
    /// </summary>
    public void StartServer()
    {
        if (IsServerRunning)
            return;

        Log("Starting server...", LogLevel.Info);

        // Get local IP
        var localIP = NetworkUtils.GetLocalIPAddress();
        if (localIP == null)
        {
            Log("Cannot get local IP address", LogLevel.Error);
            Log("Make sure you're connected to WiFi or Ethernet", LogLevel.Warning);
            return;
        }

        // Get PC name
        var hostName = NetworkUtils.GetHostName();

        // Generate HTML content
        var htmlContent = WebPlayerHtml.GetHtml(HttpPort, localIP, hostName);

        // Start HTTP + WebSocket server
        _httpServer = new HttpWebSocketServer(HttpPort);
        _httpServer.HtmlContent = htmlContent;
        _httpServer.OnClientCountChanged += count =>
        {
            WebClientsConnected = count;
            Log($"Browser clients: {count}", LogLevel.Info);
            OnClientCountChanged?.Invoke(count);
            OnStateChanged?.Invoke();
        };
        _httpServer.OnLog += msg => Log(msg, LogLevel.Debug);

        try
        {
            _httpServer.Start();
        }
        catch (Exception ex)
        {
            Log($"Failed to start server: {ex.Message}", LogLevel.Error);
            _httpServer = null;
            return;
        }

        IsServerRunning = true;
        WebPlayerUrl = $"http://{localIP}:{HttpPort}";

        // Generate QR code
        UpdateQrCode();

        Log("Server started!", LogLevel.Info);
        Log($"URL: {WebPlayerUrl}", LogLevel.Info);

        // Start audio capture
        StartAudioCapture();

        // Start health check timer
        StartHealthCheck();

        OnStateChanged?.Invoke();
    }

    /// <summary>
    /// Stop the server and audio capture.
    /// </summary>
    public void StopServer()
    {
        if (!IsServerRunning)
            return;

        Log("Stopping server...", LogLevel.Info);

        // Stop health check
        StopHealthCheck();

        // Stop audio capture
        StopAudioCapture();

        // Stop server
        _httpServer?.Stop();
        _httpServer?.Dispose();
        _httpServer = null;

        IsServerRunning = false;
        WebClientsConnected = 0;
        PacketsSent = 0;

        Log("Server stopped", LogLevel.Info);
        OnStateChanged?.Invoke();
    }

    private void StartAudioCapture()
    {
        Log("Starting system audio capture...", LogLevel.Info);
        CaptureStatus = "Starting...";

        _audioCapture = new WasapiLoopbackCapture();

        _audioCapture.OnStatusUpdate += status =>
        {
            CaptureStatus = status;
            Log($"Capture: {status}", LogLevel.Info);
            OnStateChanged?.Invoke();
        };

        _audioCapture.OnError += error =>
        {
            CaptureStatus = "Error";
            Log($"Capture error: {error}", LogLevel.Error);
            OnStateChanged?.Invoke();
        };

        _audioCapture.OnAudioPacket += packet =>
        {
            // Broadcast to all clients
            _httpServer?.Broadcast(packet);
            PacketsSent++;
        };

        try
        {
            _audioCapture.Start();
            IsCaptureActive = true;
            CaptureStatus = "Capturing";
            OnStateChanged?.Invoke();
        }
        catch (Exception ex)
        {
            Log($"Failed to start capture: {ex.Message}", LogLevel.Error);
            CaptureStatus = "Failed";
            OnStateChanged?.Invoke();
        }
    }

    private void StopAudioCapture()
    {
        _audioCapture?.Stop();
        _audioCapture?.Dispose();
        _audioCapture = null;
        IsCaptureActive = false;
        CaptureStatus = "Stopped";
    }

    private void StartHealthCheck()
    {
        _lastPacketCount = 0;
        _stalePacketCheckCount = 0;

        _healthCheckTimer = new System.Threading.Timer(
            _ => PerformHealthCheck(),
            null,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromSeconds(5)
        );
    }

    private void StopHealthCheck()
    {
        _healthCheckTimer?.Dispose();
        _healthCheckTimer = null;
    }

    private void PerformHealthCheck()
    {
        if (!IsServerRunning)
            return;

        // Check if audio capture is still working
        if (IsCaptureActive && WebClientsConnected > 0)
        {
            // If we have clients but packets aren't increasing, something's wrong
            if (PacketsSent == _lastPacketCount)
            {
                _stalePacketCheckCount++;

                if (_stalePacketCheckCount >= 3)
                {
                    // 15 seconds of no new packets with active clients - restart
                    Log("Audio capture appears stalled, restarting...", LogLevel.Warning);
                    RestartAudioCapture();
                    _stalePacketCheckCount = 0;
                }
            }
            else
            {
                _stalePacketCheckCount = 0;
            }
            _lastPacketCount = PacketsSent;
        }

        // Check if capture died
        if (!IsCaptureActive && IsServerRunning)
        {
            Log("Audio capture stopped unexpectedly, restarting...", LogLevel.Warning);
            StartAudioCapture();
        }
    }

    private void RestartAudioCapture()
    {
        StopAudioCapture();

        // Brief delay before restarting
        Task.Delay(500).ContinueWith(_ =>
        {
            StartAudioCapture();
        }, TaskScheduler.Default);
    }

    private void UpdateQrCode()
    {
        var url = QrCodeGenerator.GetWebPlayerUrl(HttpPort);
        if (url == null)
        {
            QrCodeImage = null;
            WebPlayerUrl = null;
            return;
        }

        WebPlayerUrl = url;
        QrCodeImage = QrCodeGenerator.Generate(url, 200);
    }

    private void Log(string message, LogLevel level)
    {
        OnLog?.Invoke(message, level);
        Console.WriteLine($"[{level}] {message}");
    }

    public void Dispose()
    {
        if (_disposed)
            return;

        _disposed = true;

        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        StopServer();
        QrCodeImage?.Dispose();
    }
}

/// <summary>
/// Log severity levels.
/// </summary>
public enum LogLevel
{
    Debug,
    Info,
    Warning,
    Error
}
