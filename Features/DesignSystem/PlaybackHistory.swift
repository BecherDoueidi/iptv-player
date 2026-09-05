import Foundation
import SwiftData
import IPTVCore

/// Records what was last played, driving the History section on each catalog tab.
///
/// The timestamp lives on the provider-mirror row (Movie / TVSeries / LiveChannel)
/// rather than in its own table, because a "last watched" time is worthless once the
/// title is gone from the provider — it should disappear with it.
enum PlaybackHistory {
    @MainActor
    static func recordMovie(contentKey: String, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.contentKey == contentKey })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.lastPlayedAt = .now
        try? modelContext.save()
    }

    /// Recorded against the *series*, not the episode — "what was I watching" means the
    /// show, and an episode row would make the section a list of near-duplicates.
    @MainActor
    static func recordSeries(contentKey: String, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TVSeries>(predicate: #Predicate { $0.contentKey == contentKey })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.lastPlayedAt = .now
        try? modelContext.save()
    }
}
