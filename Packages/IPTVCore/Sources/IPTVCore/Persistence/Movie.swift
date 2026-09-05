import Foundation
import SwiftData

/// A local mirror of one provider movie. Disposable and safe to wipe/resync — user
/// data (favorites, ratings, downloads, progress) lives in separate tables keyed by
/// the same `contentKey` so it survives a resync of this table.
@Model
public class Movie {
    @Attribute(.unique) public var contentKey: String
    public var providerID: String
    public var title: String
    public var posterURLString: String?
    public var backdropURLString: String?
    public var plot: String?
    public var genre: String?
    public var releaseDate: String?
    public var durationSeconds: Int?
    public var rating: Double?
    public var containerExtension: String?
    public var categoryID: String?
    public var addedAt: Date?
    public var lastSyncedAt: Date

    public init(
        contentKey: String,
        providerID: String,
        title: String,
        posterURLString: String? = nil,
        backdropURLString: String? = nil,
        plot: String? = nil,
        genre: String? = nil,
        releaseDate: String? = nil,
        durationSeconds: Int? = nil,
        rating: Double? = nil,
        containerExtension: String? = nil,
        categoryID: String? = nil,
        addedAt: Date? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.contentKey = contentKey
        self.providerID = providerID
        self.title = title
        self.posterURLString = posterURLString
        self.backdropURLString = backdropURLString
        self.plot = plot
        self.genre = genre
        self.releaseDate = releaseDate
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.containerExtension = containerExtension
        self.categoryID = categoryID
        self.addedAt = addedAt
        self.lastSyncedAt = lastSyncedAt
    }

    public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
    public var backdropURL: URL? { backdropURLString.flatMap(URL.init(string:)) }
}
