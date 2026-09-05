import SwiftUI
import IPTVCore

struct MovieDetailView: View {
    let movie: MovieSummary
    let dependencies: AppDependencies

    @State private var detail: MovieDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var credentials: XtreamCredentials?
    @State private var playbackRequest: PlaybackRequest?

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
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(credentials == nil)

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
            await loadDetail()
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
        guard let credentials,
              let url = dependencies.mediaProvider.movieStreamURL(
                credentials: credentials,
                movieID: movie.id,
                containerExtension: movie.containerExtension
              )
        else { return }
        playbackRequest = PlaybackRequest(url: url, title: movie.title)
    }
}
