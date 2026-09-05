import SwiftUI
import SwiftData
import IPTVCore

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

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

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
                } else if viewModel.filteredSeries.isEmpty {
                    ContentUnavailableView("No series found", systemImage: "tv")
                } else {
                    ScrollView {
                        categoryPicker
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.filteredSeries) { series in
                                NavigationLink(value: series) {
                                    SeriesPosterCell(series: series)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Series")
            .searchable(text: $viewModel.searchText)
            .navigationDestination(for: SeriesSummary.self) { series in
                SeriesDetailView(series: series, account: account, dependencies: dependencies)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive, action: signOut)
                }
            }
            .task {
                await viewModel.loadIfNeeded(modelContext: modelContext)
            }
            .refreshable {
                await viewModel.refresh(modelContext: modelContext)
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

    private func signOut() {
        try? dependencies.credentialStore.clear()
        modelContext.delete(account)
        try? modelContext.save()
    }
}

private struct SeriesPosterCell: View {
    let series: SeriesSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: series.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                default:
                    Rectangle()
                        .fill(.secondary.opacity(0.2))
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .overlay(Image(systemName: "tv").foregroundStyle(.secondary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(series.title)
                .font(.caption)
                .lineLimit(2)
        }
    }
}
