using System.Drawing;
using System.Runtime.InteropServices;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace MixLink.App;

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
        _appState.OnLog += (msg, level) => { };

        _startStopItem = new ToolStripMenuItem("Start", null, OnStartStop);
        _clientsItem = new ToolStripMenuItem("Clients: 0") { Enabled = false };

        var contextMenu = new ContextMenuStrip();
        contextMenu.Items.Add(_startStopItem);
        contextMenu.Items.Add(_clientsItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add("Show QR Code", null, OnShowQrCode);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add("Exit", null, OnExit);

        _trayIcon = new NotifyIcon
        {
            Icon = CreateTrayIcon(isRunning: false, isActive: false),
            Text = "Cymatics Mix Link",
            ContextMenuStrip = contextMenu,
            Visible = true
        };

        _trayIcon.Click += OnTrayClick;
        _trayIcon.DoubleClick += OnTrayDoubleClick;

        _appState.StartServer();

        // Auto-show the QR popup on launch
        ShowQrPopup();
    }

    private void OnTrayClick(object? sender, EventArgs e)
    {
        if (e is MouseEventArgs me && me.Button == MouseButtons.Left)
            ShowQrPopup();
    }

    private void OnTrayDoubleClick(object? sender, EventArgs e) => ShowQrPopup();

    private void OnStartStop(object? sender, EventArgs e)
    {
        if (_appState.IsServerRunning) _appState.StopServer();
        else _appState.StartServer();
    }

    private void OnShowQrCode(object? sender, EventArgs e) => ShowQrPopup();

    private void ShowQrPopup()
    {
        if (_qrPopup == null || _qrPopup.IsDisposed)
            _qrPopup = new QrPopupForm(_appState);

        if (_qrPopup.Visible)
            _qrPopup.Hide();
        else
            _qrPopup.ShowNearTray();
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

        _startStopItem.Text = isRunning ? "Stop" : "Start";
    }

    private void UpdateClientCount(int count)
    {
        _clientsItem.Text = $"Clients: {count}";
        UpdateTrayIcon();
    }

    private static Icon CreateTrayIcon(bool isRunning, bool isActive)
    {
        const int size = 32;
        using var bitmap = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bitmap);

        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);

        float[] barHeights = [0.35f, 0.7f, 1.0f, 0.7f, 0.35f];
        float barW = 4f;
        float gap = 2.5f;
        float maxH = 22f;
        float totalW = barHeights.Length * barW + (barHeights.Length - 1) * gap;
        float startX = (size - totalW) / 2f;
        float baseY = (size + maxH) / 2f;

        var cyan = Color.FromArgb(0, 212, 255);

        using var cyanBrush = new SolidBrush(cyan);
        using var dimBrush = new SolidBrush(Color.FromArgb(100, 100, 100));

        Brush barBrush = isRunning ? cyanBrush : dimBrush;

        for (int i = 0; i < barHeights.Length; i++)
        {
            float h = maxH * barHeights[i];
            float x = startX + i * (barW + gap);
            float y = baseY - h;
            float cr = barW / 2f;

            using var path = new GraphicsPath();
            path.AddArc(x, y, cr * 2, cr * 2, 180, 90);
            path.AddArc(x + barW - cr * 2, y, cr * 2, cr * 2, 270, 90);
            path.AddArc(x + barW - cr * 2, y + h - cr * 2, cr * 2, cr * 2, 0, 90);
            path.AddArc(x, y + h - cr * 2, cr * 2, cr * 2, 90, 90);
            path.CloseAllFigures();

            g.FillPath(barBrush, path);
        }

        if (!isRunning)
        {
            using var pen = new Pen(Color.FromArgb(90, 90, 90), 2.5f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            g.DrawLine(pen, size * 0.8f, size * 0.75f, size * 0.2f, size * 0.25f);
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
