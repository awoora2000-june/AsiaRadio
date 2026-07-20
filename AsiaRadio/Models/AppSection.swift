import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case favorites
    case channels
    case region
    case recent
    case popular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .channels: return "Channels"
        case .favorites: return "Favorites"
        case .region: return "Country"
        case .recent: return "Recent"
        case .popular: return "Popular"
        }
    }

    var icon: String {
        switch self {
        case .favorites: return "heart.fill"
        case .channels: return "dot.radiowaves.left.and.right"
        case .region: return "flag.fill"
        case .recent: return "clock.fill"
        case .popular: return "star.fill"
        }
    }
}
