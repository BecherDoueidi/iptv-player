using System.IO;
using System.Text.Json;

namespace IPTVPlayer.Desktop.Core;

/// <summary>
/// Local mirror of the catalog, so the app opens instantly and stays browsable when
/// the panel is slow or unreachable.
///
/// Categories are cached alongside the titles, not treated as cheap-to-refetch. They
/// are the navigation: on iOS, leaving them out meant a failed refresh produced a
/// screen with nothing to click, even though the content behind those sections was
/// already on disk. Same mistake is not worth making twice.
/// </summary>
public sealed class CatalogCache(string sourceId)
{
    private static readonly string Root = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "IPTVPlayer", "cache");

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = false };

    private string PathFor(string name) => Path.Combine(Root, $"{sourceId}.{name}.json");

    public async Task SaveAsync<T>(string name, T value)
    {
        try
        {
            Directory.CreateDirectory(Root);
            // Written to a temporary file and moved into place, so an interrupted write
            // can't leave a half-written cache that fails to parse on next launch.
            var temporary = PathFor(name) + ".tmp";
            await using (var stream = File.Create(temporary))
            {
                await JsonSerializer.SerializeAsync(stream, value, Options);
            }
            File.Move(temporary, PathFor(name), overwrite: true);
        }
        catch (IOException)
        {
            // A cache write failing is not worth interrupting the user over; the app
            // works without it, just slower on next launch.
        }
    }

    public async Task<T?> LoadAsync<T>(string name)
    {
        var path = PathFor(name);
        if (!File.Exists(path)) return default;
        try
        {
            await using var stream = File.OpenRead(path);
            return await JsonSerializer.DeserializeAsync<T>(stream);
        }
        catch (Exception ex) when (ex is JsonException or IOException)
        {
            return default;
        }
    }

    public void Clear()
    {
        if (!Directory.Exists(Root)) return;
        foreach (var file in Directory.EnumerateFiles(Root, $"{sourceId}.*.json"))
        {
            try { File.Delete(file); } catch (IOException) { }
        }
    }
}
