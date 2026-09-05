import Foundation
import Observation
import SwiftData
import IPTVCore

@Observable
final class SeriesDetailViewModel {
    let series: SeriesSummary
    private(set) var seasons: [SeriesSeason] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedSeasonNumber: Int?

    private let dependencies: AppDependencies
    private let account: ProviderAccount

    init(series: SeriesSummary, account: ProviderAccount, dependencies: AppDependencies) {
        self.series = series
        self.account = account
        self.dependencies = dependencies
    }

    @MainActor
    func loadIfNeeded(modelContext: ModelContext) async {
        guard seasons.isEmpty, !isLoading else { return }
        loadFromCache(modelContext: modelContext)
        await load(modelContext: modelContext)
    }

    /// Populates from the persisted Series → Season → Episode tree first so
    /// previously-viewed episodes are browsable offline (or while the network
    /// refresh below is in flight / fails).
    private func loadFromCache(modelContext: ModelContext) {
        let seriesKey = ContentKey.make(sourceID: account.sourceID, kind: .series, providerID: series.id)
        let descriptor = FetchDescriptor<TVSeries>(predicate: #Predicate { $0.contentKey == seriesKey })
        guard let record = try? modelContext.fetch(descriptor).first, !record.seasons.isEmpty else { return }

        seasons = record.seasons.map { season in
            SeriesSeason(
                seasonNumber: season.seasonNumber,
                episodes: season.episodes.map { episode in
                    SeriesEpisode(
                        id: episode.providerID,
                        seasonNumber: season.seasonNumber,
                        episodeNumber: episode.episodeNumber,
                        title: episode.title,
                        containerExtension: episode.containerExtension
                    )
                }.sorted { $0.episodeNumber < $1.episodeNumber }
            )
        }.sorted { $0.seasonNumber < $1.seasonNumber }

        if selectedSeasonNumber == nil {
            selectedSeasonNumber = seasons.first?.seasonNumber
        }
    }

    @MainActor
    func load(modelContext: ModelContext) async {
        guard let credentials = try? dependencies.credentialStore.loadCredentials() else {
            errorMessage = "Missing saved credentials."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let detail = try await dependencies.mediaProvider.fetchSeriesDetail(
                credentials: credentials,
                seriesID: series.id
            )
            seasons = detail.seasons
            if selectedSeasonNumber == nil {
                selectedSeasonNumber = detail.seasons.first?.seasonNumber
            }
            persist(detail, modelContext: modelContext)
        } catch {
            errorMessage = "Couldn't load episodes."
        }
    }

    private func persist(_ detail: SeriesDetail, modelContext: ModelContext) {
        let seriesKey = ContentKey.make(sourceID: account.sourceID, kind: .series, providerID: series.id)
        let descriptor = FetchDescriptor<TVSeries>(predicate: #Predicate { $0.contentKey == seriesKey })
        guard let seriesRecord = try? modelContext.fetch(descriptor).first else { return }

        // Explicitly delete the old season/episode rows first — reassigning a
        // to-many relationship doesn't itself cascade-delete previously-linked
        // children; the cascade rule only fires when the owning row is deleted.
        for season in seriesRecord.seasons {
            modelContext.delete(season)
        }

        seriesRecord.seasons = detail.seasons.map { season in
            TVSeason(
                seasonNumber: season.seasonNumber,
                episodes: season.episodes.map { episode in
                    TVEpisode(
                        contentKey: ContentKey.make(sourceID: account.sourceID, kind: .episode, providerID: episode.id),
                        providerID: episode.id,
                        episodeNumber: episode.episodeNumber,
                        title: episode.title,
                        containerExtension: episode.containerExtension
                    )
                }
            )
        }
        try? modelContext.save()
    }
}
