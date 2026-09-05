import Foundation

/// Fields available from Xtream's catalog list call (`get_vod_streams`). Full
/// plot/genre/etc. require a separate per-title call — see `MovieDetail`.
public struct MovieSummary: Identifiable, Equatable, Hashable {
    public let id: String
    public let categoryID: String?
    public let title: String
    public let posterURL: URL?
    public let containerExtension: String?
    public let rating: Double?
    public let addedAt: Date?

    public init(
        id: String,
        categoryID: String?,
        title: String,
        posterURL: URL?,
        containerExtension: String?,
        rating: Double?,
        addedAt: Date?
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.posterURL = posterURL
        self.containerExtension = containerExtension
        self.rating = rating
        self.addedAt = addedAt
    }
}
