import Foundation
import Observation
import SwiftData
import IPTVCore

@Observable
final class SeriesViewModel {
    private(set) var categories: [MediaCategory] = []
    private(set) var seriesList: [SeriesSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var searchText: String = ""

    /// Content keys of favourited series, and provider IDs of recently played ones
    /// (most recent first). Refreshed from the store rather than observed with
    /// `@Query` — a per-row query on a catalog this size is what froze the app.
    private(set) var favoriteKeys: Set<String> = []
    private(set) var historyIDs: [String] = []
    /// Recomputed whenever the catalog, favourites or history change — never per row.
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

    func contentKey(for series: SeriesSummary) -> String {
        ContentKey.make(sourceID: account.sourceID, kind: .series, providerID: series.id)
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Search spans the whole catalog, not the section being viewed.
    var searchResults: [SeriesSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return seriesList.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var sections: [CatalogSection] {
        [.all(title: "All Series"), .favorites, .history] + categories.map { .category(id: $0.id, name: $0.name) }
    }

    func series(in section: CatalogSection) -> [SeriesSummary] {
        switch section {
        case .all:
            return seriesList
        case .favorites:
            return seriesList.filter { favoriteKeys.contains(contentKey(for: $0)) }
        case .history:
            let byID = Dictionary(seriesList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return historyIDs.compactMap { byID[$0] }
        case .category(let id, _):
            return seriesList.filter { $0.categoryID == id }
        }
    }

    func seriesCount(in section: CatalogSection) -> Int {
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
            items: seriesList,
            itemID: \.id,
            categoryID: \.categoryID,
            isFavorite: { self.favoriteKeys.contains(self.contentKey(for: $0)) },
            historyIDs: historyIDs
        )
    }

    @MainActor
    func loadFavorites(modelContext: ModelContext) {
        guard let favorites = try? modelContext.fetch(FetchDescriptor<Favorite>()) else { return }
        favoriteKeys = Set(favorites.map(\.contentKey))
        recomputeSectionCounts()
    }

    @MainActor
    func loadHistory(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<TVSeries>(
            predicate: #Predicate { $0.lastPlayedAt != nil },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.historyLimit
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        let prefix = "\(account.sourceID)|series|"
        historyIDs = rows.filter { $0.contentKey.hasPrefix(prefix) }.map(\.providerID)
        recomputeSectionCounts()
    }

    @MainActor
    func loadIfNeeded(modelContext: ModelContext) async {
        guard seriesList.isEmpty, !isLoading else { return }
        await loadFromCache()
        loadFavorites(modelContext: modelContext)
        loadHistory(modelContext: modelContext)
        await refresh()
    }

    /// Populates from persisted data first so the catalog is browsable offline (or
    /// while the network refresh below is still in flight / fails).
    @MainActor
    private func loadFromCache() async {
        let cached = await dependencies.catalogStore.cachedSeries(sourceID: account.sourceID)
        // Sections come from the cache first. They are the navigation, so a slow
        // or failed refresh must not leave the screen with nothing on it.
        categories = await dependencies.catalogStore.cachedCategories(sourceID: account.sourceID, kind: .series)
        guard !cached.isEmpty else { return }
        seriesList = cached
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
            async let categoriesTask = dependencies.mediaProvider.fetchSeriesCategories(credentials: credentials)
            async let seriesTask = dependencies.mediaProvider.fetchSeries(credentials: credentials, categoryID: nil)
            let (fetchedCategories, fetchedSeries) = try await (categoriesTask, seriesTask)

            // An empty list from a flaky refresh must not wipe sections that are
            // already on screen — keep the last known good set instead.
            if !fetchedCategories.isEmpty {
                categories = fetchedCategories
            }
            seriesList = fetchedSeries
            recomputeSectionCounts()
            // Deliberately not awaited: the catalog is already on screen, and the
            // write is only about the next cold start.
            Task {
                await dependencies.catalogStore.persistSeries(fetchedSeries, sourceID: account.sourceID)
                await dependencies.catalogStore.persistCategories(
                    fetchedCategories,
                    sourceID: account.sourceID,
                    kind: .series
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
