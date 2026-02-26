using System;
using System.Threading;
using System.Windows.Forms;

namespace MixLink.App;

internal static class Program
{
    /// <summary>
    /// The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        // Ensure only one instance is running
        using var mutex = new Mutex(true, "MixLink.Windows.SingleInstance", out bool createdNew);

        if (!createdNew)
        {
            MessageBox.Show(
                "Cymatics Mix Link is already running.\nCheck the system tray.",
                "Cymatics Mix Link",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information
            );
            return;
        }

        // Enable visual styles
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.DpiUnawareGdiScaled);

        // Handle unhandled exceptions
        Application.ThreadException += (s, e) =>
        {
            MessageBox.Show(
                $"An error occurred: {e.Exception.Message}",
                "Cymatics Mix Link Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        };

        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        {
            if (e.ExceptionObject is Exception ex)
            {
                MessageBox.Show(
                    $"A fatal error occurred: {ex.Message}",
                    "Cymatics Mix Link Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        };

        // Subscription verification with grace period
        var creds = LicenseService.LoadCredentials();
        bool authorized = false;
        bool needsBackgroundVerify = false;

        if (creds is not null && LicenseService.IsWithinGracePeriod())
        {
            // Within grace period — skip login, background verify will run in TrayApplication
            authorized = true;
            needsBackgroundVerify = true;
        }
        else if (creds is not null)
        {
            // Have credentials but grace expired — verify silently before showing any UI
            try
            {
                var result = LicenseService.VerifyAsync(creds.Email, creds.Password).GetAwaiter().GetResult();

                if (result.AccessGranted)
                {
                    LicenseService.MarkVerificationSuccess();
                    UpdateForm.CheckAndPrompt(result);
                    authorized = true;
                }
                else if (result.Reason == "invalid_credentials")
                {
                    LicenseService.ClearCredentials();
                    LicenseService.ClearGracePeriod();
                    // Fall through to login
                }
                else
                {
                    // inactive_subscription or no_purchase — show inactive screen and exit
                    LicenseService.ClearGracePeriod();
                    using var inactive = new SubscriptionInactiveForm(result.ViewPlansUrl);
                    inactive.ShowDialog();
                    return;
                }
            }
            catch
            {
                // Network error — fall through to login
            }
        }

        if (!authorized)
        {
            using var loginForm = new LoginForm();
            var loginResult = loginForm.ShowDialog();

            if (loginResult != DialogResult.OK || !loginForm.LoginSuccess)
                return;

            // Check for update using the verify result from login
            if (loginForm.LastVerifyResult is not null)
                UpdateForm.CheckAndPrompt(loginForm.LastVerifyResult);
        }

        // Show onboarding on first launch
        if (!OnboardingForm.IsComplete)
        {
            using var onboarding = new OnboardingForm();
            if (onboarding.ShowDialog() != DialogResult.OK)
                return;
        }

        // License verified — run the application
        Application.Run(new TrayApplication(backgroundVerify: needsBackgroundVerify));
    }
}
