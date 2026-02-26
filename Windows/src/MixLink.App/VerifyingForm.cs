using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MixLink.App;

/// <summary>
/// Shown when grace period has expired and we need to verify before granting access.
/// Displays a spinner and auto-closes with the result.
/// </summary>
public sealed class VerifyingForm : Form
{
    public VerifyResult? Result { get; private set; }

    private readonly string _email;
    private readonly string _password;
    private readonly Label _statusLabel;

    public VerifyingForm(string email, string password)
    {
        _email = email;
        _password = password;

        Text = "Cymatics Mix Link";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(320, 180);
        BackColor = MixLinkTheme.Background;
        ShowInTaskbar = true;
        DoubleBuffered = true;

        Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, ClientSize.Width + 1, ClientSize.Height + 1, 16, 16));

        int pad = 32;
        int cw = ClientSize.Width - pad * 2;

        int y = 32;

        var wordmark = new WordmarkPanel { Location = new Point(pad, y), Size = new Size(cw, 14) };
        Controls.Add(wordmark);
        y += 18;

        var title = new Label
        {
            Text = "MIX LINK",
            Font = new Font("Segoe UI", 18, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(cw, 30),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        Controls.Add(title);
        y += 42;

        _statusLabel = new Label
        {
            Text = "Verifying subscription...",
            Font = new Font("Segoe UI", 11),
            ForeColor = Color.FromArgb(180, 180, 180),
            AutoSize = false,
            Size = new Size(cw, 22),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        Controls.Add(_statusLabel);
        y += 30;

        var progress = new ProgressBar
        {
            Style = ProgressBarStyle.Marquee,
            MarqueeAnimationSpeed = 28,
            Size = new Size(cw, 3),
            Location = new Point(pad, y)
        };
        Controls.Add(progress);

        Shown += OnShown;
    }

    private async void OnShown(object? sender, EventArgs e)
    {
        try
        {
            Result = await LicenseService.VerifyAsync(_email, _password);
        }
        catch (HttpRequestException)
        {
            _statusLabel.Text = "Cannot reach server.";
            await Task.Delay(1500);
            Result = null; // signals network error
        }
        catch (TaskCanceledException)
        {
            _statusLabel.Text = "Request timed out.";
            await Task.Delay(1500);
            Result = null;
        }
        catch
        {
            _statusLabel.Text = "Verification failed.";
            await Task.Delay(1500);
            Result = null;
        }

        DialogResult = DialogResult.OK;
        Close();
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
