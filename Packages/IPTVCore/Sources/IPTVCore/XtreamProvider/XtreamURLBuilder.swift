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
        components.path = "/\(kind)/\(credentials.username)/\(credentials.password)/\(id).\(ext)"
        components.queryItems = nil
        return components.url
    }
}
