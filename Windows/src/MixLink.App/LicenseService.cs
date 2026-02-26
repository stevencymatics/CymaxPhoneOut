using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace MixLink.App;

public sealed class LicenseService
{
    private const string WorkerUrl = "https://license-verification-worker.teamcymatics.workers.dev/verify-license";
    private const string ProductSlug = "mix-link";
    private const double GracePeriodSeconds = 3 * 24 * 60 * 60; // 3 days

    private const string RegistryPath = @"SOFTWARE\Cymatics\MixLink";
    private const string LastVerifiedValue = "LastVerifiedAt";
    private const string DismissedUpdateValue = "DismissedUpdateVersion";

    private static readonly string CredentialsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Cymatics");
    private static readonly string CredentialsFile =
        Path.Combine(CredentialsDir, "credentials.dat");
    // Legacy plaintext credentials path (for migration)
    private static readonly string LegacyCredentialsFile =
        Path.Combine(CredentialsDir, "credentials.json");

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    // MARK: - Verification

    public static async Task<VerifyResult> VerifyAsync(string email, string password)
    {
        var appVersion = System.Reflection.Assembly.GetExecutingAssembly()
            .GetName().Version?.ToString(2) ?? "1.0";

        var payload = new { email, password, product_slug = ProductSlug, app_version = appVersion };
        var response = await Http.PostAsJsonAsync(WorkerUrl, payload);
        var body = await response.Content.ReadFromJsonAsync<VerifyResponse>();

        if (body is null)
            return new VerifyResult(false, "server_error", null, null, null);

        return new VerifyResult(body.AccessGranted, body.Reason, body.ViewPlansUrl,
                                body.LatestVersion, body.UpdateUrl);
    }

    // MARK: - Credential Storage (DPAPI)

    public static void SaveCredentials(string email, string password)
    {
        Directory.CreateDirectory(CredentialsDir);

        var json = JsonSerializer.Serialize(new StoredCredentials { Email = email, Password = password });
        var plainBytes = Encoding.UTF8.GetBytes(json);
        var encrypted = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(CredentialsFile, encrypted);

        // Remove legacy plaintext file if it exists
        if (File.Exists(LegacyCredentialsFile))
            try { File.Delete(LegacyCredentialsFile); } catch { }
    }

    public static StoredCredentials? LoadCredentials()
    {
        // Try DPAPI-encrypted file first
        if (File.Exists(CredentialsFile))
        {
            try
            {
                var encrypted = File.ReadAllBytes(CredentialsFile);
                var plainBytes = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
                var json = Encoding.UTF8.GetString(plainBytes);
                var data = JsonSerializer.Deserialize<StoredCredentials>(json);
                if (data is not null && !string.IsNullOrEmpty(data.Email) && !string.IsNullOrEmpty(data.Password))
                    return data;
            }
            catch { }
        }

        // Fall back to legacy Base64 file and migrate
        if (File.Exists(LegacyCredentialsFile))
        {
            try
            {
                var json = File.ReadAllText(LegacyCredentialsFile);
                var data = JsonSerializer.Deserialize<StoredCredentials>(json);
                if (data is not null && !string.IsNullOrEmpty(data.Email) && !string.IsNullOrEmpty(data.Password))
                {
                    // Decode Base64 password from legacy format
                    data.Password = Encoding.UTF8.GetString(Convert.FromBase64String(data.Password));
                    // Migrate to DPAPI
                    SaveCredentials(data.Email, data.Password);
                    return data;
                }
            }
            catch { }
        }

        return null;
    }

    public static void ClearCredentials()
    {
        if (File.Exists(CredentialsFile))
            try { File.Delete(CredentialsFile); } catch { }
        if (File.Exists(LegacyCredentialsFile))
            try { File.Delete(LegacyCredentialsFile); } catch { }
    }

    // MARK: - Grace Period (Registry)

    public static void MarkVerificationSuccess()
    {
        using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
        key.SetValue(LastVerifiedValue, DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());
    }

    public static bool IsWithinGracePeriod()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryPath);
        if (key?.GetValue(LastVerifiedValue) is not string val) return false;
        if (!long.TryParse(val, out var lastVerified)) return false;
        var elapsed = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - lastVerified;
        return elapsed < GracePeriodSeconds;
    }

    public static void ClearGracePeriod()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryPath, writable: true);
        key?.DeleteValue(LastVerifiedValue, throwOnMissingValue: false);
    }

    // MARK: - Update Check

    public static string? GetDismissedUpdateVersion()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryPath);
        return key?.GetValue(DismissedUpdateValue) as string;
    }

    public static void SetDismissedUpdateVersion(string version)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
        key.SetValue(DismissedUpdateValue, version);
    }

    public static string? GetCurrentVersion()
    {
        return System.Reflection.Assembly.GetExecutingAssembly()
            .GetName().Version?.ToString(2) ?? "1.0";
    }

    public static bool IsVersionNewer(string latest, string current)
    {
        var partsA = latest.Split('.').Select(s => int.TryParse(s, out var v) ? v : 0).ToArray();
        var partsB = current.Split('.').Select(s => int.TryParse(s, out var v) ? v : 0).ToArray();
        var maxLen = Math.Max(partsA.Length, partsB.Length);
        for (int i = 0; i < maxLen; i++)
        {
            var va = i < partsA.Length ? partsA[i] : 0;
            var vb = i < partsB.Length ? partsB[i] : 0;
            if (va > vb) return true;
            if (va < vb) return false;
        }
        return false;
    }
}

public record VerifyResult(bool AccessGranted, string? Reason, string? ViewPlansUrl,
                           string? LatestVersion, string? UpdateUrl);

public class StoredCredentials
{
    [JsonPropertyName("email")]
    public string Email { get; set; } = "";

    [JsonPropertyName("password")]
    public string Password { get; set; } = "";
}

public class VerifyResponse
{
    [JsonPropertyName("access_granted")]
    public bool AccessGranted { get; set; }

    [JsonPropertyName("reason")]
    public string? Reason { get; set; }

    [JsonPropertyName("view_plans_url")]
    public string? ViewPlansUrl { get; set; }

    [JsonPropertyName("latest_version")]
    public string? LatestVersion { get; set; }

    [JsonPropertyName("update_url")]
    public string? UpdateUrl { get; set; }
}
