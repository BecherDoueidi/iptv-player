import Foundation

/// Xtream's stream URL conventions: `/movie/{user}/{pass}/{id}.{ext}` and
/// `/series/{user}/{pass}/{episode_id}.{ext}` — distinct from the `player_api.php`
/// JSON API, and quarantined here so nothing outside `XtreamProvider/` needs to know
/// this convention exists.
enum XtreamURLBuilder {
    static func movieStreamURL(credentials: XtreamCredentials, movieID: String, containerExtension: String?) -> URL? {
        buildStreamURL(credentials: credentials, kind: "movie", id: movieID, containerExtension: containerExtension)
    }

    static func episodeStreamURL(credentials: XtreamCredentials, episodeID: String, containerExtension: String?) -> URL? {
        buildStreamURL(credentials: credentials, kind: "series", id: episodeID, containerExtension: containerExtension)
    }

    /// Live channels are served as MPEG-TS at `/live/{user}/{pass}/{id}.ts`. TS rather
    /// than the panel's `.m3u8` alternative because VLC handles the raw transport
    /// stream directly and it starts noticeably faster than an HLS playlist.
    static func liveStreamURL(credentials: XtreamCredentials, channelID: String) -> URL? {
        buildStreamURL(credentials: credentials, kind: "live", id: channelID, containerExtension: "ts")
    }

    private static func buildStreamURL(
        credentials: XtreamCredentials,
        kind: String,
        id: String,
        containerExtension: String?
    ) -> URL? {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let ext = (containerExtension?.isEmpty == false) ? containerExtension! : "mp4"

        // Percent-encode each path segment individually and assign via
        // `percentEncodedPath` rather than interpolating raw strings into `.path` —
        // a username/password containing "/", "%", "+", "@", etc. (not unheard of for
        // Xtream panel-generated credentials) would otherwise corrupt the path
        // structure or silently produce a URL the server rejects.
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let user = credentials.username.addingPercentEncoding(withAllowedCharacters: allowed),
              let pass = credentials.password.addingPercentEncoding(withAllowedCharacters: allowed),
              let safeID = id.addingPercentEncoding(withAllowedCharacters: allowed),
              let safeExt = ext.addingPercentEncoding(withAllowedCharacters: allowed)
        else {
            return nil
        }

        components.percentEncodedPath = "/\(kind)/\(user)/\(pass)/\(safeID).\(safeExt)"
        components.queryItems = nil
        return components.url
    }
}
