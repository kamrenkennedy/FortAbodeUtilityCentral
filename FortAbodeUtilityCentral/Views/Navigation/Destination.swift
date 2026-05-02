import Foundation

// Top-level sidebar tabs for the v4.0.0 shell. Order is the order they appear
// in the sidebar from top to bottom.

enum Destination: String, CaseIterable, Identifiable {
    case home
    case family
    case weeklyRhythm
    case marketplace
    case settings

    var id: Self { self }

    var label: String {
        switch self {
        case .home:         return "Home"
        case .family:       return "Family"
        case .weeklyRhythm: return "Weekly Rhythm"
        case .marketplace:  return "Marketplace"
        case .settings:     return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home:         return "house"
        case .family:       return "person.2"
        case .weeklyRhythm: return "calendar"
        case .marketplace:  return "square.grid.2x2"
        case .settings:     return "gearshape"
        }
    }
}
