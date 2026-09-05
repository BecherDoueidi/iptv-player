import SwiftUI
import SwiftData
import IPTVCore

struct MoviesListView: View {
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MoviesViewModel

    init(account: ProviderAccount, dependencies: AppDependencies) {
        self.account = account
        self.dependencies = dependencies
        _viewModel = State(initialValue: MoviesViewModel(dependencies: dependencies, account: account))
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.movies.isEmpty {
                    ProgressView("Loading movies…")
                } else if let errorMessage = viewModel.errorMessage, viewModel.movies.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load movies",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if viewModel.filteredMovies.isEmpty {
                    ContentUnavailableView("No movies found", systemImage: "film")
                } else {
                    ScrollView {
                        continueWatchingSection
                        categoryPicker
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.filteredMovies) { movie in
                                NavigationLink(value: movie) {
                                    MoviePosterCell(movie: movie)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Movies")
            .searchable(text: $viewModel.searchText)
            .navigationDestination(for: MovieSummary.self) { movie in
                MovieDetailView(movie: movie, account: account, dependencies: dependencies)
            }
            .task {
                await viewModel.loadIfNeeded(modelContext: modelContext)
            }
            .onAppear {
                viewModel.loadContinueWatching(modelContext: modelContext)
            }
            .refreshable {
                await viewModel.refresh(modelContext: modelContext)
                viewModel.loadContinueWatching(modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        if !viewModel.continueWatching.isEmpty {
            VStack(alignment: .leading) {
                Text("Continue Watching")
                    .font(.headline)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.continueWatching) { movie in
                            NavigationLink(value: movie) {
                                MoviePosterCell(movie: movie)
                                    .frame(width: 110)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 8)
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
    }

}

private struct MoviePosterCell: View {
    let movie: MovieSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                default:
                    Rectangle()
                        .fill(.secondary.opacity(0.2))
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(movie.title)
                .font(.caption)
                .lineLimit(2)
        }
    }
}
