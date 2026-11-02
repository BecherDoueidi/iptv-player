using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace IPTVPlayer.Desktop.Core;

/// <summary>
/// The Windows equivalent of the iOS app's Keychain wrapper. Credentials are encrypted
/// with DPAPI under the current Windows user, so the file is unreadable to other
/// accounts on the machine and useless if copied elsewhere.
///
/// Provider credentials are secrets: they are never written in plaintext, never logged,
/// and never shown in the UI beyond the username.
/// </summary>
public sealed class CredentialStore
{
    private static readonly string Directory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "IPTVPlayer");

    private static readonly string FilePath = Path.Combine(Directory, "credentials.bin");

    private sealed record Stored(string ServerUrl, string Username, string Password);

    public void Save(XtreamCredentials credentials)
    {
        System.IO.Directory.CreateDirectory(Directory);
        var payload = JsonSerializer.SerializeToUtf8Bytes(
            new Stored(credentials.ServerUrl.ToString(), credentials.Username, credentials.Password));
        var encrypted = ProtectedData.Protect(payload, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(FilePath, encrypted);
    }

    public XtreamCredentials? Load()
    {
        if (!File.Exists(FilePath)) return null;
        try
        {
            var decrypted = ProtectedData.Unprotect(File.ReadAllBytes(FilePath), null, DataProtectionScope.CurrentUser);
            var stored = JsonSerializer.Deserialize<Stored>(decrypted);
            if (stored is null || !Uri.TryCreate(stored.ServerUrl, UriKind.Absolute, out var url)) return null;
            return new XtreamCredentials(url, stored.Username, stored.Password);
        }
        catch (Exception ex) when (ex is CryptographicException or JsonException)
        {
            // Written by a different Windows user, or corrupted. Treat as signed out
            // rather than crashing the app on launch.
            return null;
        }
    }

    public void Clear()
    {
        if (File.Exists(FilePath)) File.Delete(FilePath);
    }

    /// <summary>
    /// Normalises what someone types into the login box. A bare "example.com:8080"
    /// is not a valid URI, and demanding the scheme is a pointless thing to fail on.
    /// </summary>
    public static Uri? NormaliseServerUrl(string input)
    {
        var trimmed = input.Trim();
        if (trimmed.Length == 0) return null;
        if (!trimmed.Contains("://", StringComparison.Ordinal)) trimmed = "http://" + trimmed;
        trimmed = trimmed.TrimEnd('/');
        return Uri.TryCreate(trimmed, UriKind.Absolute, out var url)
            && (url.Scheme == Uri.UriSchemeHttp || url.Scheme == Uri.UriSchemeHttps)
            ? url
            : null;
    }
}
