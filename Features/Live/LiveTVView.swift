import SwiftUI
import SwiftData
import IPTVCore

/// Landing screen for Live TV: All / Favourites / Channel History, then the provider's
/// own categories. Typing in the search field replaces the section list with matching
/// channels from *every* section.
struct LiveTVView: View {
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: LiveViewModel

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
                } else if viewModel.isSearching {
                    LiveChannelList(
                        channels: viewModel.searchResults,
                        viewModel: viewModel,
                        emptyMessage: "No channel matches that name."
                    )
                } else {
                    sectionList
                }
            }
            .navigationTitle("Live TV")
            .searchable(text: $viewModel.searchText, prompt: "Search all channels")
            .navigationDestination(for: LiveSection.self) { section in
                LiveChannelList(
                    channels: viewModel.channels(in: section),
                    viewModel: viewModel,
                    emptyMessage: emptyMessage(for: section)
                )
                .navigationTitle(section.title)
                .navigationBarTitleDisplayMode(.inline)
            }
            .task {
                await viewModel.loadIfNeeded(modelContext: modelContext)
            }
            .refreshable {
                await viewModel.refresh(modelContext: modelContext)
                viewModel.loadFavorites(modelContext: modelContext)
                viewModel.loadHistory(modelContext: modelContext)
            }
        }
    }

    private var sectionList: some View {
        List(viewModel.sections) { section in
            NavigationLink(value: section) {
                Label {
                    HStack {
                        Text(section.title).lineLimit(1)
                        Spacer()
                        Text("\(viewModel.channelCount(in: section))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: section.systemImage).foregroundStyle(section.tint)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func emptyMessage(for section: LiveSection) -> String {
        switch section {
        case .favorites: return "Tap the heart next to a channel to add it here."
        case .history: return "Channels you watch will show up here."
        default: return "This category has no channels."
        }
    }
}
