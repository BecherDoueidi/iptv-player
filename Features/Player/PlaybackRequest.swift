import Foundation

/// Identifiable wrapper so `.fullScreenCover(item:)` can present the player.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let contentKey: String
}
