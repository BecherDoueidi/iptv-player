import Foundation
import SwiftData

// Named `TVSeries`/`TVSeason`/`TVEpisode` rather than bare `Series`/`Season`/`Episode`
// as a precaution — a plain `Category` model collided with an unrelated type visible
// once the app target's frameworks were linked in (see MediaCategory's history).

/// Series → Season → Episode is the one genuine `@Relationship` tree in the schema —
/// unlike the soft-keyed engagement tables (favorites, downloads, progress), this is a
/// real hierarchy that's always loaded together, so SwiftData relationships fit here.
@Model
public class TVSeries {
    @Attribute(.unique) public var contentKey: String
    public var providerID: String
    public var title: String
    public var posterURLString: String?
    public var backdropURLString: String?
    public var plot: String?
    public var genre: String?
    public var rating: Double?
    public var categoryID: String?
    public var lastSyncedAt: Date

    @Relationship(deleteRule: .cascade) public var seasons: [TVSeason] = []

    public init(
        contentKey: String,
        providerID: String,
        title: String,
        posterURLString: String? = nil,
        backdropURLString: String? = nil,
        plot: String? = nil,
        genre: String? = nil,
        rating: Double? = nil,
        categoryID: String? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.contentKey = contentKey
        self.providerID = providerID
        self.title = title
        self.posterURLString = posterURLString
        self.backdropURLString = backdropURLString
        self.plot = plot
        self.genre = genre
        self.rating = rating
        self.categoryID = categoryID
        self.lastSyncedAt = lastSyncedAt
    }

    public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
    public var backdropURL: URL? { backdropURLString.flatMap(URL.init(string:)) }
}

@Model
public class TVSeason {
    public var seasonNumber: Int

    @Relationship(deleteRule: .cascade) public var episodes: [TVEpisode] = []

    public init(seasonNumber: Int, episodes: [TVEpisode] = []) {
        self.seasonNumber = seasonNumber
        self.episodes = episodes
    }
}

@Model
public class TVEpisode {
    @Attribute(.unique) public var contentKey: String
    public var providerID: String
    public var episodeNumber: Int
    public var title: String
    public var containerExtension: String?

    public init(
        contentKey: String,
        providerID: String,
        episodeNumber: Int,
        title: String,
        containerExtension: String? = nil
    ) {
        self.contentKey = contentKey
        self.providerID = providerID
        self.episodeNumber = episodeNumber
        self.title = title
        self.containerExtension = containerExtension
    }
}
