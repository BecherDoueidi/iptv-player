import Foundation
import Observation
import SwiftData
import IPTVCore

@Observable
final class MoviesViewModel {
    private(set) var categories: [MediaCategory] = []
    private(set) var movies: [MovieSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var searchText: String = ""

    /// Content keys of favourited movies, and provider IDs of recently played ones
    /// (most recent first). Both refreshed from the store rather than observed with
    /// `@Query` — a per-row query on a catalog this size is what froze the app.
    private(set) var favoriteKeys: Set<String> = []
    private(set) var historyIDs: [String] = []

    private static let historyLimit = 50

    private let dependencies: AppDependencies
    private let account: ProviderAccount
    private let credentials: XtreamCredentials?

    init(dependencies: AppDependencies, account: ProviderAccount) {
        self.dependencies = dependencies
        self.account = account
        self.credentials = try? dependencies.credentialStore.loadCredentials()
    }

    func contentKey(for movie: MovieSummary) -> String {
        ContentKey.make(sourceID: account.sourceID, kind: .movie, providerID: movie.id)
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Search spans the whole catalog, not the section being viewed — being told "no
    /// results" for a film that exists, because of which section you were in, is wrong.
    var searchResults: [MovieSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return movies.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var sections: [CatalogSection] {
        [.all(title: "All Movies"), .favorites, .history] + categories.map { .category(id: $0.id, name: $0.name) }
    }

    func movies(in section: CatalogSection) -> [MovieSummary] {
        switch section {
        case .all:
            return movies
        case .favorites:
            return movies.filter { favoriteKeys.contains(contentKey(for: $0)) }
        case .history:
            let byID = Dictionary(movies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return historyIDs.compactMap { byID[$0] }
        case .category(let id, _):
            return movies.filter { $0.categoryID == id }
        }
    }

    func movieCount(in section: CatalogSection) -> Int {
        movies(in: section).count
    }

    @MainActor
    func loadFavorites(modelContext: ModelContext) {
        guard let favorites = try? modelContext.fetch(FetchDescriptor<Favorite>()) else { return }
        favoriteKeys = Set(favorites.map(\.contentKey))
    }

    @MainActor
    func loadHistory(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.lastPlayedAt != nil },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.historyLimit
        guard let rows = try? modelContext.fetch(descriptor) else { return }
        let prefix = "\(account.sourceID)|movie|"
        historyIDs = rows.filter { $0.contentKey.hasPrefix(prefix) }.map(\.providerID)
    }

    @MainActor
    func loadIfNeeded(modelContext: ModelContext) async {
        guard movies.isEmpty, !isLoading else { return }
        loadFromCache(modelContext: modelContext)
        loadFavorites(modelContext: modelContext)
        loadHistory(modelContext: modelContext)
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
