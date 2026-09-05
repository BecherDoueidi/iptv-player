import SwiftUI
import SwiftData
import IPTVCore

/// Case-insensitive substring match over the locally cached catalog — tolerates case
/// differences and partial titles per the spec, without sending anything off-device.
struct SearchView: View {
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Query private var allMovies: [Movie]
    @Query private var allSeries: [TVSeries]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView("Search Your Library", systemImage: "magnifyingglass")
                } else if filteredMovies.isEmpty && filteredSeries.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No matches for \"\(trimmedQuery)\"")
                    )
                } else {
                    if !filteredMovies.isEmpty {
                        Section("Movies") {
                            ForEach(filteredMovies) { movie in
                                NavigationLink {
                                    MovieDetailView(movie: summary(for: movie), account: account, dependencies: dependencies)
                                } label: {
                                    Text(movie.title)
                                }
                            }
                        }
                    }
                    if !filteredSeries.isEmpty {
                        Section("Series") {
                            ForEach(filteredSeries) { series in
                                NavigationLink {
                                    SeriesDetailView(series: summary(for: series), account: account, dependencies: dependencies)
                                } label: {
                                    Text(series.title)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredMovies: [Movie] {
        guard !trimmedQuery.isEmpty else { return [] }
        let prefix = "\(account.sourceID)|movie|"
        return allMovies.filter { $0.contentKey.hasPrefix(prefix) && $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var filteredSeries: [TVSeries] {
        guard !trimmedQuery.isEmpty else { return [] }
        let prefix = "\(account.sourceID)|series|"
        return allSeries.filter { $0.contentKey.hasPrefix(prefix) && $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private func summary(for movie: Movie) -> MovieSummary {
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

    private func summary(for series: TVSeries) -> SeriesSummary {
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
