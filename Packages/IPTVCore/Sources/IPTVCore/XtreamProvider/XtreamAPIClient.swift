import Foundation

public enum XtreamAPIError: Error, Equatable {
    case invalidServerURL
    case network(String)
    case unexpectedResponse
    case httpStatus(Int)
}

actor XtreamAPIClient {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchAuthResponse(credentials: XtreamCredentials) async throws -> XtreamAuthResponseDTO {
        try await fetch(credentials: credentials, extraQueryItems: [])
    }

    func fetchMovieCategories(credentials: XtreamCredentials) async throws -> [XtreamCategoryDTO] {
        try await fetch(
            credentials: credentials,
            extraQueryItems: [URLQueryItem(name: "action", value: "get_vod_categories")]
        )
    }

    func fetchMovies(credentials: XtreamCredentials, categoryID: String?) async throws -> [XtreamVodStreamDTO] {
        var items = [URLQueryItem(name: "action", value: "get_vod_streams")]
        if let categoryID {
            items.append(URLQueryItem(name: "category_id", value: categoryID))
        }
        return try await fetch(credentials: credentials, extraQueryItems: items)
    }

    func fetchMovieDetail(credentials: XtreamCredentials, movieID: String) async throws -> XtreamVodInfoResponseDTO {
        try await fetch(credentials: credentials, extraQueryItems: [
            URLQueryItem(name: "action", value: "get_vod_info"),
            URLQueryItem(name: "vod_id", value: movieID)
        ])
    }

    func fetchSeriesCategories(credentials: XtreamCredentials) async throws -> [XtreamCategoryDTO] {
        try await fetch(
            credentials: credentials,
            extraQueryItems: [URLQueryItem(name: "action", value: "get_series_categories")]
        )
    }

    func fetchSeries(credentials: XtreamCredentials, categoryID: String?) async throws -> [XtreamSeriesDTO] {
        var items = [URLQueryItem(name: "action", value: "get_series")]
        if let categoryID {
            items.append(URLQueryItem(name: "category_id", value: categoryID))
        }
        return try await fetch(credentials: credentials, extraQueryItems: items)
    }

    func fetchSeriesDetail(credentials: XtreamCredentials, seriesID: String) async throws -> XtreamSeriesInfoResponseDTO {
        try await fetch(credentials: credentials, extraQueryItems: [
            URLQueryItem(name: "action", value: "get_series_info"),
            URLQueryItem(name: "series_id", value: seriesID)
        ])
    }

    private func fetch<T: Decodable>(credentials: XtreamCredentials, extraQueryItems: [URLQueryItem]) async throws -> T {
        let url = try Self.playerAPIURL(credentials: credentials, extraQueryItems: extraQueryItems)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            throw XtreamAPIError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XtreamAPIError.unexpectedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw XtreamAPIError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XtreamAPIError.unexpectedResponse
        }
    }

    /// `player_api.php` with no `action` query item is the standard Xtream auth-check call;
    /// other endpoints add an `action` (and sometimes further) query items on top of it.
    static func playerAPIURL(credentials: XtreamCredentials, extraQueryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw XtreamAPIError.invalidServerURL
        }
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password)
        ] + extraQueryItems
        guard let url = components.url else {
            throw XtreamAPIError.invalidServerURL
        }
        return url
    }
}
