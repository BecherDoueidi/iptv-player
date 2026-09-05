import Foundation
import SwiftData

/// Keyed by `contentKey` (movie or episode) — the backbone of resume playback and
/// Continue Watching ordering.
@Model
public class WatchProgress {
    @Attribute(.unique) public var contentKey: String
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var lastPlayedAt: Date
    public var isCompleted: Bool

    public init(
        contentKey: String,
        positionSeconds: Double,
        durationSeconds: Double,
        lastPlayedAt: Date = .now,
        isCompleted: Bool = false
    ) {
        self.contentKey = contentKey
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.lastPlayedAt = lastPlayedAt
        self.isCompleted = isCompleted
    }
}
