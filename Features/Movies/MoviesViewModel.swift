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

    private func persist(_ summaries: [MovieSummary], modelContext: ModelContext) {
        for summary in summaries {
            let key = ContentKey.make(sourceID: account.sourceID, kind: .movie, providerID: summary.id)
            let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.contentKey == key })
            let existing = try? modelContext.fetch(descriptor).first

            if let existing {
                existing.title = summary.title
                existing.posterURLString = summary.posterURL?.absoluteString
                existing.categoryID = summary.categoryID
                existing.containerExtension = summary.containerExtension
                existing.rating = summary.rating
                existing.addedAt = summary.addedAt
                existing.lastSyncedAt = .now
            } else {
                modelContext.insert(Movie(
                    contentKey: key,
                    providerID: summary.id,
                    title: summary.title,
                    posterURLString: summary.posterURL?.absoluteString,
                    rating: summary.rating,
                    containerExtension: summary.containerExtension,
                    categoryID: summary.categoryID,
                    addedAt: summary.addedAt
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
