import Foundation
import SwiftData

/// A local mirror of one provider category (a section row on a catalog screen).
///
/// Originally categories were deliberately not persisted — only the titles were — on
/// the reasoning that they were cheap to refetch. That was wrong once categories
/// became the *navigation*: a failed or slow refresh left the user staring at a screen
/// with no sections at all, even though the content behind them was cached and ready.
@Model
public class CatalogCategory {
    /// `sourceID|kind|providerID` — same namespacing as ContentKey, so two providers
    /// (or movie and series categories that share an id) can never collide.
    @Attribute(.unique) public var id: String
    public var sourceID: String
    public var kindRaw: String
    public var providerID: String
    public var name: String
    /// Position in the provider's own ordering, preserved so sections don't shuffle
    /// between launches.
    public var sortIndex: Int
    public var lastSyncedAt: Date

    public init(
        sourceID: String,
        kind: ContentKind,
        providerID: String,
        name: String,
        sortIndex: Int,
        lastSyncedAt: Date = .now
    ) {
        self.id = Self.makeID(sourceID: sourceID, kind: kind, providerID: providerID)
        self.sourceID = sourceID
        self.kindRaw = kind.rawValue
        self.providerID = providerID
        self.name = name
        self.sortIndex = sortIndex
        self.lastSyncedAt = lastSyncedAt
    }

    public static func makeID(sourceID: String, kind: ContentKind, providerID: String) -> String {
        "\(sourceID)|\(kind.rawValue)|\(providerID)"
    }

    public var kind: ContentKind {
        ContentKind(rawValue: kindRaw) ?? .movie
    }
}
