using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MixLink.App;

public sealed class LicenseService
{
    private const string WorkerUrl = "https://license-verification-worker.teamcymatics.workers.dev/verify-license";
    private const string ProductSlug = "mix-link";

    private static readonly string CredentialsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Cymatics");
    private static readonly string CredentialsFile =
        Path.Combine(CredentialsDir, "credentials.json");

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    public static async Task<VerifyResult> VerifyAsync(string email, string password)
    {
        var payload = new { email, password, product_slug = ProductSlug };
        var response = await Http.PostAsJsonAsync(WorkerUrl, payload);
        var body = await response.Content.ReadFromJsonAsync<VerifyResponse>();

        if (body is null)
            return new VerifyResult(false, "server_error", null);

        return new VerifyResult(body.AccessGranted, body.Reason, body.ViewPlansUrl);
    }

    public static void SaveCredentials(string email, string password)
    {
        Directory.CreateDirectory(CredentialsDir);

        var data = new StoredCredentials
        {
            Email = email,
            Password = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(password))
        };

        var json = JsonSerializer.Serialize(data);
        File.WriteAllText(CredentialsFile, json);
    }

    public static StoredCredentials? LoadCredentials()
    {
        if (!File.Exists(CredentialsFile))
            return null;

        try
        {
            var json = File.ReadAllText(CredentialsFile);
            var data = JsonSerializer.Deserialize<StoredCredentials>(json);
            if (data is null || string.IsNullOrEmpty(data.Email) || string.IsNullOrEmpty(data.Password))
                return null;

            data.Password = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(data.Password));
            return data;
        }
        catch
        {
            return null;
        }
    }

    public static void ClearCredentials()
    {
        if (File.Exists(CredentialsFile))
            File.Delete(CredentialsFile);
    }
}

public record VerifyResult(bool AccessGranted, string? Reason, string? ViewPlansUrl);

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
}
