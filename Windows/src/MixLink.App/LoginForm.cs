using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace MixLink.App;

public sealed class LoginForm : Form
{
    private readonly TextBox _emailBox;
    private readonly TextBox _passwordBox;
    private readonly Button _loginButton;
    private readonly Label _errorLabel;
    private readonly Label _loadingLabel;

    public bool LoginSuccess { get; private set; }

    public LoginForm()
    {
        Text = "Cymatics Link";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        Size = new Size(380, 420);
        BackColor = Color.FromArgb(24, 24, 28);
        Font = new Font("Segoe UI", 10);

        var brandLabel = new Label
        {
            Text = "CYMATICS",
            Font = new Font("Segoe UI", 28, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = false,
            Size = new Size(340, 50),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, 30)
        };

        var subtitleLabel = new Label
        {
            Text = "Sign in to continue",
            Font = new Font("Segoe UI", 10),
            ForeColor = Color.FromArgb(140, 140, 140),
            AutoSize = false,
            Size = new Size(340, 22),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(20, 82)
        };

        var emailLabel = new Label
        {
            Text = "Email",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(180, 180, 180),
            AutoSize = true,
            Location = new Point(38, 125)
        };

        _emailBox = new TextBox
        {
            Size = new Size(300, 30),
            Location = new Point(40, 147),
            Font = new Font("Segoe UI", 11),
            BackColor = Color.FromArgb(40, 40, 46),
            ForeColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle
        };

        var passwordLabel = new Label
        {
            Text = "Password",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(180, 180, 180),
            AutoSize = true,
            Location = new Point(38, 190)
        };

        _passwordBox = new TextBox
        {
            Size = new Size(300, 30),
            Location = new Point(40, 212),
            Font = new Font("Segoe UI", 11),
            BackColor = Color.FromArgb(40, 40, 46),
            ForeColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle,
            UseSystemPasswordChar = true
        };

        _loginButton = new Button
        {
            Text = "Sign In",
            Size = new Size(300, 42),
            Location = new Point(40, 265),
            Font = new Font("Segoe UI", 11, FontStyle.Bold),
            ForeColor = Color.White,
            BackColor = Color.FromArgb(0, 150, 220),
            FlatStyle = FlatStyle.Flat,
            Cursor = Cursors.Hand
        };
        _loginButton.FlatAppearance.BorderSize = 0;
        _loginButton.Click += OnLoginClick;

        _errorLabel = new Label
        {
            Text = "",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(239, 68, 68),
            AutoSize = false,
            Size = new Size(300, 36),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(40, 315),
            Visible = false
        };

        _loadingLabel = new Label
        {
            Text = "Verifying...",
            Font = new Font("Segoe UI", 9),
            ForeColor = Color.FromArgb(0, 212, 255),
            AutoSize = false,
            Size = new Size(300, 20),
            TextAlign = ContentAlignment.MiddleCenter,
            Location = new Point(40, 315),
            Visible = false
        };

        Controls.Add(brandLabel);
        Controls.Add(subtitleLabel);
        Controls.Add(emailLabel);
        Controls.Add(_emailBox);
        Controls.Add(passwordLabel);
        Controls.Add(_passwordBox);
        Controls.Add(_loginButton);
        Controls.Add(_errorLabel);
        Controls.Add(_loadingLabel);

        AcceptButton = _loginButton;

        var stored = LicenseService.LoadCredentials();
        if (stored is not null)
        {
            _emailBox.Text = stored.Email;
            _passwordBox.Text = stored.Password;
        }
    }

    private async void OnLoginClick(object? sender, EventArgs e)
    {
        var email = _emailBox.Text.Trim();
        var password = _passwordBox.Text;

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
        _loadingLabel.Visible = false;
    }

    private void SetLoading(bool loading)
    {
        _loginButton.Enabled = !loading;
        _emailBox.Enabled = !loading;
        _passwordBox.Enabled = !loading;
        _loadingLabel.Visible = loading;
        if (loading) _errorLabel.Visible = false;
        _loginButton.Text = loading ? "Verifying..." : "Sign In";
    }
}
