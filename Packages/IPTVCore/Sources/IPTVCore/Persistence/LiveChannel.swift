import Foundation
import SwiftData

/// A local mirror of one live channel. Disposable and safe to wipe/resync — favorites
/// live in their own table keyed by the same `contentKey`, so they survive a resync.
@Model
public class LiveChannel {
    @Attribute(.unique) public var contentKey: String
    public var providerID: String
    public var name: String
    public var logoURLString: String?
    public var categoryID: String?
    public var number: Int?
    public var epgChannelID: String?
    /// Drives the Channel History section. Kept on the mirror row rather than in its
    /// own table because it's worthless once the channel is gone from the provider.
    public var lastPlayedAt: Date?
    public var lastSyncedAt: Date

    public init(
        contentKey: String,
        providerID: String,
        name: String,
        logoURLString: String? = nil,
        categoryID: String? = nil,
        number: Int? = nil,
        epgChannelID: String? = nil,
        lastPlayedAt: Date? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.contentKey = contentKey
        self.providerID = providerID
        self.name = name
        self.logoURLString = logoURLString
        self.categoryID = categoryID
        self.number = number
        self.epgChannelID = epgChannelID
        self.lastPlayedAt = lastPlayedAt
        self.lastSyncedAt = lastSyncedAt
    }

    public var logoURL: URL? { logoURLString.flatMap(URL.init(string:)) }
}
