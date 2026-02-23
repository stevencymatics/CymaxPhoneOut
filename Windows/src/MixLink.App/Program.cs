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

        // Verify license before launching the app
        using var loginForm = new LoginForm();
        var result = loginForm.ShowDialog();

        if (result != DialogResult.OK || !loginForm.LoginSuccess)
            return;

        // Show onboarding on first launch
        if (!OnboardingForm.IsComplete)
        {
            using var onboarding = new OnboardingForm();
            if (onboarding.ShowDialog() != DialogResult.OK)
                return;
        }

        // License verified — run the application
        Application.Run(new TrayApplication());
    }
}
