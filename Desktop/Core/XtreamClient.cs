using System.Net.Http;
using System.Text.Json;
using System.Web;

namespace IPTVPlayer.Desktop.Core;

public sealed class XtreamException(string message) : Exception(message);

/// <summary>
/// Everything Xtream-specific lives behind this class: the <c>player_api.php</c>
/// conventions, the stream URL shapes, and the panel quirks. Nothing outside Core
/// needs to know the provider is Xtream.
/// </summary>
public sealed class XtreamClient(HttpClient? httpClient = null)
{
    private readonly HttpClient _http = httpClient ?? CreateHttpClient();

    private static HttpClient CreateHttpClient()
    {
        // One connection to the panel, matching the iOS app. These accounts cap
        // concurrent connections and answer anything over the cap with a bare 404,
        // so a burst of parallel requests fails rather than going faster.
        var handler = new SocketsHttpHandler { MaxConnectionsPerServer = 1 };
        var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(60) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("VLC/3.0.20 LibVLC/3.0.20");
        return client;
    }

    public async Task<AccountInfo> AuthenticateAsync(XtreamCredentials credentials, CancellationToken ct = default)
    {
        var root = await GetJsonAsync(credentials, null, ct);
        if (!root.TryGetProperty("user_info", out var userInfo))
        {
            return new AccountInfo(false, null, null, null, null, "The server didn't return account details.");
        }

        var expiresRaw = XtreamJson.String(userInfo, "exp_date");
        DateTimeOffset? expiresAt = long.TryParse(expiresRaw, out var epoch)
            ? DateTimeOffset.FromUnixTimeSeconds(epoch)
            : null;

        return new AccountInfo(
            IsAuthenticated: XtreamJson.Int(userInfo, "auth") == 1,
            Status: XtreamJson.String(userInfo, "status"),
            ExpiresAt: expiresAt,
            ActiveConnections: XtreamJson.Int(userInfo, "active_cons"),
            MaxConnections: XtreamJson.Int(userInfo, "max_connections"),
            Message: XtreamJson.String(userInfo, "message"));
    }

    public async Task<List<MediaCategory>> GetCategoriesAsync(
        XtreamCredentials credentials, ContentKind kind, CancellationToken ct = default)
    {
        var action = kind switch
        {
            ContentKind.Movie => "get_vod_categories",
            ContentKind.Series => "get_series_categories",
            _ => "get_live_categories"
        };

        var root = await GetJsonAsync(credentials, action, ct);
        var categories = new List<MediaCategory>();
        foreach (var item in XtreamJson.Array(root))
        {
            var id = XtreamJson.String(item, "category_id");
            var name = XtreamJson.String(item, "category_name");
            if (id is null || name is null) continue;
            categories.Add(new MediaCategory(id, name));
        }
        return categories;
    }

    public async Task<List<MovieSummary>> GetMoviesAsync(XtreamCredentials credentials, CancellationToken ct = default)
    {
        var root = await GetJsonAsync(credentials, "get_vod_streams", ct);
        var movies = new List<MovieSummary>();
        foreach (var item in XtreamJson.Array(root))
        {
            var id = XtreamJson.String(item, "stream_id");
            var title = XtreamJson.String(item, "name");
            if (id is null || title is null) continue;
            movies.Add(new MovieSummary(
                id,
                XtreamJson.String(item, "category_id"),
                title,
                XtreamJson.NonEmptyString(item, "stream_icon"),
                XtreamJson.NonEmptyString(item, "container_extension"),
                XtreamJson.Double(item, "rating")));
        }
        return movies;
    }

    public async Task<List<SeriesSummary>> GetSeriesAsync(XtreamCredentials credentials, CancellationToken ct = default)
    {
        var root = await GetJsonAsync(credentials, "get_series", ct);
        var series = new List<SeriesSummary>();
        foreach (var item in XtreamJson.Array(root))
        {
            var id = XtreamJson.String(item, "series_id");
            var title = XtreamJson.String(item, "name");
            if (id is null || title is null) continue;
            series.Add(new SeriesSummary(
                id,
                XtreamJson.String(item, "category_id"),
                title,
                XtreamJson.NonEmptyString(item, "cover"),
                XtreamJson.NonEmptyString(item, "plot"),
                XtreamJson.Double(item, "rating")));
        }
        return series;
    }

    public async Task<List<LiveChannelSummary>> GetLiveChannelsAsync(
        XtreamCredentials credentials, CancellationToken ct = default)
    {
        var root = await GetJsonAsync(credentials, "get_live_streams", ct);
        var channels = new List<LiveChannelSummary>();
        foreach (var item in XtreamJson.Array(root))
        {
            var id = XtreamJson.String(item, "stream_id");
            var name = XtreamJson.String(item, "name");
            if (id is null || name is null) continue;
            channels.Add(new LiveChannelSummary(
                id,
                XtreamJson.String(item, "category_id"),
                name,
                XtreamJson.NonEmptyString(item, "stream_icon"),
                XtreamJson.Int(item, "num")));
        }
        return channels;
    }

    /// <summary>
    /// <c>get_series_info</c> returns episodes as a dictionary keyed by season number.
    /// Some panels send <c>[]</c> instead of <c>{}</c> when a series has no episodes —
    /// a real observed quirk, tolerated as empty rather than thrown.
    /// </summary>
    public async Task<List<SeriesEpisode>> GetEpisodesAsync(
        XtreamCredentials credentials, string seriesId, CancellationToken ct = default)
    {
        var root = await GetJsonAsync(credentials, "get_series_info", ct,
            ("series_id", seriesId));

        var episodes = new List<SeriesEpisode>();
        if (!root.TryGetProperty("episodes", out var seasons) || seasons.ValueKind != JsonValueKind.Object)
        {
            return episodes;
        }

        foreach (var season in seasons.EnumerateObject())
        {
            if (!int.TryParse(season.Name, out var seasonNumber)) continue;
            foreach (var item in XtreamJson.Array(season.Value))
            {
                var id = XtreamJson.String(item, "id");
                var title = XtreamJson.String(item, "title");
                var number = XtreamJson.Int(item, "episode_num");
                if (id is null || title is null || number is null) continue;
                episodes.Add(new SeriesEpisode(
                    id,
                    XtreamJson.Int(item, "season") ?? seasonNumber,
                    number.Value,
                    title,
                    XtreamJson.NonEmptyString(item, "container_extension")));
            }
        }

        return episodes
            .OrderBy(e => e.SeasonNumber)
            .ThenBy(e => e.EpisodeNumber)
            .ToList();
    }

    // MARK: - URLs

    public static Uri MovieStreamUrl(XtreamCredentials credentials, string movieId, string? containerExtension)
        => StreamUrl(credentials, "movie", movieId, containerExtension ?? "mp4");

    public static Uri EpisodeStreamUrl(XtreamCredentials credentials, string episodeId, string? containerExtension)
        => StreamUrl(credentials, "series", episodeId, containerExtension ?? "mp4");

    /// <summary>Live is served as MPEG-TS, which VLC opens faster than the HLS alternative.</summary>
    public static Uri LiveStreamUrl(XtreamCredentials credentials, string channelId)
        => StreamUrl(credentials, "live", channelId, "ts");

    /// <summary>
    /// Each path segment is escaped individually. Panel-generated passwords really do
    /// contain "/", "+" and "@", and interpolating one raw would silently corrupt the
    /// path structure.
    /// </summary>
    private static Uri StreamUrl(XtreamCredentials credentials, string kind, string id, string extension)
    {
        var builder = new UriBuilder(credentials.ServerUrl)
        {
            Path = $"/{kind}/{Uri.EscapeDataString(credentials.Username)}"
                 + $"/{Uri.EscapeDataString(credentials.Password)}"
                 + $"/{Uri.EscapeDataString(id)}.{Uri.EscapeDataString(extension)}",
            Query = string.Empty
        };
        return builder.Uri;
    }

    /// <summary>Blanks the username and password segments for display in errors and logs.</summary>
    public static string Redact(Uri url)
    {
        var segments = url.AbsolutePath.Split('/');
        if (segments.Length >= 4)
        {
            segments[2] = "***";
            segments[3] = "***";
        }
        return $"{url.Scheme}://{url.Authority}{string.Join('/', segments)}";
    }

    private async Task<JsonElement> GetJsonAsync(
        XtreamCredentials credentials,
        string? action,
        CancellationToken ct,
        params (string Key, string Value)[] extraQuery)
    {
        var query = HttpUtility.ParseQueryString(string.Empty);
        query["username"] = credentials.Username;
        query["password"] = credentials.Password;
        if (action is not null) query["action"] = action;
        foreach (var (key, value) in extraQuery) query[key] = value;

        var builder = new UriBuilder(credentials.ServerUrl)
        {
            Path = "/player_api.php",
            Query = query.ToString()
        };

        HttpResponseMessage response;
        try
        {
            response = await _http.GetAsync(builder.Uri, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            throw new XtreamException($"Couldn't reach the server: {ex.Message}");
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new XtreamException($"The server returned an error (HTTP {(int)response.StatusCode}).");
        }

        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(ct);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            return document.RootElement.Clone();
        }
        catch (JsonException)
        {
            throw new XtreamException("The server sent back something that wasn't valid data.");
        }
    }
}
