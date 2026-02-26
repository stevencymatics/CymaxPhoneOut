using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class UpdateForm : Form
{
    private readonly string _latestVersion;
    private readonly string _updateUrl;

    /// <summary>
    /// Shows an update prompt if a newer version is available and the user hasn't dismissed it.
    /// Returns without doing anything if no update is needed.
    /// </summary>
    public static void CheckAndPrompt(VerifyResult result)
    {
        if (string.IsNullOrEmpty(result.LatestVersion) || string.IsNullOrEmpty(result.UpdateUrl))
            return;

        var currentVersion = LicenseService.GetCurrentVersion() ?? "0.0";
        if (!LicenseService.IsVersionNewer(result.LatestVersion, currentVersion))
            return;

        var dismissed = LicenseService.GetDismissedUpdateVersion();
        if (dismissed == result.LatestVersion)
            return;

        using var form = new UpdateForm(result.LatestVersion, result.UpdateUrl);
        form.ShowDialog();
    }

    private UpdateForm(string latestVersion, string updateUrl)
    {
        _latestVersion = latestVersion;
        _updateUrl = updateUrl;

        Text = "Update Available";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(340, 220);
        BackColor = MixLinkTheme.Background;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;

        Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, ClientSize.Width + 1, ClientSize.Height + 1, 16, 16));

        int pad = 32;
        int cw = ClientSize.Width - pad * 2;

        var close = new TrafficLightButton(TrafficLightKind.Close) { Location = new Point(14, 14) };
        close.Click += (_, _) => { DismissAndClose(); };
        Controls.Add(close);

        int y = 36;

        var wordmark = new WordmarkPanel { Location = new Point(pad, y), Size = new Size(cw, 14) };
        Controls.Add(wordmark);
        y += 18;

        var title = new Label
        {
            Text = "Update Available",
            Font = new Font("Segoe UI", 18, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(cw, 30),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        Controls.Add(title);
        y += 40;

        var message = new Label
        {
            Text = $"Cymatics Mix Link {_latestVersion} is available.",
            Font = new Font("Segoe UI", 11),
            ForeColor = Color.FromArgb(200, 200, 200),
            AutoSize = false,
            Size = new Size(cw, 22),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        Controls.Add(message);
        y += 38;

        var downloadBtn = new MixLinkButton
        {
            Text = "Download",
            Font = new Font("Segoe UI", 13, FontStyle.Bold),
            ForeColor = Color.Black,
            Size = new Size(cw, 42),
            Location = new Point(pad, y)
        };
        downloadBtn.Click += (_, _) =>
        {
            try { Process.Start(new ProcessStartInfo(_updateUrl) { UseShellExecute = true }); } catch { }
            Close();
        };
        Controls.Add(downloadBtn);
        y += 52;

        var laterLink = new LinkLabel
        {
            Text = "Later",
            LinkColor = Color.FromArgb(160, 160, 160),
            ActiveLinkColor = Color.White,
            VisitedLinkColor = Color.FromArgb(160, 160, 160),
            LinkBehavior = LinkBehavior.NeverUnderline,
            Font = new Font("Segoe UI", 10),
            AutoSize = false,
            Size = new Size(cw, 20),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        laterLink.Click += (_, _) => { DismissAndClose(); };
        Controls.Add(laterLink);
    }

    private void DismissAndClose()
    {
        LicenseService.SetDismissedUpdateVersion(_latestVersion);
        Close();
    }

    // Allow dragging
    private const int WM_NCHITTEST = 0x84;
    private const int HTCAPTION = 0x2;

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_NCHITTEST)
        {
            base.WndProc(ref m);
            if (m.Result == (IntPtr)1)
                m.Result = (IntPtr)HTCAPTION;
            return;
        }
        base.WndProc(ref m);
    }

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int cx, int cy);

    private sealed class WordmarkPanel : Control
    {
        public WordmarkPanel() =>
            SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);
            CymaticsWordmark.Draw(e.Graphics, new RectangleF(0, 0, Width, Height), Color.White);
        }
    }
}
