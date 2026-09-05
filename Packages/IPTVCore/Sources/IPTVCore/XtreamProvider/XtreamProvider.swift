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

    public func fetchMovieCategories(credentials: XtreamCredentials) async throws -> [MediaCategory] {
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

    public func fetchSeriesCategories(credentials: XtreamCredentials) async throws -> [MediaCategory] {
        let dtos = try await apiClient.fetchSeriesCategories(credentials: credentials)
        return XtreamMapper.makeCategories(from: dtos)
    }

    public func fetchSeries(credentials: XtreamCredentials, categoryID: String?) async throws -> [SeriesSummary] {
        let dtos = try await apiClient.fetchSeries(credentials: credentials, categoryID: categoryID)
        return XtreamMapper.makeSeriesSummaries(from: dtos)
    }

    public func fetchSeriesDetail(credentials: XtreamCredentials, seriesID: String) async throws -> SeriesDetail {
        let response = try await apiClient.fetchSeriesDetail(credentials: credentials, seriesID: seriesID)
        return XtreamMapper.makeSeriesDetail(id: seriesID, from: response)
    }

    public func movieStreamURL(credentials: XtreamCredentials, movieID: String, containerExtension: String?) -> URL? {
        XtreamURLBuilder.movieStreamURL(credentials: credentials, movieID: movieID, containerExtension: containerExtension)
    }

    public func episodeStreamURL(credentials: XtreamCredentials, episodeID: String, containerExtension: String?) -> URL? {
        XtreamURLBuilder.episodeStreamURL(credentials: credentials, episodeID: episodeID, containerExtension: containerExtension)
    }
}
