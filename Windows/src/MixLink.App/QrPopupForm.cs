using System.Drawing;
using System.Windows.Forms;

namespace MixLink.App;

/// <summary>
/// Borderless popup window showing QR code and URL.
/// </summary>
public sealed class QrPopupForm : Form
{
    private readonly AppState _appState;
    private readonly PictureBox _qrPictureBox;
    private readonly Label _urlLabel;
    private readonly Label _statusLabel;

    public QrPopupForm(AppState appState)
    {
        _appState = appState;

        // Form settings
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(280, 340);
        BackColor = Color.FromArgb(30, 30, 30);
        ShowInTaskbar = false;
        TopMost = true;

        // Add rounded corners (Windows 11 style)
        Region = CreateRoundedRegion(Size, 16);

        // Title
        var titleLabel = new Label
        {
            Text = "Cymatics Link",
            Font = new Font("Segoe UI", 16, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(280, 35),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(0, 15)
        };

        // QR Code image
        _qrPictureBox = new PictureBox
        {
            Size = new Size(200, 200),
            Location = new Point(40, 55),
            SizeMode = PictureBoxSizeMode.Zoom,
            BackColor = Color.White
        };

        // URL label
        _urlLabel = new Label
        {
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(0, 212, 255),
            AutoSize = false,
            Size = new Size(260, 20),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(10, 265),
            Cursor = Cursors.Hand
        };
        _urlLabel.Click += OnUrlClick;

        // Status label
        _statusLabel = new Label
        {
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(128, 128, 128),
            AutoSize = false,
            Size = new Size(260, 20),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(10, 290)
        };

        // Close button
        var closeButton = new Button
        {
            Text = "×",
            Font = new Font("Segoe UI", 14, FontStyle.Bold),
            ForeColor = Color.FromArgb(128, 128, 128),
            FlatStyle = FlatStyle.Flat,
            Size = new Size(30, 30),
            Location = new Point(245, 5),
            Cursor = Cursors.Hand
        };
        closeButton.FlatAppearance.BorderSize = 0;
        closeButton.FlatAppearance.MouseOverBackColor = Color.FromArgb(60, 60, 60);
        closeButton.Click += (s, e) => Hide();

        Controls.Add(titleLabel);
        Controls.Add(_qrPictureBox);
        Controls.Add(_urlLabel);
        Controls.Add(_statusLabel);
        Controls.Add(closeButton);

        // Subscribe to state changes
        _appState.OnStateChanged += UpdateDisplay;

        // Initial display
        UpdateDisplay();

        // Close on click outside or Escape
        Deactivate += (s, e) => Hide();
        KeyPreview = true;
        KeyDown += (s, e) =>
        {
            if (e.KeyCode == Keys.Escape)
                Hide();
        };
    }

    private void UpdateDisplay()
    {
        if (InvokeRequired)
        {
            Invoke(UpdateDisplay);
            return;
        }

        _qrPictureBox.Image = _appState.QrCodeImage;
        _urlLabel.Text = _appState.WebPlayerUrl ?? "Not available";

        if (_appState.IsServerRunning)
        {
            var clients = _appState.WebClientsConnected;
            _statusLabel.Text = clients > 0
                ? $"Streaming to {clients} device{(clients == 1 ? "" : "s")}"
                : "Scan with your phone to connect";
            _statusLabel.ForeColor = clients > 0
                ? Color.FromArgb(74, 222, 128)
                : Color.FromArgb(128, 128, 128);
        }
        else
        {
            _statusLabel.Text = "Server stopped";
            _statusLabel.ForeColor = Color.FromArgb(239, 68, 68);
        }
    }

    private void OnUrlClick(object? sender, EventArgs e)
    {
        if (!string.IsNullOrEmpty(_appState.WebPlayerUrl))
        {
            try
            {
                // Copy URL to clipboard
                Clipboard.SetText(_appState.WebPlayerUrl);

                // Show feedback
                var originalText = _urlLabel.Text;
                _urlLabel.Text = "Copied to clipboard!";
                _urlLabel.ForeColor = Color.FromArgb(74, 222, 128);

                // Revert after 2 seconds
                Task.Delay(2000).ContinueWith(_ =>
                {
                    if (!IsDisposed)
                    {
                        Invoke(() =>
                        {
                            _urlLabel.Text = originalText;
                            _urlLabel.ForeColor = Color.FromArgb(0, 212, 255);
                        });
                    }
                });
            }
            catch
            {
                // Ignore clipboard errors
            }
        }
    }

    private static Region CreateRoundedRegion(Size size, int radius)
    {
        using var path = new System.Drawing.Drawing2D.GraphicsPath();
        path.AddArc(0, 0, radius * 2, radius * 2, 180, 90);
        path.AddArc(size.Width - radius * 2, 0, radius * 2, radius * 2, 270, 90);
        path.AddArc(size.Width - radius * 2, size.Height - radius * 2, radius * 2, radius * 2, 0, 90);
        path.AddArc(0, size.Height - radius * 2, radius * 2, radius * 2, 90, 90);
        path.CloseAllFigures();
        return new Region(path);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        // Draw subtle border
        using var pen = new Pen(Color.FromArgb(60, 60, 60), 1);
        e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _appState.OnStateChanged -= UpdateDisplay;
        }
        base.Dispose(disposing);
    }
}
