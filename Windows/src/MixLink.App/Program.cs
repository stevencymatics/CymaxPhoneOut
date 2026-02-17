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
                "Cymatics Link is already running.\nCheck the system tray.",
                "Cymatics Link",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information
            );
            return;
        }

        // Enable visual styles
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.SystemAware);

        // Handle unhandled exceptions
        Application.ThreadException += (s, e) =>
        {
            MessageBox.Show(
                $"An error occurred: {e.Exception.Message}",
                "Cymatics Link Error",
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
                    "Cymatics Link Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        };

        // Run the application
        Application.Run(new TrayApplication());
    }
}
