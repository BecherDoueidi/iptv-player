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
    var selectedCategoryID: String?
    var searchText: String = ""
    var favoritesOnly = false

    /// Content keys of favorited channels, refreshed from the store rather than
    /// observed with `@Query` — the list is filtered by it, and a per-row query on a
    /// list this long is exactly the pattern that froze the catalog screens.
    private(set) var favoriteKeys: Set<String> = []

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

    var filteredChannels: [LiveChannelSummary] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        return channels.filter { channel in
            let matchesCategory = selectedCategoryID == nil || channel.categoryID == selectedCategoryID
            let matchesSearch = trimmedSearch.isEmpty || channel.name.localizedCaseInsensitiveContains(trimmedSearch)
            let matchesFavorites = !favoritesOnly || favoriteKeys.contains(contentKey(for: channel))
            return matchesCategory && matchesSearch && matchesFavorites
        }
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
        loadFromCache(modelContext: modelContext)
        loadFavorites(modelContext: modelContext)
        await refresh(modelContext: modelContext)
    }

    @MainActor
    func loadFavorites(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Favorite>()
        guard let favorites = try? modelContext.fetch(descriptor) else { return }
        favoriteKeys = Set(favorites.map(\.contentKey))
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
    }

    /// Populates from persisted data first so the channel list is browsable while the
    /// network refresh is in flight, or if it fails.
    @MainActor
    private func loadFromCache(modelContext: ModelContext) {
        guard let cached = try? modelContext.fetch(FetchDescriptor<LiveChannel>()) else { return }
        let prefix = "\(account.sourceID)|live|"
        let relevant = cached.filter { $0.contentKey.hasPrefix(prefix) }
        guard !relevant.isEmpty else { return }
        channels = relevant
            .map {
                LiveChannelSummary(
                    id: $0.providerID,
                    categoryID: $0.categoryID,
                    name: $0.name,
                    logoURL: $0.logoURL,
                    number: $0.number,
                    epgChannelID: $0.epgChannelID
                )
            }
            .sorted { ($0.number ?? .max, $0.name) < ($1.number ?? .max, $1.name) }
    }

    @MainActor
    func refresh(modelContext: ModelContext) async {
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

            categories = fetchedCategories
            channels = fetchedChannels.sorted { ($0.number ?? .max, $0.name) < ($1.number ?? .max, $1.name) }
            persist(fetchedChannels, modelContext: modelContext)
        } catch {
            errorMessage = Self.errorMessage(for: error)
        }
    }

    /// One bulk fetch + in-memory dictionary, not a query per channel — panels list
    /// tens of thousands of live channels, and this runs on the main actor.
    @MainActor
    private func persist(_ summaries: [LiveChannelSummary], modelContext: ModelContext) {
        let existing = (try? modelContext.fetch(FetchDescriptor<LiveChannel>())) ?? []
        var byKey = Dictionary(existing.map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })

        for summary in summaries {
            let key = ContentKey.make(sourceID: account.sourceID, kind: .live, providerID: summary.id)
            if let row = byKey[key] {
                row.name = summary.name
                row.logoURLString = summary.logoURL?.absoluteString
                row.categoryID = summary.categoryID
                row.number = summary.number
                row.epgChannelID = summary.epgChannelID
                row.lastSyncedAt = .now
            } else {
                let row = LiveChannel(
                    contentKey: key,
                    providerID: summary.id,
                    name: summary.name,
                    logoURLString: summary.logoURL?.absoluteString,
                    categoryID: summary.categoryID,
                    number: summary.number,
                    epgChannelID: summary.epgChannelID
                )
                modelContext.insert(row)
                byKey[key] = row
            }
        }
        try? modelContext.save()
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
