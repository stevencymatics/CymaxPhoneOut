using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class SubscriptionInactiveForm : Form
{
    public SubscriptionInactiveForm(string? viewPlansUrl)
    {
        Text = "Cymatics Link";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        Size = new Size(380, 320);
        BackColor = Color.FromArgb(24, 24, 28);
        Font = new Font("Segoe UI", 10);

        var brandLabel = new Label
        {
            Text = "CYMATICS",
            Font = new Font("Segoe UI", 24, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(340, 44),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, 25)
        };

        var messageLabel = new Label
        {
            Text = "Your subscription isn't active",
            Font = new Font("Segoe UI", 13),
            ForeColor = Color.FromArgb(220, 220, 220),
            AutoSize = false,
            Size = new Size(340, 30),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, 85)
        };

        var viewPlansButton = new Button
        {
            Text = "View Plans",
            Size = new Size(300, 42),
            Location = new Point(40, 140),
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Color.White,
            BackColor = Color.FromArgb(0, 150, 220),
            FlatStyle = FlatStyle.Flat,
            Cursor = Cursors.Hand
        };
        viewPlansButton.FlatAppearance.BorderSize = 0;
        viewPlansButton.Click += (_, _) =>
        {
            var url = viewPlansUrl ?? "https://cymatics.fm";
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
            catch { }
        };

        var supportLabel = new Label
        {
            Text = "If you have any other questions\ncontact support@cymatics.fm",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(120, 120, 120),
            AutoSize = false,
            Size = new Size(340, 40),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, 200)
        };

        var closeButton = new Button
        {
            Text = "Close",
            Size = new Size(300, 34),
            Location = new Point(40, 250),
            Font = new Font("Segoe UI", 10),
            ForeColor = Color.FromArgb(180, 180, 180),
            BackColor = Color.FromArgb(50, 50, 56),
            FlatStyle = FlatStyle.Flat,
            Cursor = Cursors.Hand
        };
        closeButton.FlatAppearance.BorderSize = 0;
        closeButton.Click += (_, _) => Close();

        Controls.Add(brandLabel);
        Controls.Add(messageLabel);
        Controls.Add(viewPlansButton);
        Controls.Add(supportLabel);
        Controls.Add(closeButton);
    }
}
