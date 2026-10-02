import Foundation
import SwiftData

/// Owns catalog reads and writes on a background executor.
///
/// A catalog sync touches thousands of rows: a full fetch, a diff against what arrived,
/// then inserts and property updates. Run on the main actor — as it was — that work
/// blocks the UI, which is what froze the app on first launch and on every tab switch.
///
/// Moving it here is safe precisely because nothing on screen reads these rows to
/// render: the view models hold their own arrays of value types, and the store is only
/// read at cold start to populate them. So the UI never waits on this actor.
@ModelActor
public actor CatalogStore {
    // MARK: - Reads

    public func cachedMovies(sourceID: String) -> [MovieSummary] {
        rows(ofType: Movie.self, sourceID: sourceID, kind: .movie).map { movie in
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

    public func cachedSeries(sourceID: String) -> [SeriesSummary] {
        rows(ofType: TVSeries.self, sourceID: sourceID, kind: .series).map { series in
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

    public func cachedLiveChannels(sourceID: String) -> [LiveChannelSummary] {
        rows(ofType: LiveChannel.self, sourceID: sourceID, kind: .live).map { channel in
            LiveChannelSummary(
                id: channel.providerID,
                categoryID: channel.categoryID,
                name: channel.name,
                logoURL: channel.logoURL,
                number: channel.number,
                epgChannelID: channel.epgChannelID
            )
        }
    }

    /// Categories are read back in the provider's own order, so sections stay put
    /// between launches instead of reshuffling.
    public func cachedCategories(sourceID: String, kind: ContentKind) -> [MediaCategory] {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<CatalogCategory>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.kindRaw == kindRaw },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        guard let rows = try? modelContext.fetch(descriptor) else { return [] }
        return rows.map { MediaCategory(id: $0.providerID, name: $0.name) }
    }

    // MARK: - Writes

    /// Replaces the stored set for this source and kind: categories the provider has
    /// dropped are removed, so a stale section can't linger forever pointing at
    /// nothing.
    public func persistCategories(_ categories: [MediaCategory], sourceID: String, kind: ContentKind) {
        guard !categories.isEmpty else { return }

        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<CatalogCategory>(
            predicate: #Predicate { $0.sourceID == sourceID && $0.kindRaw == kindRaw }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var liveIDs = Set<String>()
        for (index, category) in categories.enumerated() {
            let id = CatalogCategory.makeID(sourceID: sourceID, kind: kind, providerID: category.id)
            liveIDs.insert(id)
            if let row = byID[id] {
                guard row.name != category.name || row.sortIndex != index else { continue }
                row.name = category.name
                row.sortIndex = index
                row.lastSyncedAt = .now
            } else {
                let row = CatalogCategory(
                    sourceID: sourceID,
                    kind: kind,
                    providerID: category.id,
                    name: category.name,
                    sortIndex: index
                )
                modelContext.insert(row)
                byID[id] = row
            }
        }

        for row in existing where !liveIDs.contains(row.id) {
            modelContext.delete(row)
        }
        try? modelContext.save()
    }

    public func persistMovies(_ summaries: [MovieSummary], sourceID: String) {
        var byKey = existingByKey(ofType: Movie.self)
        var didChange = false

        for summary in summaries {
            let key = ContentKey.make(sourceID: sourceID, kind: .movie, providerID: summary.id)
            if let existing = byKey[key] {
                // Only touch a row whose values actually differ. SwiftData does real
                // work per mutation, and on a resync the overwhelming majority of a
                // catalog is unchanged.
                guard existing.title != summary.title
                    || existing.posterURLString != summary.posterURL?.absoluteString
                    || existing.categoryID != summary.categoryID
                    || existing.containerExtension != summary.containerExtension
                    || existing.rating != summary.rating
                    || existing.addedAt != summary.addedAt
                else { continue }

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
                byKey[key] = movie
            }
            didChange = true
        }

        saveIfNeeded(didChange)
    }

    public func persistSeries(_ summaries: [SeriesSummary], sourceID: String) {
        var byKey = existingByKey(ofType: TVSeries.self)
        var didChange = false

        for summary in summaries {
            let key = ContentKey.make(sourceID: sourceID, kind: .series, providerID: summary.id)
            if let existing = byKey[key] {
                guard existing.title != summary.title
                    || existing.posterURLString != summary.posterURL?.absoluteString
                    || existing.backdropURLString != summary.backdropURL?.absoluteString
                    || existing.plot != summary.plot
                    || existing.genre != summary.genre
                    || existing.rating != summary.rating
                    || existing.categoryID != summary.categoryID
                else { continue }

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
                byKey[key] = series
            }
            didChange = true
        }

        saveIfNeeded(didChange)
    }

    public func persistLiveChannels(_ summaries: [LiveChannelSummary], sourceID: String) {
        var byKey = existingByKey(ofType: LiveChannel.self)
        var didChange = false

        for summary in summaries {
            let key = ContentKey.make(sourceID: sourceID, kind: .live, providerID: summary.id)
            if let existing = byKey[key] {
                guard existing.name != summary.name
                    || existing.logoURLString != summary.logoURL?.absoluteString
                    || existing.categoryID != summary.categoryID
                    || existing.number != summary.number
                    || existing.epgChannelID != summary.epgChannelID
                else { continue }

                existing.name = summary.name
                existing.logoURLString = summary.logoURL?.absoluteString
                existing.categoryID = summary.categoryID
                existing.number = summary.number
                existing.epgChannelID = summary.epgChannelID
                existing.lastSyncedAt = .now
            } else {
                let channel = LiveChannel(
                    contentKey: key,
                    providerID: summary.id,
                    name: summary.name,
                    logoURLString: summary.logoURL?.absoluteString,
                    categoryID: summary.categoryID,
                    number: summary.number,
                    epgChannelID: summary.epgChannelID
                )
                modelContext.insert(channel)
                byKey[key] = channel
            }
            didChange = true
        }

        saveIfNeeded(didChange)
    }

    // MARK: - Private

    /// One bulk fetch keyed in memory, never a query per item — a per-item
    /// `FetchDescriptor` over a real catalog is what froze the app originally.
    private func existingByKey<T: CatalogRow>(ofType type: T.Type) -> [String: T] {
        let rows = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
        return Dictionary(rows.map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func rows<T: CatalogRow>(ofType type: T.Type, sourceID: String, kind: ContentKind) -> [T] {
        guard let all = try? modelContext.fetch(FetchDescriptor<T>()) else { return [] }
        let prefix = "\(sourceID)|\(kind.rawValue)|"
        return all.filter { $0.contentKey.hasPrefix(prefix) }
    }

    private func saveIfNeeded(_ didChange: Bool) {
        guard didChange else { return }
        try? modelContext.save()
    }
}

/// Lets the bulk fetch/diff above be written once instead of once per model type.
public protocol CatalogRow: PersistentModel {
    var contentKey: String { get }
}

extension Movie: CatalogRow {}
extension TVSeries: CatalogRow {}
extension LiveChannel: CatalogRow {}
