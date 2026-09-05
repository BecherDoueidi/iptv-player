import Foundation
import Observation
import SwiftData
import IPTVCore

@Observable
final class MoviesViewModel {
    private(set) var categories: [MediaCategory] = []
    private(set) var movies: [MovieSummary] = []
    private(set) var continueWatching: [MovieSummary] = []
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

    var filteredMovies: [MovieSummary] {
        movies.filter { movie in
            let matchesCategory = selectedCategoryID == nil || movie.categoryID == selectedCategoryID
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
            let matchesSearch = trimmedSearch.isEmpty || movie.title.localizedCaseInsensitiveContains(trimmedSearch)
            return matchesCategory && matchesSearch
        }
    }

    @MainActor
    func loadIfNeeded(modelContext: ModelContext) async {
        guard movies.isEmpty, !isLoading else { return }
        loadFromCache(modelContext: modelContext)
        await refresh(modelContext: modelContext)
    }

    /// Populates from persisted data first so the catalog is browsable offline (or
    /// while the network refresh below is still in flight / fails). Category filter
    /// chips aren't cached (categories are never persisted, only movies are), so
    /// they won't appear until a successful network refresh — an acceptable
    /// offline-mode trade-off, not a bug.
    private func loadFromCache(modelContext: ModelContext) {
        guard let cached = try? modelContext.fetch(FetchDescriptor<Movie>()) else { return }
        let prefix = "\(account.sourceID)|movie|"
        let relevant = cached.filter { $0.contentKey.hasPrefix(prefix) }
        guard !relevant.isEmpty else { return }
        movies = relevant.map { movie in
            MovieSummary(
                id: movie.providerID,
                categoryID: movie.categoryID,
                title: movie.title,
                posterURL: movie.posterURL,
                containerExtension: movie.containerExtension,
                rating: movie.rating,
                addedAt: movie.addedAt
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
            async let categoriesTask = dependencies.mediaProvider.fetchMovieCategories(credentials: credentials)
            async let moviesTask = dependencies.mediaProvider.fetchMovies(credentials: credentials, categoryID: nil)
            let (fetchedCategories, fetchedMovies) = try await (categoriesTask, moviesTask)

            categories = fetchedCategories
            movies = fetchedMovies
            persist(fetchedMovies, modelContext: modelContext)
        } catch {
            errorMessage = Self.errorMessage(for: error)
        }
    }

    /// Movies-only for now (episodes have their own progress rows too, but a unified
    /// cross-media Continue Watching row is deferred to a later polish pass — this
    /// still satisfies "most-recent-incomplete first" ordering for the Movies tab).
    @MainActor
    func loadContinueWatching(modelContext: ModelContext) {
        let progressDescriptor = FetchDescriptor<WatchProgress>(
            predicate: #Predicate { !$0.isCompleted },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        guard let allProgress = try? modelContext.fetch(progressDescriptor) else { return }

        let prefix = "\(account.sourceID)|movie|"
        let relevant = allProgress.filter { $0.contentKey.hasPrefix(prefix) }

        guard let allMovies = try? modelContext.fetch(FetchDescriptor<Movie>()) else { return }
        let movieByKey = Dictionary(uniqueKeysWithValues: allMovies.map { ($0.contentKey, $0) })

        continueWatching = Array(relevant.compactMap { progress -> MovieSummary? in
            guard let movie = movieByKey[progress.contentKey] else { return nil }
            return MovieSummary(
                id: movie.providerID,
                categoryID: movie.categoryID,
                title: movie.title,
                posterURL: movie.posterURL,
                containerExtension: movie.containerExtension,
                rating: movie.rating,
                addedAt: movie.addedAt
            )
        }.prefix(10))
    }

    /// One bulk fetch + in-memory dictionary lookup, not a query per movie — a
    /// per-item FetchDescriptor here froze the app on any catalog of real-world
    /// size (Xtream panels commonly list thousands of VOD entries), since this
    /// runs synchronously on the main actor.
    private func persist(_ summaries: [MovieSummary], modelContext: ModelContext) {
        let existingMovies = (try? modelContext.fetch(FetchDescriptor<Movie>())) ?? []
        var moviesByKey = Dictionary(uniqueKeysWithValues: existingMovies.map { ($0.contentKey, $0) })

        for summary in summaries {
            let key = ContentKey.make(sourceID: account.sourceID, kind: .movie, providerID: summary.id)

            if let existing = moviesByKey[key] {
                existing.title = summary.title
                existing.posterURLString = summary.posterURL?.absoluteString
                existing.categoryID = summary.categoryID
                existing.containerExtension = summary.containerExtension
                existing.rating = summary.rating
                existing.addedAt = summary.addedAt
                existing.lastSyncedAt = .now
            } else {
                let movie = Movie(
                    contentKey: key,
                    providerID: summary.id,
                    title: summary.title,
                    posterURLString: summary.posterURL?.absoluteString,
                    rating: summary.rating,
                    containerExtension: summary.containerExtension,
                    categoryID: summary.categoryID,
                    addedAt: summary.addedAt
                )
                modelContext.insert(movie)
                moviesByKey[key] = movie
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
