using System.Drawing;
using QRCoder;

namespace MixLink.Core.Utilities;

/// <summary>
/// QR code generation utilities.
/// </summary>
public static class QrCodeGenerator
{
    /// <summary>
    /// Generate a QR code bitmap for the given URL.
    /// </summary>
    /// <param name="url">The URL to encode</param>
    /// <param name="size">Size in pixels (default 200)</param>
    /// <returns>Bitmap image of the QR code</returns>
    public static Bitmap Generate(string url, int size = 200)
    {
        using var qrGenerator = new QRCodeGenerator();
        using var qrCodeData = qrGenerator.CreateQrCode(url, QRCodeGenerator.ECCLevel.M);
        using var qrCode = new QRCoder.QRCode(qrCodeData);

        // Calculate pixels per module to achieve desired size
        var pixelsPerModule = Math.Max(1, size / qrCodeData.ModuleMatrix.Count);

        return qrCode.GetGraphic(pixelsPerModule, Color.Black, Color.White, true);
    }

    /// <summary>
    /// Get the web player URL.
    /// </summary>
    /// <param name="port">HTTP port (default 19621)</param>
    /// <returns>Full URL or null if no local IP available</returns>
    public static string? GetWebPlayerUrl(int port = 19621)
    {
        var ip = NetworkUtils.GetLocalIPAddress();
        if (ip == null)
            return null;

        return $"http://{ip}:{port}";
    }
}
