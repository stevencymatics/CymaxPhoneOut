using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class OnboardingForm : Form
{
    private static readonly string OnboardingFlag =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Cymatics", "onboarding_complete");

    public static bool IsComplete => File.Exists(OnboardingFlag);

    public static void MarkComplete()
    {
        var dir = Path.GetDirectoryName(OnboardingFlag)!;
        Directory.CreateDirectory(dir);
        File.WriteAllText(OnboardingFlag, "1");
    }

    private int _page;
    private readonly Panel _contentPanel;
    private readonly MixLinkButton _actionBtn;
    private readonly DotsPanel _dotsPanel;

    public OnboardingForm()
    {
        Text = "Cymatics Mix Link";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(300, 440);
        BackColor = MixLinkTheme.Background;
        DoubleBuffered = true;

        Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, Width + 1, Height + 1, 16, 16));

        var close = new TrafficLightButton(TrafficLightKind.Close) { Location = new Point(12, 10) };
        close.Click += (_, _) => Close();
        Controls.Add(close);

        _contentPanel = new Panel
        {
            Location = new Point(0, 30),
            Size = new Size(Width, 330),
            BackColor = Color.Transparent
        };
        Controls.Add(_contentPanel);

        _dotsPanel = new DotsPanel(3) { Location = new Point((Width - 50) / 2, 370), Size = new Size(50, 10) };
        Controls.Add(_dotsPanel);

        _actionBtn = new MixLinkButton
        {
            Text = "Continue",
            Font = new Font("Segoe UI", 13, FontStyle.Bold),
            Size = new Size(252, 44),
            Location = new Point(24, 390)
        };
        _actionBtn.Click += OnAction;
        Controls.Add(_actionBtn);

        ShowPage(0);
    }

    private void OnAction(object? sender, EventArgs e)
    {
        if (_page < 2)
        {
            ShowPage(_page + 1);
        }
        else
        {
            MarkComplete();
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    private void ShowPage(int page)
    {
        _page = page;
        _contentPanel.Controls.Clear();

        _dotsPanel.ActiveIndex = page;

        _actionBtn.Text = page < 2 ? "Continue" : "Get Started";

        switch (page)
        {
            case 0: BuildWelcomePage(); break;
            case 1: BuildRequirementsPage(); break;
            case 2: BuildReadyPage(); break;
        }
    }

    private void BuildWelcomePage()
    {
        int y = 30;
        var wm = new WordmarkPanel { Location = new Point(0, y), Size = new Size(Width, 18) };
        _contentPanel.Controls.Add(wm);
        y += 18;

        var title = new Label
        {
            Text = "MIX LINK",
            Font = new Font("Segoe UI Semibold", 27),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(Width, 40),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, y)
        };
        _contentPanel.Controls.Add(title);
        y += 60;

        var desc = new Label
        {
            Text = "Stream your desktop audio\nto your phone over your\nown local network.",
            Font = new Font("Segoe UI", 14),
            ForeColor = Color.FromArgb(140, 255, 255, 255),
            AutoSize = false,
            Size = new Size(240, 80),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(30, y)
        };
        _contentPanel.Controls.Add(desc);
    }

    private void BuildRequirementsPage()
    {
        int y = 16;
        var rows = new[]
        {
            ("\u266B", "Desktop Audio Access", "Mix Link needs permission to capture your system audio."),
            ("\u2B50", "Same Network", "Your computer and phone need to be on the same WiFi or Hotspot."),
        };

        foreach (var (icon, reqTitle, detail) in rows)
        {
            var row = new Panel
            {
                Location = new Point(24, y),
                Size = new Size(252, 70),
                BackColor = Color.FromArgb(MixLinkTheme.White04.A, MixLinkTheme.White04.R, MixLinkTheme.White04.G, MixLinkTheme.White04.B)
            };

            var iconLbl = new Label
            {
                Text = icon,
                Font = new Font("Segoe UI", 20),
                ForeColor = MixLinkTheme.Cyan,
                AutoSize = false,
                Size = new Size(40, 40),
                TextAlign = ContentAlignment.MiddleCenter,
                Location = new Point(10, 14)
            };

            var titleLbl = new Label
            {
                Text = reqTitle,
                Font = new Font("Segoe UI Semibold", 13),
                ForeColor = Color.White,
                AutoSize = true,
                Location = new Point(54, 10)
            };

            var detailLbl = new Label
            {
                Text = detail,
                Font = new Font("Segoe UI", 11),
                ForeColor = Color.FromArgb(128, 255, 255, 255),
                AutoSize = false,
                Size = new Size(188, 34),
                Location = new Point(54, 34)
            };

            row.Controls.Add(iconLbl);
            row.Controls.Add(titleLbl);
            row.Controls.Add(detailLbl);
            _contentPanel.Controls.Add(row);
            y += 80;
        }
    }

    private void BuildReadyPage()
    {
        int y = 50;
        var check = new Label
        {
            Text = "\u2705",
            Font = new Font("Segoe UI", 36),
            AutoSize = false,
            Size = new Size(Width, 50),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, y)
        };
        _contentPanel.Controls.Add(check);
        y += 70;

        var ready = new Label
        {
            Text = "You're all set!",
            Font = new Font("Segoe UI Semibold", 18),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(Width, 30),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, y)
        };
        _contentPanel.Controls.Add(ready);
        y += 40;

        var instructions = new Label
        {
            Text = "Click Start, then scan the QR\ncode with your phone to begin\nstreaming audio.",
            Font = new Font("Segoe UI", 12),
            ForeColor = Color.FromArgb(140, 255, 255, 255),
            AutoSize = false,
            Size = new Size(250, 60),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(25, y)
        };
        _contentPanel.Controls.Add(instructions);
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
            CymaticsWordmark.Draw(e.Graphics, new RectangleF((Width - 200) / 2f, (Height - 12) / 2f, 200, 12), Color.White);
        }
    }

    private sealed class DotsPanel : Control
    {
        private readonly int _count;
        private int _active;
        [System.ComponentModel.Browsable(false)]
        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public int ActiveIndex { get => _active; set { _active = value; Invalidate(); } }

        public DotsPanel(int count)
        {
            _count = count;
            SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Color.Transparent);
            float dotSize = 6f;
            float gap = 8f;
            float totalW = _count * dotSize + (_count - 1) * gap;
            float x = (Width - totalW) / 2f;
            float y = (Height - dotSize) / 2f;
            for (int i = 0; i < _count; i++)
            {
                var alpha = i == _active ? 230 : 51; // 0.9 / 0.2
                using var b = new SolidBrush(Color.FromArgb(alpha, 255, 255, 255));
                e.Graphics.FillEllipse(b, x, y, dotSize, dotSize);
                x += dotSize + gap;
            }
        }
    }
}
