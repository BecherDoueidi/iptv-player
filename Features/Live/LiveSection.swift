import SwiftUI
import IPTVCore

/// A row on the Live TV landing screen. The first three are computed views over the
/// same channel list rather than provider categories — the panel knows nothing about
/// favorites or what you've watched.
enum LiveSection: Hashable, Identifiable {
    case all
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
        case .all: return "All Channels"
        case .favorites: return "Favourites"
        case .history: return "Channel History"
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
