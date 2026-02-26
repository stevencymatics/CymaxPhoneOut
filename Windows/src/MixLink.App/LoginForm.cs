using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class LoginForm : Form
{
    private readonly RoundedField _emailField;
    private readonly RoundedField _passwordField;
    private readonly MixLinkButton _loginButton;
    private readonly ProgressBar _progress;
    private readonly Label _errorLabel;

    public bool LoginSuccess { get; private set; }
    public VerifyResult? LastVerifyResult { get; private set; }

    public LoginForm()
    {
        Text = "Cymatics Mix Link";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = true;
        ClientSize = new Size(380, 380);
        BackColor = MixLinkTheme.Background;
        DoubleBuffered = true;

        Region = Region.FromHrgn(Native.CreateRoundRectRgn(0, 0, ClientSize.Width + 1, ClientSize.Height + 1, 16, 16));

        int pad = 32;
        int fieldW = ClientSize.Width - pad * 2;

        var close = new TrafficLightButton(TrafficLightKind.Close) { Location = new Point(14, 14) };
        close.Click += (_, _) => Close();
        var minimize = new TrafficLightButton(TrafficLightKind.Minimize) { Location = new Point(36, 14) };
        minimize.Click += (_, _) => Hide();

        var menu = new ContextMenuStrip();
        menu.Items.Add("Help", null, (_, _) => OpenUrl("https://cymatics.fm/pages/mix-link-faq"));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Application.Exit());
        var hamburger = new HamburgerButton { Location = new Point(ClientSize.Width - 14 - 28, 10) };
        hamburger.Click += (_, _) => menu.Show(hamburger, new Point(0, hamburger.Height));

        int y = 44;

        var wordmark = new WordmarkControl
        {
            Location = new Point(pad, y),
            Size = new Size(fieldW, 18),
            ForeColor = Color.White
        };
        y += 22;

        var title = new Label
        {
            Text = "MIX LINK",
            Font = new Font("Segoe UI", 22, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(fieldW, 36),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        y += 56;

        _emailField = new RoundedField("Email", isPassword: false)
        {
            Location = new Point(pad, y),
            Size = new Size(fieldW, 40)
        };
        y += 52;

        _passwordField = new RoundedField("Password", isPassword: true)
        {
            Location = new Point(pad, y),
            Size = new Size(fieldW, 40)
        };
        y += 52;

        _errorLabel = new Label
        {
            Text = "",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(239, 68, 68),
            AutoSize = false,
            Size = new Size(fieldW, 24),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y),
            Visible = false
        };
        _progress = new ProgressBar
        {
            Style = ProgressBarStyle.Marquee,
            MarqueeAnimationSpeed = 28,
            Size = new Size(fieldW, 3),
            Location = new Point(pad, y + 10),
            Visible = false
        };
        y += 30;

        _loginButton = new MixLinkButton
        {
            Text = "Sign In",
            Location = new Point(pad, y),
            Size = new Size(fieldW, 42),
            Font = new Font("Segoe UI", 13, FontStyle.Bold),
            ForeColor = Color.Black
        };
        _loginButton.Click += OnLoginClick;
        y += 56;

        var forgot = new LinkLabel
        {
            Text = "Forgot Password?",
            LinkColor = MixLinkTheme.Cyan,
            ActiveLinkColor = MixLinkTheme.Teal,
            VisitedLinkColor = MixLinkTheme.Cyan,
            LinkBehavior = LinkBehavior.NeverUnderline,
            Font = new Font("Segoe UI", 10),
            AutoSize = false,
            Size = new Size(fieldW, 20),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(pad, y)
        };
        forgot.Click += (_, _) => OpenUrl("https://cymatics.fm/pages/forgot-password");

        Controls.Add(close);
        Controls.Add(minimize);
        Controls.Add(hamburger);
        Controls.Add(wordmark);
        Controls.Add(title);
        Controls.Add(_emailField);
        Controls.Add(_passwordField);
        Controls.Add(_errorLabel);
        Controls.Add(_progress);
        Controls.Add(_loginButton);
        Controls.Add(forgot);

        var stored = LicenseService.LoadCredentials();
        if (stored is not null)
        {
            _emailField.Value = stored.Email;
            _passwordField.Value = stored.Password;
        }

        Shown += (_, _) => _emailField.FocusInput();
    }

    private async void OnLoginClick(object? sender, EventArgs e)
    {
        var email = _emailField.Value.Trim();
        var password = _passwordField.Value;

        if (string.IsNullOrEmpty(email) || string.IsNullOrEmpty(password))
        {
            ShowError("Please enter your email and password.");
            return;
        }

        SetLoading(true);

        try
        {
            var result = await LicenseService.VerifyAsync(email, password);

            if (result.AccessGranted)
            {
                LicenseService.SaveCredentials(email, password);
                LicenseService.MarkVerificationSuccess();
                LastVerifyResult = result;
                LoginSuccess = true;
                DialogResult = DialogResult.OK;
                Close();
                return;
            }

            switch (result.Reason)
            {
                case "invalid_credentials":
                    ShowError("Invalid email or password. Please try again.");
                    break;
                case "inactive_subscription":
                case "no_purchase":
                    LicenseService.SaveCredentials(email, password);
                    using (var inactive = new SubscriptionInactiveForm(result.ViewPlansUrl))
                        inactive.ShowDialog(this);
                    break;
                default:
                    ShowError("Verification failed. Please try again later.");
                    break;
            }
        }
        catch (HttpRequestException) { ShowError("Cannot reach server. Check your internet connection."); }
        catch (TaskCanceledException) { ShowError("Request timed out. Please try again."); }
        catch { ShowError("An unexpected error occurred. Please try again."); }
        finally { SetLoading(false); }
    }

    private void ShowError(string msg) { _errorLabel.Text = msg; _errorLabel.Visible = true; _progress.Visible = false; }

    private void SetLoading(bool on)
    {
        _loginButton.Enabled = !on;
        _emailField.Enabled = !on;
        _passwordField.Enabled = !on;
        _progress.Visible = on;
        if (on) _errorLabel.Visible = false;
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

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }

    private sealed class WordmarkControl : Control
    {
        public WordmarkControl() =>
            SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);
            CymaticsWordmark.Draw(e.Graphics, new RectangleF(0, 0, Width, Height), Color.White);
        }
    }

    internal sealed class RoundedField : Panel
    {
        private readonly TextBox _box;
        private readonly string _placeholder;
        private bool _focused;

        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public string Value { get => _box.Text; set => _box.Text = value; }

        public RoundedField(string placeholder, bool isPassword)
        {
            _placeholder = placeholder;
            DoubleBuffered = true;
            BackColor = MixLinkTheme.Background;
            // Compute the exact blended color: 15% white over Background(20,20,20)
            // so the TextBox matches the rounded rect fill with no visible seam
            int bg = MixLinkTheme.Background.R; // 20
            int blended = bg + (int)((255 - bg) * 38.0 / 255.0); // ≈ 55
            _box = new TextBox
            {
                BorderStyle = BorderStyle.None,
                ForeColor = Color.White,
                BackColor = Color.FromArgb(blended, blended, blended),
                Font = new Font("Segoe UI", 12),
                UseSystemPasswordChar = isPassword,
            };
            _box.GotFocus += (_, _) => { _focused = true; Invalidate(); };
            _box.LostFocus += (_, _) => { _focused = false; Invalidate(); };
            _box.TextChanged += (_, _) => Invalidate();
            Controls.Add(_box);
        }

        public void FocusInput() => _box.Focus();

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            _box.Width = Width - 24;
            _box.Location = new Point(12, (Height - _box.Height) / 2);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);
            var rect = new RectangleF(0, 0, Width - 1, Height - 1);
            using var fill = new SolidBrush(Color.FromArgb(38, 255, 255, 255));
            MixLinkPaint.FillRoundedRect(e.Graphics, fill, rect, 8f);
            using var pen = new Pen(_focused ? Color.FromArgb(140, MixLinkTheme.Cyan) : Color.FromArgb(64, 255, 255, 255), 1f);
            MixLinkPaint.StrokeRoundedRect(e.Graphics, pen, rect, 8f);
            if (string.IsNullOrEmpty(_box.Text) && !_focused)
                TextRenderer.DrawText(e.Graphics, _placeholder, _box.Font,
                    new Rectangle(12, 0, Width - 24, Height),
                    Color.FromArgb(128, 255, 255, 255),
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left);
        }
    }

    internal static class Native
    {
        [System.Runtime.InteropServices.DllImport("gdi32.dll")]
        public static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int cx, int cy);
    }
}
