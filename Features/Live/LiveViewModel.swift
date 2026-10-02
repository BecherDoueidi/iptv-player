import Foundation
import Observation
import SwiftData
import IPTVCore

@Observable
final class LiveViewModel {
    private(set) var categories: [MediaCategory] = []
    private(set) var channels: [LiveChannelSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var searchText: String = ""

    /// Provider IDs of recently played channels, most recent first.
    private(set) var historyIDs: [String] = []

    /// Content keys of favorited channels, refreshed from the store rather than
    /// observed with `@Query` — the list is filtered by it, and a per-row query on a
    /// list this long is exactly the pattern that froze the catalog screens.
    private(set) var favoriteKeys: Set<String> = []
    /// Recomputed whenever the channel list, favourites or history change — never per
    /// row. Live lists are the largest in the app, so this matters most here.
    private(set) var sectionCounts = SectionCounts()

    private static let historyLimit = 50

    private let dependencies: AppDependencies
    private let account: ProviderAccount
    private let credentials: XtreamCredentials?

    init(dependencies: AppDependencies, account: ProviderAccount) {
        self.dependencies = dependencies
        self.account = account
        self.credentials = try? dependencies.credentialStore.loadCredentials()
    }

    func contentKey(for channel: LiveChannelSummary) -> String {
        ContentKey.make(sourceID: account.sourceID, kind: .live, providerID: channel.id)
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Search deliberately spans every channel, not just the section being viewed —
    /// looking for a channel by name and being shown "no results" because you happened
    /// to be inside one category is the wrong behaviour.
    var searchResults: [LiveChannelSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var sections: [LiveSection] {
        [.all, .favorites, .history] + categories.map { .category(id: $0.id, name: $0.name) }
    }

    func channels(in section: LiveSection) -> [LiveChannelSummary] {
        switch section {
        case .all:
            return channels
        case .favorites:
            return channels.filter { favoriteKeys.contains(contentKey(for: $0)) }
        case .history:
            // Ordered by when they were played, not by channel number.
            let byID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return historyIDs.compactMap { byID[$0] }
        case .category(let id, _):
            return channels.filter { $0.categoryID == id }
        }
    }

    func channelCount(in section: LiveSection) -> Int {
        switch section {
        case .all: return sectionCounts.total
        case .favorites: return sectionCounts.favorites
        case .history: return sectionCounts.history
        case .category(let id, _): return sectionCounts.count(forCategory: id)
        }
    }

    @MainActor
    private func recomputeSectionCounts() {
        sectionCounts = SectionCounts(
            items: channels,
            itemID: \.id,
            categoryID: \.categoryID,
            isFavorite: { self.favoriteKeys.contains(self.contentKey(for: $0)) },
            historyIDs: historyIDs
        )
    }

    func streamURL(for channel: LiveChannelSummary) -> URL? {
        guard let credentials else { return nil }
        return dependencies.mediaProvider.liveStreamURL(credentials: credentials, channelID: channel.id)
    }

    func shortEPG(for channel: LiveChannelSummary) async throws -> [EPGEntry] {
        guard let credentials else { return [] }
        return try await dependencies.mediaProvider.fetchShortEPG(credentials: credentials, channelID: channel.id)
    }

    @MainActor
    func loadIfNeeded(modelContext: ModelContext) async {
        guard channels.isEmpty, !isLoading else { return }
        await loadFromCache()
        loadFavorites(modelContext: modelContext)
        loadHistory(modelContext: modelContext)
        await refresh()
    }

    @MainActor
    func loadFavorites(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Favorite>()
        guard let favorites = try? modelContext.fetch(descriptor) else { return }
        favoriteKeys = Set(favorites.map(\.contentKey))
        recomputeSectionCounts()
    }

    @MainActor
    func loadHistory(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<LiveChannel>(
            predicate: #Predicate { $0.lastPlayedAt != nil },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.historyLimit
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        let prefix = "\(account.sourceID)|live|"
        historyIDs = rows.filter { $0.contentKey.hasPrefix(prefix) }.map(\.providerID)
        recomputeSectionCounts()
    }

    /// Recorded when playback starts. One targeted fetch per tap is fine here — unlike
    /// the per-row lookups that froze the catalog screens, this runs once on a tap.
    @MainActor
    func recordPlayback(of channel: LiveChannelSummary, modelContext: ModelContext) {
        let key = contentKey(for: channel)
        let descriptor = FetchDescriptor<LiveChannel>(predicate: #Predicate { $0.contentKey == key })
        guard let row = try? modelContext.fetch(descriptor).first else { return }
        row.lastPlayedAt = .now
        try? modelContext.save()

        historyIDs.removeAll { $0 == channel.id }
        historyIDs.insert(channel.id, at: 0)
        if historyIDs.count > Self.historyLimit {
            historyIDs.removeLast(historyIDs.count - Self.historyLimit)
        }
        recomputeSectionCounts()
    }

    @MainActor
    func toggleFavorite(_ channel: LiveChannelSummary, modelContext: ModelContext) {
        let key = contentKey(for: channel)
        let descriptor = FetchDescriptor<Favorite>(predicate: #Predicate { $0.contentKey == key })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            favoriteKeys.remove(key)
        } else {
            modelContext.insert(Favorite(
                contentKey: key,
                kind: .live,
                title: channel.name,
                posterURLString: channel.logoURL?.absoluteString
            ))
            favoriteKeys.insert(key)
        }
        try? modelContext.save()
        recomputeSectionCounts()
    }

    /// Populates from persisted data first so the channel list is browsable while the
    /// network refresh is in flight, or if it fails.
    @MainActor
    private func loadFromCache() async {
        let cached = await dependencies.catalogStore.cachedLiveChannels(sourceID: account.sourceID)
        // Sections come from the cache first. They are the navigation, so a slow
        // or failed refresh must not leave the screen with nothing on it.
        categories = await dependencies.catalogStore.cachedCategories(sourceID: account.sourceID, kind: .live)
        guard !cached.isEmpty else { return }
        channels = cached.sorted { ($0.number ?? .max, $0.name) < ($1.number ?? .max, $1.name) }
        recomputeSectionCounts()
    }

    @MainActor
    func refresh() async {
        guard let credentials else {
            errorMessage = "Missing saved credentials — please sign in again."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let categoriesTask = dependencies.mediaProvider.fetchLiveCategories(credentials: credentials)
            async let channelsTask = dependencies.mediaProvider.fetchLiveChannels(credentials: credentials, categoryID: nil)
            let (fetchedCategories, fetchedChannels) = try await (categoriesTask, channelsTask)

            // An empty list from a flaky refresh must not wipe sections that are
            // already on screen — keep the last known good set instead.
            if !fetchedCategories.isEmpty {
                categories = fetchedCategories
            }
            channels = fetchedChannels.sorted { ($0.number ?? .max, $0.name) < ($1.number ?? .max, $1.name) }
            recomputeSectionCounts()
            // Deliberately not awaited: the list is already on screen, and the write is
            // only about the next cold start.
            Task {
                await dependencies.catalogStore.persistLiveChannels(fetchedChannels, sourceID: account.sourceID)
                await dependencies.catalogStore.persistCategories(
                    fetchedCategories,
                    sourceID: account.sourceID,
                    kind: .live
                )
            }
        } catch {
            errorMessage = Self.errorMessage(for: error)
        }
    }

    private static func errorMessage(for error: Error) -> String {
        if let apiError = error as? XtreamAPIError {
            switch apiError {
            case .invalidServerURL: return "That server address doesn't look right."
            case .network(let message): return "Couldn't reach the server: \(message)"
            case .unexpectedResponse: return "The server sent back something unexpected."
            case .httpStatus(let code): return "Server returned an error (HTTP \(code))."
            }
        }
        return "Something went wrong: \(error.localizedDescription)"
    }
}
