import Foundation

// Named `SeriesSeason`/`SeriesEpisode` rather than bare `Season`/`Episode` — a plain
// `Category` type collided with something else visible in the app target's scope
// (see MediaCategory's history) once this SDK's app-target frameworks were linked in,
// so common single-word names are avoided here as a precaution.

public struct SeriesEpisode: Identifiable, Equatable, Hashable {
    public let id: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let title: String
    public let containerExtension: String?

    public init(id: String, seasonNumber: Int, episodeNumber: Int, title: String, containerExtension: String?) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.containerExtension = containerExtension
    }
}

public struct SeriesSeason: Identifiable, Equatable, Hashable {
    public let seasonNumber: Int
    public let episodes: [SeriesEpisode]
    public var id: Int { seasonNumber }

    public init(seasonNumber: Int, episodes: [SeriesEpisode]) {
        self.seasonNumber = seasonNumber
        self.episodes = episodes
    }
}

/// From Xtream's per-title call (`get_series_info`), fetched when a series' detail
/// screen appears — the list endpoint doesn't carry episodes.
public struct SeriesDetail: Equatable {
    public let id: String
    public let seasons: [SeriesSeason]

    public init(id: String, seasons: [SeriesSeason]) {
        self.id = id
        self.seasons = seasons
    }
}
