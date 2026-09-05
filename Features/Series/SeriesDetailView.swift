import SwiftUI
import SwiftData
import IPTVCore

struct SeriesDetailView: View {
    let series: SeriesSummary
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SeriesDetailViewModel
    @State private var credentials: XtreamCredentials?
    @State private var playbackRequest: PlaybackRequest?

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

                Divider()

                if viewModel.isLoading {
                    ProgressView()
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if viewModel.seasons.isEmpty {
                    Text("No episodes available yet.").foregroundStyle(.secondary)
                } else {
                    seasonPicker
                    episodeList
                }
            }
            .padding()
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerScreen(request: request)
        }
        .task {
            credentials = try? dependencies.credentialStore.loadCredentials()
            await viewModel.loadIfNeeded(modelContext: modelContext)
        }
    }

    private func play(_ episode: SeriesEpisode) {
        guard let credentials,
              let url = dependencies.mediaProvider.episodeStreamURL(
                credentials: credentials,
                episodeID: episode.id,
                containerExtension: episode.containerExtension
              )
        else { return }
        playbackRequest = PlaybackRequest(url: url, title: episode.title)
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
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(episodes) { episode in
                Button {
                    play(episode)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Episode \(episode.episodeNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(episode.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(credentials == nil)
                .padding(.vertical, 4)
                Divider()
            }
        }
    }
}
