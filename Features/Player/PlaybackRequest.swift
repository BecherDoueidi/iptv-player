import Foundation

/// Identifiable wrapper so `.fullScreenCover(item:)` can present the player.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let contentKey: String
    /// A live channel has no duration, no meaningful position, and nothing to resume —
    /// the player hides its scrubber and skips watch-progress tracking for these.
    var isLive: Bool = false
}
