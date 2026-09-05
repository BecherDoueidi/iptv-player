import SwiftUI
import SwiftData
import IPTVCore

/// Landing screen for Series: All / Favourites / History, then the provider's own
/// categories. Typing in the search field replaces the section list with matches from
/// the whole catalog.
struct SeriesListView: View {
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SeriesViewModel

    init(account: ProviderAccount, dependencies: AppDependencies) {
        self.account = account
        self.dependencies = dependencies
        _viewModel = State(initialValue: SeriesViewModel(dependencies: dependencies, account: account))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.seriesList.isEmpty {
                    ProgressView("Loading series…")
                } else if let errorMessage = viewModel.errorMessage, viewModel.seriesList.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load series",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if viewModel.isSearching {
                    grid(for: viewModel.searchResults, emptyMessage: "No series matches that name.")
                } else {
                    CatalogSectionList(
                        sections: viewModel.sections,
                        title: \.title,
                        systemImage: \.systemImage,
                        tint: \.tint,
                        count: { viewModel.seriesCount(in: $0) }
                    )
                }
            }
            .navigationTitle("Series")
            .searchable(text: $viewModel.searchText, prompt: "Search all series")
            .navigationDestination(for: CatalogSection.self) { section in
                grid(for: viewModel.series(in: section), emptyMessage: emptyMessage(for: section))
                    .navigationTitle(section.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: SeriesSummary.self) { series in
                SeriesDetailView(series: series, account: account, dependencies: dependencies)
            }
            .task {
                await viewModel.loadIfNeeded(modelContext: modelContext)
            }
            .onAppear {
                // Favourites and history change from the detail screen, so they're
                // re-read on the way back rather than only at first load.
                viewModel.loadFavorites(modelContext: modelContext)
                viewModel.loadHistory(modelContext: modelContext)
            }
            .refreshable {
                await viewModel.refresh(modelContext: modelContext)
                viewModel.loadFavorites(modelContext: modelContext)
                viewModel.loadHistory(modelContext: modelContext)
            }
        }
    }

    private func grid(for series: [SeriesSummary], emptyMessage: String) -> some View {
        PosterGrid(items: series, emptyMessage: emptyMessage, emptySystemImage: "tv") { item in
            PosterCell(title: item.title, posterURL: item.posterURL, placeholderSystemImage: "tv")
        }
    }

    private func emptyMessage(for section: CatalogSection) -> String {
        switch section {
        case .favorites: return "Favourite a series to see it here."
        case .history: return "Series you play will show up here."
        default: return "This category has no series."
        }
    }
}
