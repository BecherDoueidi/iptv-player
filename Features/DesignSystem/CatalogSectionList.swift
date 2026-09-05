import SwiftUI

/// The landing list of sections, identical for Movies and Series. Counts are passed in
/// rather than computed here so each view model decides how to derive them.
struct CatalogSectionList<Section: Identifiable & Hashable>: View {
    let sections: [Section]
    let title: (Section) -> String
    let systemImage: (Section) -> String
    let tint: (Section) -> Color
    let count: (Section) -> Int

    var body: some View {
        List(sections) { section in
            NavigationLink(value: section) {
                Label {
                    HStack {
                        Text(title(section)).lineLimit(1)
                        Spacer()
                        Text("\(count(section))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: systemImage(section)).foregroundStyle(tint(section))
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// Shared poster grid used by every catalog section screen and by search results.
struct PosterGrid<Item: Identifiable & Hashable, Cell: View>: View {
    let items: [Item]
    let emptyMessage: String
    var emptySystemImage: String = "film"
    @ViewBuilder let cell: (Item) -> Cell

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("Nothing here", systemImage: emptySystemImage, description: Text(emptyMessage))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            cell(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}

/// One poster tile. Shared so a movie and a series cell can't drift apart visually.
struct PosterCell: View {
    let title: String
    let posterURL: URL?
    var placeholderSystemImage: String = "film"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(2 / 3, contentMode: .fill)
                default:
                    Rectangle()
                        .fill(.secondary.opacity(0.2))
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .overlay(Image(systemName: placeholderSystemImage).foregroundStyle(.secondary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.caption)
                .lineLimit(2)
        }
    }
}
