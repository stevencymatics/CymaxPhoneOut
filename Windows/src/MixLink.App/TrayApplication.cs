using System.Drawing;
using System.Windows.Forms;

namespace MixLink.App;

/// <summary>
/// System tray application with NotifyIcon and context menu.
/// </summary>
public sealed class TrayApplication : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private readonly AppState _appState;
    private QrPopupForm? _qrPopup;
    private readonly ToolStripMenuItem _startStopItem;
    private readonly ToolStripMenuItem _clientsItem;

    public TrayApplication()
    {
        _appState = new AppState();
        _appState.OnStateChanged += UpdateTrayIcon;
        _appState.OnClientCountChanged += count => UpdateClientCount(count);
        _appState.OnLog += (msg, level) =>
        {
            // Could be extended to show notifications for errors
        };

        // Create context menu
        _startStopItem = new ToolStripMenuItem("Start", null, OnStartStop);
        _clientsItem = new ToolStripMenuItem("Clients: 0") { Enabled = false };

        var contextMenu = new ContextMenuStrip();
        contextMenu.Items.Add(_startStopItem);
        contextMenu.Items.Add(_clientsItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add("Show QR Code", null, OnShowQrCode);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add("Exit", null, OnExit);

        // Create tray icon
        _trayIcon = new NotifyIcon
        {
            Icon = CreateTrayIcon(false),
            Text = "Cymatics Link - Click to show QR",
            ContextMenuStrip = contextMenu,
            Visible = true
        };

        _trayIcon.Click += OnTrayClick;
        _trayIcon.DoubleClick += OnTrayDoubleClick;

        // Auto-start the server
        _appState.StartServer();
    }

    private void OnTrayClick(object? sender, EventArgs e)
    {
        // Check if it was a left-click (MouseEventArgs)
        if (e is MouseEventArgs me && me.Button == MouseButtons.Left)
        {
            ShowQrPopup();
        }
    }

    private void OnTrayDoubleClick(object? sender, EventArgs e)
    {
        ShowQrPopup();
    }

    private void OnStartStop(object? sender, EventArgs e)
    {
        if (_appState.IsServerRunning)
        {
            _appState.StopServer();
        }
        else
        {
            _appState.StartServer();
        }
    }

    private void OnShowQrCode(object? sender, EventArgs e)
    {
        ShowQrPopup();
    }

    private void ShowQrPopup()
    {
        if (_qrPopup == null || _qrPopup.IsDisposed)
        {
            _qrPopup = new QrPopupForm(_appState);
        }

        if (_qrPopup.Visible)
        {
            _qrPopup.Hide();
        }
        else
        {
            // Position near tray icon
            var screen = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1920, 1080);
            var popupSize = _qrPopup.Size;

            // Position in bottom-right corner (where tray usually is)
            int x = screen.Right - popupSize.Width - 20;
            int y = screen.Bottom - popupSize.Height - 20;

            _qrPopup.Location = new Point(x, y);
            _qrPopup.Show();
            _qrPopup.Activate();
        }
    }

    private void OnExit(object? sender, EventArgs e)
    {
        _trayIcon.Visible = false;
        _appState.Dispose();
        Application.Exit();
    }

    private void UpdateTrayIcon()
    {
        var isActive = _appState.IsServerRunning && _appState.WebClientsConnected > 0;

        _trayIcon.Icon = CreateTrayIcon(isActive);
        _trayIcon.Text = _appState.IsServerRunning
            ? $"Cymatics Link - {_appState.WebClientsConnected} clients"
            : "Cymatics Link - Stopped";

        _startStopItem.Text = _appState.IsServerRunning ? "Stop" : "Start";
    }

    private void UpdateClientCount(int count)
    {
        _clientsItem.Text = $"Clients: {count}";
        UpdateTrayIcon();
    }

    /// <summary>
    /// Create a simple tray icon programmatically.
    /// Blue circle with play symbol when active, gray when idle.
    /// </summary>
    private static Icon CreateTrayIcon(bool isActive)
    {
        const int size = 32;
        using var bitmap = new Bitmap(size, size);
        using var g = Graphics.FromImage(bitmap);

        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);

        // Draw circle
        var circleColor = isActive ? Color.FromArgb(0, 212, 255) : Color.FromArgb(128, 128, 128);
        using var brush = new SolidBrush(circleColor);
        g.FillEllipse(brush, 2, 2, size - 4, size - 4);

        // Draw play triangle
        var triangleColor = isActive ? Color.White : Color.FromArgb(64, 64, 64);
        using var triangleBrush = new SolidBrush(triangleColor);
        var points = new Point[]
        {
            new(12, 8),
            new(12, 24),
            new(24, 16)
        };
        g.FillPolygon(triangleBrush, points);

        return Icon.FromHandle(bitmap.GetHicon());
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _trayIcon.Dispose();
            _qrPopup?.Dispose();
            _appState.Dispose();
        }
        base.Dispose(disposing);
    }
}
