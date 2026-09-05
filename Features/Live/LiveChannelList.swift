import SwiftUI
import SwiftData
import IPTVCore

/// The channel list itself, shared by the section screens and by search results so
/// playback, favoriting and the guide behave identically wherever channels appear.
struct LiveChannelList: View {
    let channels: [LiveChannelSummary]
    let viewModel: LiveViewModel
    var emptyMessage: String = "No channels here."

    @Environment(\.modelContext) private var modelContext
    @State private var playbackRequest: PlaybackRequest?
    @State private var guideChannel: LiveChannelSummary?

    var body: some View {
        Group {
            if channels.isEmpty {
                ContentUnavailableView("No channels", systemImage: "tv", description: Text(emptyMessage))
            } else {
                List(channels) { channel in
                    LiveChannelRow(
                        channel: channel,
                        isFavorite: viewModel.favoriteKeys.contains(viewModel.contentKey(for: channel)),
                        onPlay: { play(channel) },
                        onShowGuide: { guideChannel = channel },
                        onToggleFavorite: { viewModel.toggleFavorite(channel, modelContext: modelContext) }
                    )
                }
                .listStyle(.plain)
            }
        }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerScreen(request: request)
        }
        .sheet(item: $guideChannel) { channel in
            ChannelGuideSheet(channel: channel, viewModel: viewModel)
        }
    }

    private func play(_ channel: LiveChannelSummary) {
        guard let url = viewModel.streamURL(for: channel) else { return }
        Haptics.light()
        viewModel.recordPlayback(of: channel, modelContext: modelContext)
        playbackRequest = PlaybackRequest(
            url: url,
            title: channel.name,
            contentKey: viewModel.contentKey(for: channel),
            isLive: true
        )
    }
}

struct LiveChannelRow: View {
    let channel: LiveChannelSummary
    let isFavorite: Bool
    let onPlay: () -> Void
    let onShowGuide: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    AsyncImage(url: channel.logoURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "tv").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name).font(.body).foregroundStyle(.primary).lineLimit(1)
                        if let number = channel.number {
                            Text("Channel \(number)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: onShowGuide) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? .red : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// What's on now and next. Fetched on demand rather than for every visible row —
/// `get_short_epg` is one request per channel, which a list of thousands can't afford.
struct ChannelGuideSheet: View {
    let channel: LiveChannelSummary
    let viewModel: LiveViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [EPGEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn't load the guide",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "No guide data",
                        systemImage: "calendar",
                        description: Text("This channel has no EPG listings on the provider.")
                    )
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.title).font(.headline)
                                if entry.isOnAir() {
                                    Text("NOW")
                                        .font(.caption2).bold()
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.red, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                            if let timeRange = timeRange(for: entry) {
                                Text(timeRange).font(.caption).foregroundStyle(.secondary)
                            }
                            if let description = entry.description {
                                Text(description).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            defer { isLoading = false }
            do {
                entries = try await viewModel.shortEPG(for: channel)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func timeRange(for entry: EPGEntry) -> String? {
        guard let startsAt = entry.startsAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let endsAt = entry.endsAt else { return formatter.string(from: startsAt) }
        return "\(formatter.string(from: startsAt)) – \(formatter.string(from: endsAt))"
    }
}
