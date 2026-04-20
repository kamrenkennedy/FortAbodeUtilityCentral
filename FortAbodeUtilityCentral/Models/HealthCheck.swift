import Foundation

// MARK: - Health Check

/// Operational health signal for a component, sibling to UpdateStatus.
/// UpdateStatus tracks version state; HealthCheck tracks whether the component
/// can actually do its job right now (e.g. "does Claude have Full Disk Access").
struct HealthCheck: Identifiable, Hashable {
    let id: String
    let label: String
    let state: HealthState
    let actionDeepLink: URL?
}

enum HealthState: Hashable {
    case granted
    case missing
    case unknown
}
