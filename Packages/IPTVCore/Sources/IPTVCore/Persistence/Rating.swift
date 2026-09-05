import Foundation
import SwiftData

/// Personal rating — never sent anywhere, purely local. `notInterested` is a separate
/// flag rather than a sentinel star value, so it doesn't collide with the 1-5 scale.
@Model
public class Rating {
    @Attribute(.unique) public var contentKey: String
    public var stars: Int?
    public var notInterested: Bool
    public var ratedAt: Date

    public init(contentKey: String, stars: Int? = nil, notInterested: Bool = false, ratedAt: Date = .now) {
        self.contentKey = contentKey
        self.stars = stars
        self.notInterested = notInterested
        self.ratedAt = ratedAt
    }
}
