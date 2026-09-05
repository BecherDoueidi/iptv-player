import Foundation

/// Unlike movies, Xtream's series list endpoint (`get_series`) already includes
/// plot/genre/rating/backdrop up front — no separate per-title call is needed just
/// to browse. `get_series_info` (see `SeriesDetail`) is only needed for episodes.
public struct SeriesSummary: Identifiable, Equatable, Hashable {
    public let id: String
    public let categoryID: String?
    public let title: String
    public let posterURL: URL?
    public let backdropURL: URL?
    public let plot: String?
    public let genre: String?
    public let rating: Double?

    public init(
        id: String,
        categoryID: String?,
        title: String,
        posterURL: URL?,
        backdropURL: URL?,
        plot: String?,
        genre: String?,
        rating: Double?
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.plot = plot
        self.genre = genre
        self.rating = rating
    }
}
