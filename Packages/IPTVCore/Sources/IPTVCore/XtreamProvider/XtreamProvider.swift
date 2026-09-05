import Foundation

public final class XtreamProvider: MediaProvider {
    private let apiClient: XtreamAPIClient

    public init(urlSession: URLSession = .shared) {
        self.apiClient = XtreamAPIClient(urlSession: urlSession)
    }

    public func authenticate(credentials: XtreamCredentials) async throws -> AccountInfo {
        let response = try await apiClient.fetchAuthResponse(credentials: credentials)
        return XtreamMapper.makeAccountInfo(from: response)
    }

    public func fetchMovieCategories(credentials: XtreamCredentials) async throws -> [Category] {
        let dtos = try await apiClient.fetchMovieCategories(credentials: credentials)
        return XtreamMapper.makeCategories(from: dtos)
    }

    public func fetchMovies(credentials: XtreamCredentials, categoryID: String?) async throws -> [MovieSummary] {
        let dtos = try await apiClient.fetchMovies(credentials: credentials, categoryID: categoryID)
        return XtreamMapper.makeMovieSummaries(from: dtos)
    }

    public func fetchMovieDetail(credentials: XtreamCredentials, movieID: String) async throws -> MovieDetail {
        let response = try await apiClient.fetchMovieDetail(credentials: credentials, movieID: movieID)
        return XtreamMapper.makeMovieDetail(id: movieID, from: response)
    }
}
