import SwiftUI
import SwiftData
import IPTVCore

struct LiveTVView: View {
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: LiveViewModel
    @State private var playbackRequest: PlaybackRequest?
    @State private var guideChannel: LiveChannelSummary?

    init(account: ProviderAccount, dependencies: AppDependencies) {
        self.account = account
        self.dependencies = dependencies
        _viewModel = State(initialValue: LiveViewModel(dependencies: dependencies, account: account))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.channels.isEmpty {
                    ProgressView("Loading channels…")
                } else if let errorMessage = viewModel.errorMessage, viewModel.channels.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load channels",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    channelList
                }
            }
            .navigationTitle("Live TV")
            .searchable(text: $viewModel.searchText)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.favoritesOnly.toggle()
                    } label: {
                        Image(systemName: viewModel.favoritesOnly ? "heart.fill" : "heart")
                    }
                    .tint(viewModel.favoritesOnly ? .red : .accentColor)
                }
            }
            .fullScreenCover(item: $playbackRequest) { request in
                PlayerScreen(request: request)
            }
            .sheet(item: $guideChannel) { channel in
                ChannelGuideSheet(channel: channel, viewModel: viewModel)
            }
            .task {
                await viewModel.loadIfNeeded(modelContext: modelContext)
            }
            .refreshable {
                await viewModel.refresh(modelContext: modelContext)
                viewModel.loadFavorites(modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private var channelList: some View {
        VStack(spacing: 0) {
            categoryPicker
            if viewModel.filteredChannels.isEmpty {
                ContentUnavailableView(
                    viewModel.favoritesOnly ? "No favorite channels" : "No channels found",
                    systemImage: "tv"
                )
            } else {
                List(viewModel.filteredChannels) { channel in
                    ChannelRow(
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
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if !viewModel.categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    categoryChip(title: "All", isSelected: viewModel.selectedCategoryID == nil) {
                        viewModel.selectedCategoryID = nil
                    }
                    ForEach(viewModel.categories) { category in
                        categoryChip(title: category.name, isSelected: viewModel.selectedCategoryID == category.id) {
                            viewModel.selectedCategoryID = category.id
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func play(_ channel: LiveChannelSummary) {
        guard let url = viewModel.streamURL(for: channel) else { return }
        Haptics.light()
        playbackRequest = PlaybackRequest(
            url: url,
            title: channel.name,
            contentKey: viewModel.contentKey(for: channel),
            isLive: true
        )
    }
}

private struct ChannelRow: View {
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
private struct ChannelGuideSheet: View {
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
                    ContentUnavailableView("Couldn't load the guide", systemImage: "calendar.badge.exclamationmark", description: Text(errorMessage))
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
