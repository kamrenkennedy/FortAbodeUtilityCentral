import Foundation

// MARK: - Changelog Entry

struct ChangelogEntry: Identifiable, Codable, Sendable {
    var id: String { version }
    let version: String
    let date: Date?
    let body: String
    let htmlUrl: String?
}
