import Foundation
import SwiftData

/// User-curated folder of content. `itemKeys` is a simple ordered list of
/// `contentKey`s — SwiftData stores value-type arrays directly, so no many-to-many
/// join table is needed for what's really just a list the user curates by hand.
///
/// Named `MediaCollection`, not `Collection` — the latter is a core Swift standard
/// library protocol name and would collide (see MediaCategory's own naming history).
@Model
public class MediaCollection {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public var itemKeys: [String]

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now, itemKeys: [String] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.itemKeys = itemKeys
    }
}
