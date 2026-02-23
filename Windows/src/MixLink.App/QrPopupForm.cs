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

    public QrPopupForm(AppState appState)
    {
        _appState = appState;

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(300, 540);
        BackColor = MixLinkTheme.Background;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;

        Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, Width + 1, Height + 1, 16, 16));

        int y = 0;

        // Traffic lights
        var close = new TrafficLightButton(TrafficLightKind.Close) { Location = new Point(12, 10) };
        close.Click += (_, _) => Hide();
        var minimize = new TrafficLightButton(TrafficLightKind.Minimize) { Location = new Point(32, 10) };
        minimize.Click += (_, _) => Hide();
        Controls.Add(close);
        Controls.Add(minimize);

        // Hamburger
        var hamburger = new HamburgerButton { Location = new Point(Width - 12 - 28, 6) };
        var menu = new ContextMenuStrip();
        menu.Items.Add("Sign Out", null, (_, _) => { LicenseService.ClearCredentials(); Application.Exit(); });
        menu.Items.Add("Help", null, (_, _) => { try { Process.Start(new ProcessStartInfo("mailto:support@cymatics.fm") { UseShellExecute = true }); } catch { } });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Application.Exit());
        hamburger.Click += (_, _) => menu.Show(hamburger, new Point(0, hamburger.Height));
        Controls.Add(hamburger);

        y = 30;

        // Wordmark
        var wordmark = new WordmarkPanel { Location = new Point(0, y), Size = new Size(Width, 18) };
        Controls.Add(wordmark);
        y += 16;

        // MIX LINK title
        var title = new Label
        {
            Text = "MIX LINK",
            Font = new Font("Segoe UI Semibold", 24, FontStyle.Regular),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(Width, 34),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, y)
        };
        Controls.Add(title);
        y += 42;

        // QR Code container
        _qrPictureBox = new PictureBox
        {
            Size = new Size(150, 150),
            Location = new Point((Width - 150) / 2, y),
            SizeMode = PictureBoxSizeMode.Zoom,
            BackColor = Color.White
        };
        Controls.Add(_qrPictureBox);
        y += 160;

        // "Scan with your phone"
        _scanHint = new Label
        {
            Text = "Scan with your phone",
            Font = new Font("Segoe UI", 11),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(Width, 18),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, y)
        };
        Controls.Add(_scanHint);
        y += 22;

        // URL label (cyan, monospaced)
        _urlLabel = new Label
        {
            Font = new Font("Consolas", 10),
            ForeColor = MixLinkTheme.Cyan,
            AutoSize = false,
            Size = new Size(260, 20),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, y),
            Cursor = Cursors.Hand
        };
        _urlLabel.Click += OnUrlClick;
        Controls.Add(_urlLabel);
        y += 30;

        // Status row: Phones | Audio | Signal
        var statusPanel = new Panel
        {
            Location = new Point(20, y),
            Size = new Size(260, 60),
            BackColor = Color.FromArgb(MixLinkTheme.White03.A, MixLinkTheme.White03.R, MixLinkTheme.White03.G, MixLinkTheme.White03.B)
        };
        Controls.Add(statusPanel);

        int colW = 260 / 3;

        // Phones column
        _phonesValue = new Label
        {
            Text = "0",
            Font = new Font("Segoe UI Semibold", 18),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(colW, 28),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, 4)
        };
        var phonesLabel = new Label
        {
            Text = "Phones",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(colW, 16),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, 34)
        };
        statusPanel.Controls.Add(_phonesValue);
        statusPanel.Controls.Add(phonesLabel);

        // Audio column
        _audioIcon = new Label
        {
            Text = "\u266B",
            Font = new Font("Segoe UI", 16),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(colW, 28),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(colW, 4)
        };
        _audioLabel = new Label
        {
            Text = "Idle",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(colW, 16),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(colW, 34)
        };
        statusPanel.Controls.Add(_audioIcon);
        statusPanel.Controls.Add(_audioLabel);

        // Signal column
        _signalPanel = new SignalBarsPanel()
        {
            Location = new Point(colW * 2 + (colW - 20) / 2, 8),
            Size = new Size(20, 20)
        };
        var signalLabel = new Label
        {
            Text = "Signal",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(colW, 16),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(colW * 2, 34)
        };
        statusPanel.Controls.Add(_signalPanel);
        statusPanel.Controls.Add(signalLabel);
        y += 70;

        // Start/Stop button
        _startStopBtn = new MixLinkButton
        {
            Text = "Start",
            Font = new Font("Segoe UI", 14, FontStyle.Bold),
            Size = new Size(260, 44),
            Location = new Point(20, y)
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

    private void UpdateDisplay()
    {
        if (InvokeRequired) { Invoke(UpdateDisplay); return; }

        _qrPictureBox.Image = _appState.QrCodeImage;
        _urlLabel.Text = _appState.WebPlayerUrl ?? "";
        _scanHint.Visible = _appState.IsServerRunning;
        _urlLabel.Visible = _appState.IsServerRunning;

        var clients = _appState.WebClientsConnected;
        _phonesValue.Text = clients.ToString();
        _phonesValue.ForeColor = clients > 0 ? MixLinkTheme.Cyan : Color.Gray;

        var capturing = _appState.IsCaptureActive;
        _audioIcon.ForeColor = capturing ? MixLinkTheme.Cyan : Color.Gray;
        _audioLabel.Text = capturing ? "Streaming" : "Idle";

        bool active = _appState.IsServerRunning && clients > 0 && capturing;
        _signalPanel.Active = active;

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
                if (!IsDisposed)
                    Invoke(() => { _urlLabel.Text = orig; _urlLabel.ForeColor = MixLinkTheme.Cyan; });
            });
        }
        catch { }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _appState.OnStateChanged -= UpdateDisplay;
        base.Dispose(disposing);
    }

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int cx, int cy);

    private sealed class WordmarkPanel : Control
    {
        public WordmarkPanel()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);
            CymaticsWordmark.Draw(e.Graphics, new RectangleF((Width - 200) / 2f, (Height - 11) / 2f, 200, 11), Color.White);
        }
    }

    private sealed class SignalBarsPanel : Control
    {
        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public bool Active { get; set; }

        public SignalBarsPanel()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Color.Transparent);
            var barColor = Active ? MixLinkTheme.Cyan : Color.FromArgb(77, Color.Gray);
            int[] heights = [6, 12, 18];
            int barW = 5;
            int gap = 2;
            int x = 0;
            for (int i = 0; i < 3; i++)
            {
                int h = heights[i];
                int y = Height - h;
                using var b = new SolidBrush(barColor);
                MixLinkPaint.FillRoundedRect(e.Graphics, b, new RectangleF(x, y, barW, h), 1f);
                x += barW + gap;
            }
        }
    }
}
