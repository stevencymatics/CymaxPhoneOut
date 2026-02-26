using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class SubscriptionInactiveForm : Form
{
    /// <summary>Set by hamburger → Sign Out so the caller knows to show the login form.</summary>
    public bool SignedOut { get; private set; }

    public SubscriptionInactiveForm(string? viewPlansUrl)
    {
        Text = "Cymatics Mix Link";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(300, 400);
        BackColor = MixLinkTheme.Background;
        DoubleBuffered = true;

        Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, Width + 1, Height + 1, 16, 16));

        var close = new TrafficLightButton(TrafficLightKind.Close) { Location = new Point(12, 10) };
        close.Click += (_, _) => Close();
        Controls.Add(close);

        var minimize = new TrafficLightButton(TrafficLightKind.Minimize) { Location = new Point(32, 10) };
        minimize.Click += (_, _) => Close();
        Controls.Add(minimize);

        // Hamburger menu with Sign Out
        var menu = new ContextMenuStrip();
        menu.Items.Add("Sign Out", null, (_, _) =>
        {
            LicenseService.ClearCredentials();
            SignedOut = true;
            Close();
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Close());
        var hamburger = new HamburgerButton { Location = new Point(Width - 14 - 28, 10) };
        hamburger.Click += (_, _) => menu.Show(hamburger, new Point(0, hamburger.Height));
        Controls.Add(hamburger);

        int y = 36;

        var wordmark = new WordmarkPanel { Location = new Point(0, y), Size = new Size(Width, 18) };
        Controls.Add(wordmark);
        y += 16;

        var title = new Label
        {
            Text = "MIX LINK",
            Font = new Font("Segoe UI Semibold", 24),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(Width, 42),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, y)
        };
        Controls.Add(title);
        y += 56;

        // Warning icon
        var warn = new Label
        {
            Text = "\u26A0",
            Font = new Font("Segoe UI", 28),
            ForeColor = Color.Orange,
            AutoSize = false,
            Size = new Size(Width, 56),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, y)
        };
        Controls.Add(warn);
        y += 62;

        var msg = new Label
        {
            Text = "Your subscription isn't active",
            Font = new Font("Segoe UI Semibold", 13),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(260, 28),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, y)
        };
        Controls.Add(msg);
        y += 38;

        var btn = new MixLinkButton
        {
            Text = "View Plans",
            Font = new Font("Segoe UI", 14, FontStyle.Bold),
            Size = new Size(252, 44),
            Location = new Point(24, y)
        };
        btn.Click += (_, _) =>
        {
            var url = viewPlansUrl ?? "https://cymatics.fm";
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
        };
        Controls.Add(btn);
        y += 56;

        var support = new Label
        {
            Text = "If you have any other questions\ncontact support@cymatics.fm",
            Font = new Font("Segoe UI", 10),
            ForeColor = Color.Gray,
            AutoSize = false,
            Size = new Size(260, 40),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, y)
        };
        Controls.Add(support);
    }

    // Allow dragging the borderless window by its background
    private const int WM_NCHITTEST = 0x84;
    private const int HTCAPTION = 0x2;

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_NCHITTEST)
        {
            base.WndProc(ref m);
            if (m.Result == (IntPtr)1) // HTCLIENT
                m.Result = (IntPtr)HTCAPTION;
            return;
        }
        base.WndProc(ref m);
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
}
