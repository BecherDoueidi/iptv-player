import SwiftUI
import SwiftData
import IPTVCore

struct LibraryView: View {
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]
    @Query(sort: \MediaCollection.createdAt, order: .reverse) private var collections: [MediaCollection]
    @Environment(\.modelContext) private var modelContext

    @State private var showingNewCollectionAlert = false
    @State private var newCollectionName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Favorites") {
                    if favorites.isEmpty {
                        Text("No favorites yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites) { favorite in
                            NavigationLink {
                                destinationView(for: favorite.contentKey)
                            } label: {
                                Text(favorite.title)
                            }
                        }
                        .onDelete(perform: removeFavorites)
                    }
                }

                Section("Collections") {
                    ForEach(collections) { collection in
                        NavigationLink {
                            CollectionDetailView(collection: collection, account: account, dependencies: dependencies)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(collection.name)
                                Text("\(collection.itemKeys.count) item\(collection.itemKeys.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: removeCollections)

                    Button("New Collection…") {
                        showingNewCollectionAlert = true
                    }
                }
            }
            .navigationTitle("Library")
            .alert("New Collection", isPresented: $showingNewCollectionAlert) {
                TextField("Name", text: $newCollectionName)
                Button("Create", action: createCollection)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
        }
    }

    private func removeFavorites(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
        try? modelContext.save()
    }

    private func removeCollections(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(collections[index])
        }
        try? modelContext.save()
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        newCollectionName = ""
        guard !name.isEmpty else { return }
        modelContext.insert(MediaCollection(name: name))
        try? modelContext.save()
    }

    @ViewBuilder
    private func destinationView(for contentKey: String) -> some View {
        if let movie = try? modelContext.fetch(FetchDescriptor<Movie>(predicate: #Predicate { $0.contentKey == contentKey })).first {
            MovieDetailView(
                movie: MovieSummary(
                    id: movie.providerID,
                    categoryID: movie.categoryID,
                    title: movie.title,
                    posterURL: movie.posterURL,
                    containerExtension: movie.containerExtension,
                    rating: movie.rating,
                    addedAt: movie.addedAt
                ),
                account: account,
                dependencies: dependencies
            )
        } else if let series = try? modelContext.fetch(FetchDescriptor<TVSeries>(predicate: #Predicate { $0.contentKey == contentKey })).first {
            SeriesDetailView(
                series: SeriesSummary(
                    id: series.providerID,
                    categoryID: series.categoryID,
                    title: series.title,
                    posterURL: series.posterURL,
                    backdropURL: series.backdropURL,
                    plot: series.plot,
                    genre: series.genre,
                    rating: series.rating
                ),
                account: account,
                dependencies: dependencies
            )
        } else {
            Text("Content not found").foregroundStyle(.secondary)
        }
    }
}
