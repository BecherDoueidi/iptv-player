import Foundation

/// Fields from Xtream's per-title call (`get_vod_info`), fetched on demand when a
/// movie's detail screen appears rather than for the whole catalog up front.
public struct MovieDetail: Equatable {
    public let id: String
    public let plot: String?
    public let genre: String?
    public let releaseDate: String?
    public let durationSeconds: Int?
    public let backdropURL: URL?
    public let rating: Double?

    public init(
        id: String,
        plot: String?,
        genre: String?,
        releaseDate: String?,
        durationSeconds: Int?,
        backdropURL: URL?,
        rating: Double?
    ) {
        self.id = id
        self.plot = plot
        self.genre = genre
        self.releaseDate = releaseDate
        self.durationSeconds = durationSeconds
        self.backdropURL = backdropURL
        self.rating = rating
    }
}
