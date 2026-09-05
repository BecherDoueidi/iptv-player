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
        await refresh(modelContext: modelContext)
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

    private func persist(_ summaries: [SeriesSummary], modelContext: ModelContext) {
        for summary in summaries {
            let key = ContentKey.make(sourceID: account.sourceID, kind: .series, providerID: summary.id)
            let descriptor = FetchDescriptor<TVSeries>(predicate: #Predicate { $0.contentKey == key })
            let existing = try? modelContext.fetch(descriptor).first

            if let existing {
                existing.title = summary.title
                existing.posterURLString = summary.posterURL?.absoluteString
                existing.backdropURLString = summary.backdropURL?.absoluteString
                existing.plot = summary.plot
                existing.genre = summary.genre
                existing.rating = summary.rating
                existing.categoryID = summary.categoryID
                existing.lastSyncedAt = .now
            } else {
                modelContext.insert(TVSeries(
                    contentKey: key,
                    providerID: summary.id,
                    title: summary.title,
                    posterURLString: summary.posterURL?.absoluteString,
                    backdropURLString: summary.backdropURL?.absoluteString,
                    plot: summary.plot,
                    genre: summary.genre,
                    rating: summary.rating,
                    categoryID: summary.categoryID
                ))
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
