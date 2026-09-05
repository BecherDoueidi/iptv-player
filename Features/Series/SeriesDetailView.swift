import SwiftUI
import SwiftData
import IPTVCore

struct SeriesDetailView: View {
    let series: SeriesSummary
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @Query private var allDownloads: [Download]
    @State private var viewModel: SeriesDetailViewModel
    @State private var credentials: XtreamCredentials?
    @State private var playbackRequest: PlaybackRequest?
    @State private var currentlyPlayingEpisode: SeriesEpisode?

    init(series: SeriesSummary, account: ProviderAccount, dependencies: AppDependencies) {
        self.series = series
        self.account = account
        self.dependencies = dependencies
        _viewModel = State(initialValue: SeriesDetailViewModel(series: series, account: account, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AsyncImage(url: series.backdropURL ?? series.posterURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                    } else {
                        Rectangle().fill(.secondary.opacity(0.2)).aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(series.title).font(.title2).bold()

                if let genre = series.genre {
                    Text(genre).foregroundStyle(.secondary)
                }
                if let rating = series.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                if let plot = series.plot, !plot.isEmpty {
                    Text(plot)
                }

                LibraryControlsView(
                    contentKey: ContentKey.make(sourceID: account.sourceID, kind: .series, providerID: series.id),
                    kind: .series,
                    title: series.title,
                    posterURL: series.posterURL
                )

                Divider()

                if viewModel.isLoading && viewModel.seasons.isEmpty {
                    ProgressView()
                } else if viewModel.seasons.isEmpty {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("No episodes available yet.").foregroundStyle(.secondary)
                    }
                } else {
                    // Cached episodes still show even if the network refresh above
                    // failed (offline, or the panel is temporarily unreachable).
                    seasonPicker
                    episodeList
                }
            }
            .padding()
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerScreen(request: request, onRequestNextEpisode: playNextEpisodeIfAvailable)
        }
        .task {
            credentials = try? dependencies.credentialStore.loadCredentials()
            await viewModel.loadIfNeeded(modelContext: modelContext)
        }
    }

    private func contentKey(for episode: SeriesEpisode) -> String {
        ContentKey.make(sourceID: account.sourceID, kind: .episode, providerID: episode.id)
    }

    private func play(_ episode: SeriesEpisode) {
        if currentlyPlayingEpisode?.id != episode.id {
            Haptics.light()
        }
        currentlyPlayingEpisode = episode
        let key = contentKey(for: episode)
        // Recorded against the series, not the episode — see PlaybackHistory.
        PlaybackHistory.recordSeries(
            contentKey: ContentKey.make(sourceID: account.sourceID, kind: .series, providerID: series.id),
            in: modelContext
        )

        // Prefer the downloaded copy when available — faster, and works offline.
        if let existing = downloadIndex()[contentKey(for: episode)],
           existing.state == .completed, let localURL = existing.localFileURL {
            playbackRequest = PlaybackRequest(url: localURL, title: episode.title, contentKey: key)
            return
        }

        guard let credentials,
              let url = dependencies.mediaProvider.episodeStreamURL(
                credentials: credentials,
                episodeID: episode.id,
                containerExtension: episode.containerExtension
              )
        else { return }
        playbackRequest = PlaybackRequest(url: url, title: episode.title, contentKey: key)
    }

    /// Next episode in the same season, or the first episode of the next season.
    private func nextEpisode(after episode: SeriesEpisode) -> SeriesEpisode? {
        guard let season = viewModel.seasons.first(where: { $0.seasonNumber == episode.seasonNumber }) else {
            return nil
        }
        if let index = season.episodes.firstIndex(where: { $0.id == episode.id }), index + 1 < season.episodes.count {
            return season.episodes[index + 1]
        }
        return viewModel.seasons.first { $0.seasonNumber == episode.seasonNumber + 1 }?.episodes.first
    }

    private func playNextEpisodeIfAvailable() {
        guard let current = currentlyPlayingEpisode, let next = nextEpisode(after: current) else { return }
        play(next)
    }

    private func downloadIndex() -> [String: Download] {
        Dictionary(allDownloads.map { ($0.contentKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func download(for episode: SeriesEpisode, in index: [String: Download]) -> Download? {
        index[contentKey(for: episode)]
    }

    private func downloadIconName(for episode: SeriesEpisode, in index: [String: Download]) -> String {
        switch download(for: episode, in: index)?.state {
        case .completed: return "checkmark.circle.fill"
        case .downloading: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.circle"
        case .queued, .paused: return "clock"
        case .cancelled, .none: return "arrow.down.circle"
        }
    }

    private func downloadAction(for episode: SeriesEpisode) {
        guard let credentials else { return }
        if let existing = downloadIndex()[contentKey(for: episode)],
           existing.state == .failed || existing.state == .paused {
            dependencies.downloadManager.resume(contentKey: existing.contentKey)
            return
        }
        guard let url = dependencies.mediaProvider.episodeStreamURL(
            credentials: credentials,
            episodeID: episode.id,
            containerExtension: episode.containerExtension
        ) else { return }
        if (try? dependencies.downloadManager.enqueue(
            contentKey: contentKey(for: episode),
            kind: .episode,
            title: episode.title,
            sourceURL: url
        )) != nil {
            Haptics.success()
        }
    }

    private var seasonPicker: some View {
        Picker("Season", selection: Binding(
            get: { viewModel.selectedSeasonNumber ?? viewModel.seasons.first?.seasonNumber ?? 0 },
            set: { viewModel.selectedSeasonNumber = $0 }
        )) {
            ForEach(viewModel.seasons) { season in
                Text("Season \(season.seasonNumber)").tag(season.seasonNumber)
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    private var episodeList: some View {
        let episodes = viewModel.seasons.first { $0.seasonNumber == viewModel.selectedSeasonNumber }?.episodes ?? []
        // Indexed once per render — this was a linear scan over all downloads,
        // repeated several times per episode row, on every progress update.
        let index = downloadIndex()
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(episodes) { episode in
                HStack {
                    Button {
                        play(episode)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Episode \(episode.episodeNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(episode.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(credentials == nil && download(for: episode, in: index)?.state != .completed)

                    Spacer()

                    Button {
                        downloadAction(for: episode)
                    } label: {
                        Image(systemName: downloadIconName(for: episode, in: index))
                    }
                    .buttonStyle(.borderless)
                    .disabled(credentials == nil || download(for: episode, in: index)?.state == .completed
                        || download(for: episode, in: index)?.state == .downloading)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }
}
