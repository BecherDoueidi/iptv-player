using System.Text.Json;

namespace IPTVPlayer.Desktop.Core;

/// <summary>
/// Real Xtream panels are inconsistent about whether numeric fields arrive as JSON
/// numbers or as strings, and it varies by panel fork and version. Every field is read
/// through these helpers so a quirky response degrades gracefully instead of throwing
/// away the whole catalog — the same approach the iOS app uses, for the same reason.
/// </summary>
public static class XtreamJson
{
    public static string? String(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.ToString(),
            _ => null
        };
    }

    public static int? Int(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)) return number;
        if (value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out var parsed)) return parsed;
        return null;
    }

    public static double? Double(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number)) return number;
        if (value.ValueKind == JsonValueKind.String && double.TryParse(value.GetString(), out var parsed)) return parsed;
        return null;
    }

    /// <summary>Empty strings are treated as absent — panels send "" rather than omitting.</summary>
    public static string? NonEmptyString(JsonElement element, string name)
    {
        var value = String(element, name);
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }

    public static IEnumerable<JsonElement> Array(JsonElement element)
        => element.ValueKind == JsonValueKind.Array ? element.EnumerateArray() : Enumerable.Empty<JsonElement>();
}
