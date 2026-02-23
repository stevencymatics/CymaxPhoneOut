using System.Drawing;
using System.Runtime.InteropServices;
using System.Drawing.Drawing2D;
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
            Icon = CreateTrayIcon(isRunning: false, isActive: false),
            Text = "Cymatics Mix Link - Click to show QR",
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
        var isRunning = _appState.IsServerRunning;
        var isActive = isRunning && _appState.WebClientsConnected > 0;

        _trayIcon.Icon = CreateTrayIcon(isRunning: isRunning, isActive: isActive);
        _trayIcon.Text = isRunning
            ? $"Cymatics Mix Link - {_appState.WebClientsConnected} phones"
            : "Cymatics Mix Link - Stopped";

        _startStopItem.Text = _appState.IsServerRunning ? "Stop" : "Start";
    }

    private void UpdateClientCount(int count)
    {
        _clientsItem.Text = $"Clients: {count}";
        UpdateTrayIcon();
    }

    /// <summary>
    /// Create a simple tray icon programmatically.
    /// 5-bar waveform icon (matching macOS menubar icon).
    /// </summary>
    private static Icon CreateTrayIcon(bool isRunning, bool isActive)
    {
        const int size = 32;
        using var bitmap = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bitmap);

        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);

        // Bars match mac proportions: [0.35, 0.7, 1.0, 0.7, 0.35]
        float[] barHeights = [0.35f, 0.7f, 1.0f, 0.7f, 0.35f];
        float barW = 2f;
        float gap = 2f;
        float maxH = 16f;
        float totalW = barHeights.Length * barW + (barHeights.Length - 1) * gap;
        float startX = (size - totalW) / 2f;
        float baseY = (size - maxH) / 2f + maxH;

        var cyan = Color.FromArgb(0, 212, 255); // #00D4FF
        var teal = Color.FromArgb(0, 255, 212); // #00FFD4
        var gray = Color.FromArgb(128, 128, 128);
        var dimGray = Color.FromArgb(90, 90, 90);

        using var activeBrush = new LinearGradientBrush(
            new RectangleF(0, 0, size, size),
            cyan,
            teal,
            LinearGradientMode.ForwardDiagonal
        );
        using var idleBrush = new SolidBrush(isRunning ? Color.FromArgb(190, cyan) : gray);

        for (int i = 0; i < barHeights.Length; i++)
        {
            float h = maxH * barHeights[i];
            float x = startX + i * (barW + gap);
            float y = baseY - h;
            float cr = 1f;

            using var path = new GraphicsPath();
            path.AddArc(x, y, cr * 2, cr * 2, 180, 90);
            path.AddArc(x + barW - cr * 2, y, cr * 2, cr * 2, 270, 90);
            path.AddArc(x + barW - cr * 2, y + h - cr * 2, cr * 2, cr * 2, 0, 90);
            path.AddArc(x, y + h - cr * 2, cr * 2, cr * 2, 90, 90);
            path.CloseAllFigures();

            if (isActive)
                g.FillPath(activeBrush, path);
            else
                g.FillPath(idleBrush, path);
        }

        // Slash when stopped (mac "slashed" state)
        if (!isRunning)
        {
            using var pen = new Pen(dimGray, 2f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            g.DrawLine(pen, (size * 0.78f), (size * 0.72f), (size * 0.22f), (size * 0.28f));
        }

        IntPtr hIcon = bitmap.GetHicon();
        try
        {
            using var tmp = Icon.FromHandle(hIcon);
            return (Icon)tmp.Clone();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

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
