import Foundation

// MARK: - App Navigation
//
// In-tab push routes. Top-level sidebar navigation lives in
// `Views/Navigation/Destination.swift` and is driven by AppState.
//
// As of v4.0.0, the only push route in the new shell is component
// detail (from MarketplaceView's bento card → ComponentDetailView).
// FamilyMemoryView and FeedbackView are no longer pushed — Family
// content lives in the Family tab and feedback opens as a sheet.

enum AppDestination: Hashable {
    case componentDetail(componentId: String)
}
