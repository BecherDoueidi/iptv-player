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
    var selectedCategoryID: String?
    var searchText: String = ""

    private let dependencies: AppDependencies
    private let account: ProviderAccount
    private let credentials: XtreamCredentials?

    init(dependencies: AppDependencies, account: ProviderAccount) {
        self.dependencies = dependencies
        self.account = account
        self.credentials = try? dependencies.credentialStore.loadCredentials()
    }

    var filteredSeries: [SeriesSummary] {
        seriesList.filter { series in
            let matchesCategory = selectedCategoryID == nil || series.categoryID == selectedCategoryID
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
            let matchesSearch = trimmedSearch.isEmpty || series.title.localizedCaseInsensitiveContains(trimmedSearch)
            return matchesCategory && matchesSearch
        }
    }

    @MainActor
    func loadIfNeeded(modelContext: ModelContext) async {
        guard seriesList.isEmpty, !isLoading else { return }
        loadFromCache(modelContext: modelContext)
        await refresh(modelContext: modelContext)
    }

    /// Populates from persisted data first so the catalog is browsable offline (or
    /// while the network refresh below is still in flight / fails).
    private func loadFromCache(modelContext: ModelContext) {
        guard let cached = try? modelContext.fetch(FetchDescriptor<TVSeries>()) else { return }
        let prefix = "\(account.sourceID)|series|"
        let relevant = cached.filter { $0.contentKey.hasPrefix(prefix) }
        guard !relevant.isEmpty else { return }
        seriesList = relevant.map { series in
            SeriesSummary(
                id: series.providerID,
                categoryID: series.categoryID,
                title: series.title,
                posterURL: series.posterURL,
                backdropURL: series.backdropURL,
                plot: series.plot,
                genre: series.genre,
                rating: series.rating
            )
        }
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
            async let categoriesTask = dependencies.mediaProvider.fetchSeriesCategories(credentials: credentials)
            async let seriesTask = dependencies.mediaProvider.fetchSeries(credentials: credentials, categoryID: nil)
            let (fetchedCategories, fetchedSeries) = try await (categoriesTask, seriesTask)

            categories = fetchedCategories
            seriesList = fetchedSeries
            persist(fetchedSeries, modelContext: modelContext)
        } catch {
            errorMessage = Self.errorMessage(for: error)
        }
    }

    /// One bulk fetch + in-memory dictionary lookup, not a query per series — see
    /// MoviesViewModel.persist for why (froze the app on any real-world catalog size).
    private func persist(_ summaries: [SeriesSummary], modelContext: ModelContext) {
        let existingSeries = (try? modelContext.fetch(FetchDescriptor<TVSeries>())) ?? []
        var seriesByKey = Dictionary(uniqueKeysWithValues: existingSeries.map { ($0.contentKey, $0) })

        for summary in summaries {
            let key = ContentKey.make(sourceID: account.sourceID, kind: .series, providerID: summary.id)

            if let existing = seriesByKey[key] {
                existing.title = summary.title
                existing.posterURLString = summary.posterURL?.absoluteString
                existing.backdropURLString = summary.backdropURL?.absoluteString
                existing.plot = summary.plot
                existing.genre = summary.genre
                existing.rating = summary.rating
                existing.categoryID = summary.categoryID
                existing.lastSyncedAt = .now
            } else {
                let series = TVSeries(
                    contentKey: key,
                    providerID: summary.id,
                    title: summary.title,
                    posterURLString: summary.posterURL?.absoluteString,
                    backdropURLString: summary.backdropURL?.absoluteString,
                    plot: summary.plot,
                    genre: summary.genre,
                    rating: summary.rating,
                    categoryID: summary.categoryID
                )
                modelContext.insert(series)
                seriesByKey[key] = series
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
