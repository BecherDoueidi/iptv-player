import SwiftUI
import SwiftData
import IPTVCore

struct MovieDetailView: View {
    let movie: MovieSummary
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @Query private var downloadRows: [Download]

    @State private var detail: MovieDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var credentials: XtreamCredentials?
    @State private var playbackRequest: PlaybackRequest?
    @State private var resumePositionSeconds: TimeInterval?

    init(movie: MovieSummary, account: ProviderAccount, dependencies: AppDependencies) {
        self.movie = movie
        self.account = account
        self.dependencies = dependencies
        let key = ContentKey.make(sourceID: account.sourceID, kind: .movie, providerID: movie.id)
        _downloadRows = Query(filter: #Predicate<Download> { $0.contentKey == key })
    }

    private var contentKey: String {
        ContentKey.make(sourceID: account.sourceID, kind: .movie, providerID: movie.id)
    }

    private var download: Download? { downloadRows.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AsyncImage(url: detail?.backdropURL ?? movie.posterURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                    } else {
                        Rectangle().fill(.secondary.opacity(0.2)).aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(movie.title)
                    .font(.title2)
                    .bold()

                if let genre = detail?.genre {
                    Text(genre).foregroundStyle(.secondary)
                }
                if let releaseDate = detail?.releaseDate {
                    Text(releaseDate).font(.footnote).foregroundStyle(.secondary)
                }
                if let rating = detail?.rating ?? movie.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }

                Button {
                    play()
                } label: {
                    Label(playButtonTitle, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(credentials == nil && download?.state != .completed)

                Button(action: downloadAction) {
                    Label(downloadButtonTitle, systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(credentials == nil || download?.state == .completed || download?.state == .downloading)

                if download?.state == .downloading {
                    ProgressView(value: downloadProgress)
                }

                LibraryControlsView(contentKey: contentKey, kind: .movie, title: movie.title, posterURL: movie.posterURL)
                if let error = download?.lastError, download?.state == .failed {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if let plot = detail?.plot, !plot.isEmpty {
                    Text(plot)
                }
            }
            .padding()
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerScreen(request: request)
        }
        .task {
            credentials = try? dependencies.credentialStore.loadCredentials()
            loadResumePosition()
            await loadDetail()
        }
    }

    private var playButtonTitle: String {
        guard let resumePositionSeconds else { return "Play" }
        let minutes = Int(resumePositionSeconds) / 60
        let seconds = Int(resumePositionSeconds) % 60
        return String(format: "Resume at %d:%02d", minutes, seconds)
    }

    private var downloadButtonTitle: String {
        switch download?.state {
        case .completed: return "Downloaded"
        case .downloading: return "Downloading \(Int(downloadProgress * 100))%"
        case .queued: return "Queued"
        case .paused: return "Paused — Resume"
        case .failed: return "Retry Download"
        case .cancelled, .none: return "Download"
        }
    }

    private var downloadProgress: Double {
        guard let download, download.bytesExpected > 0 else { return 0 }
        return Double(download.bytesReceived) / Double(download.bytesExpected)
    }

    private func loadResumePosition() {
        let key = contentKey
        let descriptor = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.contentKey == key })
        if let progress = try? modelContext.fetch(descriptor).first, !progress.isCompleted, progress.positionSeconds > 5 {
            resumePositionSeconds = progress.positionSeconds
        }
    }

    private func loadDetail() async {
        guard let credentials else {
            errorMessage = "Missing saved credentials."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await dependencies.mediaProvider.fetchMovieDetail(credentials: credentials, movieID: movie.id)
        } catch {
            errorMessage = "Couldn't load details."
        }
    }

    private func play() {
        Haptics.light()
        // Prefer the downloaded copy when available — faster, and works offline.
        if let download, download.state == .completed, let localURL = download.localFileURL {
            playbackRequest = PlaybackRequest(url: localURL, title: movie.title, contentKey: contentKey)
            return
        }
        guard let credentials,
              let url = dependencies.mediaProvider.movieStreamURL(
                credentials: credentials,
                movieID: movie.id,
                containerExtension: movie.containerExtension
              )
        else { return }
        playbackRequest = PlaybackRequest(url: url, title: movie.title, contentKey: contentKey)
    }

    private func downloadAction() {
        guard let credentials else { return }
        if let download, download.state == .failed || download.state == .paused {
            dependencies.downloadManager.resume(contentKey: download.contentKey)
            return
        }
        guard let url = dependencies.mediaProvider.movieStreamURL(
            credentials: credentials,
            movieID: movie.id,
            containerExtension: movie.containerExtension
        ) else { return }
        do {
            try dependencies.downloadManager.enqueue(contentKey: contentKey, kind: .movie, title: movie.title, sourceURL: url)
            Haptics.success()
        } catch DownloadError.insufficientDiskSpace {
            errorMessage = "Not enough free storage to start this download."
        } catch {
            errorMessage = "Couldn't start the download."
        }
    }
}
