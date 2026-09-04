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
        let url = try Self.playerAPIURL(credentials: credentials)

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
            return try JSONDecoder().decode(XtreamAuthResponseDTO.self, from: data)
        } catch {
            throw XtreamAPIError.unexpectedResponse
        }
    }

    /// `player_api.php` with no `action` query item is the standard Xtream auth-check call.
    static func playerAPIURL(credentials: XtreamCredentials) throws -> URL {
        guard var components = URLComponents(url: credentials.serverURL, resolvingAgainstBaseURL: false) else {
            throw XtreamAPIError.invalidServerURL
        }
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password)
        ]
        guard let url = components.url else {
            throw XtreamAPIError.invalidServerURL
        }
        return url
    }
}
