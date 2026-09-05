import SwiftUI
import SwiftData
import IPTVCore

struct CollectionDetailView: View {
    let collection: MediaCollection
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if collection.itemKeys.isEmpty {
                Text("Nothing in this collection yet.").foregroundStyle(.secondary)
            } else {
                ForEach(collection.itemKeys, id: \.self) { key in
                    NavigationLink {
                        destinationView(for: key)
                    } label: {
                        Text(title(for: key))
                    }
                }
                .onDelete(perform: removeItems)
            }
        }
        .navigationTitle(collection.name)
    }

    private func removeItems(at offsets: IndexSet) {
        collection.itemKeys.remove(atOffsets: offsets)
        try? modelContext.save()
    }

    private func title(for contentKey: String) -> String {
        if let movie = fetchMovie(contentKey) { return movie.title }
        if let series = fetchSeries(contentKey) { return series.title }
        return "Unknown"
    }

    @ViewBuilder
    private func destinationView(for contentKey: String) -> some View {
        if let movie = fetchMovie(contentKey) {
            MovieDetailView(movie: summary(for: movie), account: account, dependencies: dependencies)
        } else if let series = fetchSeries(contentKey) {
            SeriesDetailView(series: summary(for: series), account: account, dependencies: dependencies)
        } else {
            Text("Content not found").foregroundStyle(.secondary)
        }
    }

    private func fetchMovie(_ contentKey: String) -> Movie? {
        try? modelContext.fetch(FetchDescriptor<Movie>(predicate: #Predicate { $0.contentKey == contentKey })).first
    }

    private func fetchSeries(_ contentKey: String) -> TVSeries? {
        try? modelContext.fetch(FetchDescriptor<TVSeries>(predicate: #Predicate { $0.contentKey == contentKey })).first
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
