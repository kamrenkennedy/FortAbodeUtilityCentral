import SwiftUI

// MARK: - Update Status

enum UpdateStatus: Equatable {
    case unknown
    case checking
    case upToDate(version: String)
    case updateAvailable(installed: String, latest: String)
    case notInstalled
    case updating
    case updateComplete(version: String)
    case error(message: String)

    // MARK: - Display Properties

    var indicatorColor: Color {
        switch self {
        case .unknown, .checking:
            return .secondary
        case .upToDate, .updateComplete:
            return .green
        case .updateAvailable:
            return .orange
        case .notInstalled:
            return .secondary
        case .updating:
            return .blue
        case .error:
            return .red
        }
    }

    var sfSymbolName: String {
        switch self {
        case .unknown:
            return "questionmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "arrow.up.circle.fill"
        case .notInstalled:
            return "minus.circle.fill"
        case .updating:
            return "arrow.down.circle.fill"
        case .updateComplete:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var statusText: String {
        switch self {
        case .unknown:
            return "Not checked"
        case .checking:
            return "Checking..."
        case .upToDate(let version):
            return "Up to date (\(version))"
        case .updateAvailable(let installed, let latest):
            return "\(latest) available (you have \(installed))"
        case .notInstalled:
            return "Not installed"
        case .updating:
            return "Updating..."
        case .updateComplete(let version):
            return "Updated to \(version)"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var installedVersion: String? {
        switch self {
        case .upToDate(let version), .updateComplete(let version):
            return version
        case .updateAvailable(let installed, _):
            return installed
        default:
            return nil
        }
    }

    var isUpdateAvailable: Bool {
        if case .updateAvailable = self { return true }
        return false
    }
}

// MARK: - Semver Comparison

struct SemverComparison {

    /// Compare two semver strings. Returns true if `latest` is newer than `installed`.
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        let latestParts = parse(latest)
        let installedParts = parse(installed)

        for i in 0..<max(latestParts.count, installedParts.count) {
            let l = i < latestParts.count ? latestParts[i] : 0
            let r = i < installedParts.count ? installedParts[i] : 0
            if l > r { return true }
            if l < r { return false }
        }
        return false
    }

    /// Parse a version string into integer components, stripping any `v` prefix
    static func parse(_ version: String) -> [Int] {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return cleaned
            .split(separator: ".")
            .compactMap { Int($0) }
    }
}
