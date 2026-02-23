using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class QrPopupForm : Form
{
    private readonly AppState _appState;
    private readonly PictureBox _qrPictureBox;
    private readonly Label _urlLabel;
    private readonly Label _phonesValue;
    private readonly Label _audioIcon;
    private readonly Label _audioLabel;
    private readonly SignalBarsPanel _signalPanel;
    private readonly MixLinkButton _startStopBtn;
    private readonly Label _scanHint;

    private const int W = 320;

    public QrPopupForm(AppState appState)
    {
        _appState = appState;

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ClientSize = new Size(W, 520);
        BackColor = MixLinkTheme.Background;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;

        Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, ClientSize.Width + 1, ClientSize.Height + 1, 16, 16));

        int pad = 24;
        int cw = W - pad * 2;

        var close = new TrafficLightButton(TrafficLightKind.Close) { Location = new Point(12, 12) };
        close.Click += (_, _) => Hide();
        var minimize = new TrafficLightButton(TrafficLightKind.Minimize) { Location = new Point(32, 12) };
        minimize.Click += (_, _) => Hide();
        Controls.Add(close);
        Controls.Add(minimize);

        var menu = new ContextMenuStrip();
        menu.Items.Add("Sign Out", null, (_, _) => { LicenseService.ClearCredentials(); Application.Exit(); });
        menu.Items.Add("Help", null, (_, _) => { try { Process.Start(new ProcessStartInfo("mailto:support@cymatics.fm") { UseShellExecute = true }); } catch { } });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Application.Exit());
        var hamburger = new HamburgerButton { Location = new Point(W - 12 - 28, 8) };
        hamburger.Click += (_, _) => menu.Show(hamburger, new Point(0, hamburger.Height));
        Controls.Add(hamburger);

        int y = 36;

        var wordmark = new WordmarkPanel { Location = new Point(pad, y), Size = new Size(cw, 14) };
        Controls.Add(wordmark);
        y += 16;

        var title = new Label
        {
            Text = "MIX LINK",
            Font = new Font("Segoe UI", 20, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(cw, 32),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        Controls.Add(title);
        y += 42;

        int qrSize = 160;
        _qrPictureBox = new PictureBox
        {
            Size = new Size(qrSize, qrSize),
            Location = new Point((W - qrSize) / 2, y),
            SizeMode = PictureBoxSizeMode.Zoom,
            BackColor = Color.White
        };
        Controls.Add(_qrPictureBox);
        y += qrSize + 10;

        _scanHint = new Label
        {
            Text = "Scan with your phone",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(cw, 16),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        Controls.Add(_scanHint);
        y += 20;

        _urlLabel = new Label
        {
            Font = new Font("Consolas", 9),
            ForeColor = MixLinkTheme.Cyan,
            AutoSize = false,
            Size = new Size(cw, 16),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y),
            Cursor = Cursors.Hand
        };
        _urlLabel.Click += OnUrlClick;
        Controls.Add(_urlLabel);
        y += 26;

        var statusPanel = new Panel
        {
            Location = new Point(pad, y),
            Size = new Size(cw, 50),
            BackColor = Color.FromArgb(28, 28, 28)
        };
        Controls.Add(statusPanel);
        int colW = cw / 3;

        _phonesValue = new Label { Text = "0", Font = new Font("Segoe UI", 16, FontStyle.Bold), ForeColor = Color.Gray, AutoSize = false, Size = new Size(colW, 26), TextAlign = ContentAlignment.MiddleCenter, Location = new Point(0, 2) };
        var phonesLbl = new Label { Text = "Phones", Font = new Font("Segoe UI", 8), ForeColor = Color.Gray, AutoSize = false, Size = new Size(colW, 14), TextAlign = ContentAlignment.MiddleCenter, Location = new Point(0, 30) };
        statusPanel.Controls.Add(_phonesValue);
        statusPanel.Controls.Add(phonesLbl);

        _audioIcon = new Label { Text = "\u266B", Font = new Font("Segoe UI", 14), ForeColor = Color.Gray, AutoSize = false, Size = new Size(colW, 26), TextAlign = ContentAlignment.MiddleCenter, Location = new Point(colW, 2) };
        _audioLabel = new Label { Text = "Idle", Font = new Font("Segoe UI", 8), ForeColor = Color.Gray, AutoSize = false, Size = new Size(colW, 14), TextAlign = ContentAlignment.MiddleCenter, Location = new Point(colW, 30) };
        statusPanel.Controls.Add(_audioIcon);
        statusPanel.Controls.Add(_audioLabel);

        _signalPanel = new SignalBarsPanel { Location = new Point(colW * 2 + (colW - 18) / 2, 4), Size = new Size(18, 18) };
        var signalLbl = new Label { Text = "Signal", Font = new Font("Segoe UI", 8), ForeColor = Color.Gray, AutoSize = false, Size = new Size(colW, 14), TextAlign = ContentAlignment.MiddleCenter, Location = new Point(colW * 2, 30) };
        statusPanel.Controls.Add(_signalPanel);
        statusPanel.Controls.Add(signalLbl);
        y += 60;

        _startStopBtn = new MixLinkButton
        {
            Text = "Start",
            Font = new Font("Segoe UI", 13, FontStyle.Bold),
            Size = new Size(cw, 40),
            Location = new Point(pad, y)
        };
        _startStopBtn.Click += (_, _) =>
        {
            if (_appState.IsServerRunning) _appState.StopServer();
            else _appState.StartServer();
        };
        Controls.Add(_startStopBtn);

        _appState.OnStateChanged += UpdateDisplay;
        UpdateDisplay();

        Deactivate += (_, _) => Hide();
        KeyPreview = true;
        KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) Hide(); };
    }

    public void ShowNearTray()
    {
        var screen = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1920, 1080);
        int x = screen.Right - Size.Width - 16;
        int y = screen.Bottom - Size.Height - 16;
        Location = new Point(x, y);
        Show();
        Activate();
    }

    private void UpdateDisplay()
    {
        if (InvokeRequired) { Invoke(UpdateDisplay); return; }

        _qrPictureBox.Image = _appState.QrCodeImage;
        _urlLabel.Text = _appState.WebPlayerUrl ?? "";
        _scanHint.Visible = _appState.IsServerRunning;
        _urlLabel.Visible = _appState.IsServerRunning;

        int clients = _appState.WebClientsConnected;
        _phonesValue.Text = clients.ToString();
        _phonesValue.ForeColor = clients > 0 ? MixLinkTheme.Cyan : Color.Gray;

        bool capturing = _appState.IsCaptureActive;
        _audioIcon.ForeColor = capturing ? MixLinkTheme.Cyan : Color.Gray;
        _audioLabel.Text = capturing ? "Streaming" : "Idle";

        _signalPanel.Active = _appState.IsServerRunning && clients > 0 && capturing;
        _signalPanel.Invalidate();

        _startStopBtn.UseDangerStyle = _appState.IsServerRunning;
        _startStopBtn.Text = _appState.IsServerRunning ? "Stop" : "Start";
        _startStopBtn.ForeColor = _appState.IsServerRunning ? Color.White : Color.Black;
        _startStopBtn.Invalidate();
    }

    private void OnUrlClick(object? sender, EventArgs e)
    {
        if (string.IsNullOrEmpty(_appState.WebPlayerUrl)) return;
        try
        {
            Clipboard.SetText(_appState.WebPlayerUrl);
            var orig = _urlLabel.Text;
            _urlLabel.Text = "Copied!";
            _urlLabel.ForeColor = Color.FromArgb(74, 222, 128);
            Task.Delay(1500).ContinueWith(_ =>
            {
                if (!IsDisposed) Invoke(() => { _urlLabel.Text = orig; _urlLabel.ForeColor = MixLinkTheme.Cyan; });
            });
        }
        catch { }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _appState.OnStateChanged -= UpdateDisplay;
        base.Dispose(disposing);
    }

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int cx, int cy);

    private sealed class WordmarkPanel : Control
    {
        public WordmarkPanel() => SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);
            CymaticsWordmark.Draw(e.Graphics, new RectangleF(0, 0, Width, Height), Color.White);
        }
    }

    internal sealed class SignalBarsPanel : Control
    {
        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public bool Active { get; set; }

        public SignalBarsPanel() => SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);
            var c = Active ? MixLinkTheme.Cyan : Color.FromArgb(77, Color.Gray);
            int[] hs = [5, 10, 16];
            int bw = 4, gap = 2, x = 0;
            for (int i = 0; i < 3; i++)
            {
                using var b = new SolidBrush(c);
                MixLinkPaint.FillRoundedRect(e.Graphics, b, new RectangleF(x, Height - hs[i], bw, hs[i]), 1f);
                x += bw + gap;
            }
        }
    }
}
