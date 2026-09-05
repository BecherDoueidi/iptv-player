import SwiftUI
import SwiftData
import IPTVCore

/// Favorite toggle, 1-5 star rating, "Not Interested," and "Add to Collection" — the
/// same personal-organization controls apply to both movies and series, so this is
/// shared rather than duplicated across MovieDetailView/SeriesDetailView.
struct LibraryControlsView: View {
    let contentKey: String
    let kind: ContentKind
    let title: String
    let posterURL: URL?

    @Environment(\.modelContext) private var modelContext
    @Query private var favoriteRows: [Favorite]
    @Query private var ratingRows: [Rating]
    @Query(sort: \MediaCollection.createdAt) private var collections: [MediaCollection]

    @State private var showingNewCollectionAlert = false
    @State private var newCollectionName = ""

    init(contentKey: String, kind: ContentKind, title: String, posterURL: URL?) {
        self.contentKey = contentKey
        self.kind = kind
        self.title = title
        self.posterURL = posterURL
        _favoriteRows = Query(filter: #Predicate<Favorite> { $0.contentKey == contentKey })
        _ratingRows = Query(filter: #Predicate<Rating> { $0.contentKey == contentKey })
    }

    private var isFavorite: Bool { !favoriteRows.isEmpty }
    private var rating: Rating? { ratingRows.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                Button(action: toggleFavorite) {
                    Label(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                }
                .tint(isFavorite ? .red : .secondary)

                Button(action: toggleNotInterested) {
                    Label("Not Interested", systemImage: rating?.notInterested == true ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .tint(rating?.notInterested == true ? .orange : .secondary)

                Menu {
                    ForEach(collections) { collection in
                        Button {
                            toggleCollectionMembership(collection)
                        } label: {
                            if collection.itemKeys.contains(contentKey) {
                                Label(collection.name, systemImage: "checkmark")
                            } else {
                                Text(collection.name)
                            }
                        }
                    }
                    Button("New Collection…") { showingNewCollectionAlert = true }
                } label: {
                    Label("Add to Collection", systemImage: "folder.badge.plus")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= (rating?.stars ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .onTapGesture { setStars(star) }
                }
            }
        }
        .alert("New Collection", isPresented: $showingNewCollectionAlert) {
            TextField("Name", text: $newCollectionName)
            Button("Create", action: createCollectionAndAdd)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
        }
    }

    private func toggleFavorite() {
        Haptics.light()
        if let existing = favoriteRows.first {
            modelContext.delete(existing)
        } else {
            modelContext.insert(Favorite(contentKey: contentKey, kind: kind, title: title, posterURLString: posterURL?.absoluteString))
        }
        try? modelContext.save()
    }

    private func setStars(_ stars: Int) {
        if let existing = rating {
            existing.stars = (existing.stars == stars) ? nil : stars
            existing.ratedAt = .now
        } else {
            modelContext.insert(Rating(contentKey: contentKey, stars: stars))
        }
        try? modelContext.save()
    }

    private func toggleNotInterested() {
        if let existing = rating {
            existing.notInterested.toggle()
            existing.ratedAt = .now
        } else {
            modelContext.insert(Rating(contentKey: contentKey, notInterested: true))
        }
        try? modelContext.save()
    }

    private func toggleCollectionMembership(_ collection: MediaCollection) {
        if collection.itemKeys.contains(contentKey) {
            collection.itemKeys.removeAll { $0 == contentKey }
        } else {
            collection.itemKeys.append(contentKey)
        }
        try? modelContext.save()
    }

    private func createCollectionAndAdd() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        newCollectionName = ""
        guard !name.isEmpty else { return }
        modelContext.insert(MediaCollection(name: name, itemKeys: [contentKey]))
        try? modelContext.save()
    }
}
