import Foundation
import SwiftUI
import SwiftData
import IPTVCore

final class AppDependencies {
    let credentialStore: CredentialStore
    let mediaProvider: MediaProvider
    let modelContainer: ModelContainer
    let downloadManager: DownloadManager

    init() {
        credentialStore = KeychainCredentialStore()
        mediaProvider = XtreamProvider()

        // Listed explicitly (not just the root ProviderAccount type) — SwiftData's
        // schema only auto-includes types reachable via @Relationship from what you
        // pass in, and Movie/TVSeries/WatchProgress/Download aren't related to it.
        let schemaTypes: [any PersistentModel.Type] = [
            ProviderAccount.self, Movie.self, TVSeries.self, TVSeason.self,
            TVEpisode.self, WatchProgress.self, Download.self
        ]
        if let container = try? ModelContainer(for: Schema(schemaTypes)) {
            modelContainer = container
        } else {
            // Should be unreachable for this schema — last-resort fallback so a rare
            // disk/schema issue degrades to a working, if non-persistent, app rather
            // than a hard crash at launch.
            modelContainer = try! ModelContainer(
                for: Schema(schemaTypes),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        downloadManager = DownloadManager()
        AppDelegate.downloadManager = downloadManager
    }

    /// `configure` touches `ModelContainer.mainContext`, which is main-actor-isolated —
    /// this can't run inside `init()` itself (AppDependencies.init() must stay
    /// nonisolated so `EnvironmentKey.defaultValue` below can construct it). Called once
    /// from IPTVPlayerApp's `.task` instead, which does run on the main actor.
    @MainActor
    func configureDownloadManagerIfNeeded() {
        downloadManager.configure(modelContext: modelContainer.mainContext)
    }
}

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies()
}

extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
