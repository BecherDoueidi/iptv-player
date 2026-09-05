import Foundation
import SwiftData

/// Separate from the disposable Movie/TVSeries provider-mirror tables — title/poster
/// are snapshotted here so a favorite stays meaningful even across a catalog resync,
/// per the architecture's "user data survives content wipes" principle.
@Model
public class Favorite {
    @Attribute(.unique) public var contentKey: String
    public var kindRaw: String
    public var title: String
    public var posterURLString: String?
    public var addedAt: Date

    public init(contentKey: String, kind: ContentKind, title: String, posterURLString: String? = nil, addedAt: Date = .now) {
        self.contentKey = contentKey
        self.kindRaw = kind.rawValue
        self.title = title
        self.posterURLString = posterURLString
        self.addedAt = addedAt
    }

    public var kind: ContentKind {
        ContentKind(rawValue: kindRaw) ?? .movie
    }

    public var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
}
