import SwiftUI

/// A row on a catalog landing screen (Movies, Series). The first three are computed
/// views over the same catalog rather than provider categories — the panel knows
/// nothing about favourites or what has been watched.
///
/// `LiveSection` is deliberately separate: live channels carry their own wording and
/// artwork rules, and collapsing the two would make both harder to change.
enum CatalogSection: Hashable, Identifiable {
    /// Carries its own title so "All Movies" and "All Series" read naturally.
    case all(title: String)
    case favorites
    case history
    case category(id: String, name: String)

    var id: String {
        switch self {
        case .all: return "__all"
        case .favorites: return "__favorites"
        case .history: return "__history"
        case .category(let id, _): return id
        }
    }

    var title: String {
        switch self {
        case .all(let title): return title
        case .favorites: return "Favourites"
        case .history: return "History"
        case .category(_, let name): return name
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
        case .history: return "clock.arrow.circlepath"
        case .category: return "folder"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .accentColor
        case .favorites: return .red
        case .history: return .orange
        case .category: return .secondary
        }
    }
}
