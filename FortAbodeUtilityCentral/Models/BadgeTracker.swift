import Foundation

// MARK: - Badge Tracker

/// Tracks which components have a pending "Updated" badge.
/// Badge persists until the user views the component's detail page.
@Observable
final class BadgeTracker {

    private static let storageKey = "updatedBadges"

    /// Component ID → version that triggered the badge
    private(set) var pendingBadges: [String: String]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            pendingBadges = decoded
        } else {
            pendingBadges = [:]
        }
    }

    /// Mark a component as recently updated — shows badge on tile
    func markUpdated(componentId: String, version: String) {
        pendingBadges[componentId] = version
        save()
    }

    /// Clear the badge — called when user views the detail page
    func clearBadge(componentId: String) {
        pendingBadges.removeValue(forKey: componentId)
        save()
    }

    /// Check if a component has a pending badge
    func hasBadge(_ componentId: String) -> Bool {
        pendingBadges[componentId] != nil
    }

    /// The version that triggered the badge
    func badgeVersion(_ componentId: String) -> String? {
        pendingBadges[componentId]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pendingBadges) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
