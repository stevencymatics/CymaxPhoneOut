using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class LoginForm : Form
{
    private readonly RoundedField _emailField;
    private readonly RoundedField _passwordField;
    private readonly MixLinkButton _loginButton;
    private readonly ProgressBar _progress;
    private readonly Label _errorLabel;
    private readonly ContextMenuStrip _menu;

    public bool LoginSuccess { get; private set; }

    public LoginForm()
    {
        Text = "Cymatics Mix Link";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = true;
        Size = new Size(300, 420);
        BackColor = MixLinkTheme.Background;
        Font = new Font("Segoe UI", 10);
        DoubleBuffered = true;

        Region = Region.FromHrgn(Native.CreateRoundRectRgn(0, 0, Width + 1, Height + 1, 16, 16));

        // Header (traffic lights + hamburger)
        var close = new TrafficLightButton(TrafficLightKind.Close) { Location = new Point(12, 10) };
        close.Click += (_, _) => Close();
        var minimize = new TrafficLightButton(TrafficLightKind.Minimize) { Location = new Point(32, 10) };
        minimize.Click += (_, _) => Hide();

        _menu = new ContextMenuStrip();
        _menu.Items.Add("Help", null, (_, _) => OpenUrl($"mailto:support@cymatics.fm"));
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add("Quit", null, (_, _) => Application.Exit());

        var hamburger = new HamburgerButton { Location = new Point(Width - 12 - 28, 6) };
        hamburger.Click += (_, _) => _menu.Show(hamburger, new Point(0, hamburger.Height));

        // Cymatics wordmark + MIX LINK
        var wordmark = new WordmarkControl
        {
            Location = new Point(0, 52),
            Size = new Size(Width, 20),
            ForeColor = Color.White
        };
        var title = new Label
        {
            Text = "MIX LINK",
            Font = new Font("Segoe UI Semibold", 24, FontStyle.Regular),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(Width, 34),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, 70)
        };

        // Form fields (match SwiftUI styling)
        _emailField = new RoundedField("Email", isPassword: false)
        {
            Location = new Point(24, 140),
            Size = new Size(252, 42)
        };

        _passwordField = new RoundedField("Password", isPassword: true)
        {
            Location = new Point(24, 196),
            Size = new Size(252, 42)
        };

        _loginButton = new MixLinkButton
        {
            Text = "Sign In",
            Location = new Point(24, 252),
            Size = new Size(252, 44),
            Font = new Font("Segoe UI", 14, FontStyle.Bold),
            ForeColor = Color.Black
        };
        _loginButton.Click += OnLoginClick;

        _errorLabel = new Label
        {
            Text = "",
            Font = new Font("Segoe UI", 11),
            ForeColor = Color.FromArgb(239, 68, 68), // #ef4444
            AutoSize = false,
            Size = new Size(252, 44),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(24, 302),
            Visible = false
        };

        _progress = new ProgressBar
        {
            Style = ProgressBarStyle.Marquee,
            MarqueeAnimationSpeed = 28,
            Size = new Size(252, 4),
            Location = new Point(24, 302),
            Visible = false
        };

        var forgot = new LinkLabel
        {
            Text = "Forgot Password?",
            LinkColor = MixLinkTheme.Cyan,
            ActiveLinkColor = MixLinkTheme.Teal,
            VisitedLinkColor = MixLinkTheme.Cyan,
            LinkBehavior = LinkBehavior.NeverUnderline,
            Font = new Font("Segoe UI", 11, FontStyle.Regular),
            AutoSize = false,
            Size = new Size(252, 22),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(24, 355)
        };
        forgot.Click += (_, _) => OpenUrl("https://cymatics.fm/pages/forgot-password");

        Controls.Add(close);
        Controls.Add(minimize);
        Controls.Add(hamburger);
        Controls.Add(wordmark);
        Controls.Add(title);
        Controls.Add(_emailField);
        Controls.Add(_passwordField);
        Controls.Add(_loginButton);
        Controls.Add(_errorLabel);
        Controls.Add(_progress);
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
                    {
                        inactive.ShowDialog(this);
                    }
                    break;
                default:
                    ShowError("Verification failed. Please try again later.");
                    break;
            }
        }
        catch (HttpRequestException)
        {
            ShowError("Cannot reach server. Check your internet connection.");
        }
        catch (TaskCanceledException)
        {
            ShowError("Request timed out. Please try again.");
        }
        catch
        {
            ShowError("An unexpected error occurred. Please try again.");
        }
        finally
        {
            SetLoading(false);
        }
    }

    private void ShowError(string message)
    {
        _errorLabel.Text = message;
        _errorLabel.Visible = true;
        _progress.Visible = false;
    }

    private void SetLoading(bool loading)
    {
        _loginButton.Enabled = !loading;
        _emailField.Enabled = !loading;
        _passwordField.Enabled = !loading;
        _progress.Visible = loading;
        if (loading) _errorLabel.Visible = false;
        _loginButton.Text = loading ? "Sign In" : "Sign In";
    }

    private static void OpenUrl(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch { }
    }

    private sealed class WordmarkControl : Control
    {
        public WordmarkControl()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);
            var h = 11f;
            var w = 260f;
            var rect = new RectangleF((Width - w) / 2f, (Height - h) / 2f, w, h);
            CymaticsWordmark.Draw(e.Graphics, rect, ForeColor);
        }
    }

    private sealed class RoundedField : Panel
    {
        private readonly TextBox _box;
        private readonly string _placeholder;
        private bool _focused;

        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public string Value
        {
            get => _box.Text;
            set => _box.Text = value;
        }

        public RoundedField(string placeholder, bool isPassword)
        {
            _placeholder = placeholder;
            DoubleBuffered = true;
            BackColor = Color.Transparent;
            _box = new TextBox
            {
                BorderStyle = BorderStyle.None,
                ForeColor = Color.White,
                BackColor = Color.FromArgb(0, 0, 0, 0),
                Font = new Font("Segoe UI", 13),
                UseSystemPasswordChar = isPassword,
                Location = new Point(10, 12),
                Width = 999
            };
            _box.GotFocus += (_, _) => { _focused = true; Invalidate(); };
            _box.LostFocus += (_, _) => { _focused = false; Invalidate(); };
            _box.TextChanged += (_, _) => Invalidate();
            Controls.Add(_box);
            Padding = new Padding(10);
        }

        public void FocusInput() => _box.Focus();

        protected override void OnResize(EventArgs eventargs)
        {
            base.OnResize(eventargs);
            _box.Width = Width - 20;
            _box.Location = new Point(10, (Height - _box.Height) / 2);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);

            var rect = ClientRectangle;
            rect.Inflate(-1, -1);

            using var fill = new SolidBrush(MixLinkTheme.White15);
            MixLinkPaint.FillRoundedRect(e.Graphics, fill, rect, 8f);

            using var pen = new Pen(_focused ? Color.FromArgb(140, MixLinkTheme.Cyan) : MixLinkTheme.White25, 1f);
            MixLinkPaint.StrokeRoundedRect(e.Graphics, pen, rect, 8f);

            if (string.IsNullOrEmpty(_box.Text) && !_focused)
            {
                var phColor = Color.FromArgb(128, 255, 255, 255); // 0.5
                TextRenderer.DrawText(
                    e.Graphics,
                    _placeholder,
                    _box.Font,
                    new Rectangle(10, 0, Width - 20, Height),
                    phColor,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Left
                );
            }
        }
    }

    private static class Native
    {
        [System.Runtime.InteropServices.DllImport("gdi32.dll", SetLastError = true)]
        public static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
    }
}
