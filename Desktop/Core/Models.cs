using System.Security.Cryptography;
using System.Text;

namespace IPTVPlayer.Desktop.Core;

public enum ContentKind { Movie, Series, Episode, Live }

public static class ContentKindExtensions
{
    public static string Raw(this ContentKind kind) => kind switch
    {
        ContentKind.Movie => "movie",
        ContentKind.Series => "series",
        ContentKind.Episode => "episode",
        ContentKind.Live => "live",
        _ => "movie"
    };
}

/// <summary>
/// <c>sourceID|kind|providerID</c>, carried over from the iOS app unchanged. The
/// namespacing is what stops two providers (or a movie and a channel that happen to
/// share an id) from colliding in the local store.
/// </summary>
public static class ContentKey
{
    public static string Make(string sourceId, ContentKind kind, string providerId)
        => $"{sourceId}|{kind.Raw()}|{providerId}";
}

public static class SourceId
{
    /// <summary>
    /// Stable hash of host:port and username, so the same account always resolves to
    /// the same local namespace and a different one never overlaps with it.
    /// </summary>
    public static string Make(Uri serverUrl, string username)
    {
        var host = serverUrl.Host.ToLowerInvariant();
        var port = serverUrl.IsDefaultPort ? "" : $":{serverUrl.Port}";
        var seed = $"{host}{port}|{username}";
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(seed));
        return Convert.ToHexString(bytes)[..16].ToLowerInvariant();
    }
}

public sealed record XtreamCredentials(Uri ServerUrl, string Username, string Password);

public sealed record AccountInfo(
    bool IsAuthenticated,
    string? Status,
    DateTimeOffset? ExpiresAt,
    int? ActiveConnections,
    int? MaxConnections,
    string? Message);

public sealed record MediaCategory(string Id, string Name);

public sealed record MovieSummary(
    string Id,
    string? CategoryId,
    string Title,
    string? PosterUrl,
    string? ContainerExtension,
    double? Rating);

public sealed record SeriesSummary(
    string Id,
    string? CategoryId,
    string Title,
    string? PosterUrl,
    string? Plot,
    double? Rating);

public sealed record SeriesEpisode(
    string Id,
    int SeasonNumber,
    int EpisodeNumber,
    string Title,
    string? ContainerExtension);

public sealed record LiveChannelSummary(
    string Id,
    string? CategoryId,
    string Name,
    string? LogoUrl,
    int? Number);
