import Foundation

// MARK: - Check Interval

enum CheckInterval: Int, CaseIterable, Identifiable {
    case hourly = 3600
    case everySixHours = 21600
    case daily = 86400

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hourly: return "Hourly"
        case .everySixHours: return "Every 6 Hours"
        case .daily: return "Daily"
        }
    }
}

// MARK: - Settings Keys

enum AppSettingsKey {
    static let checkInterval = "checkInterval"
    static let backgroundChecksEnabled = "backgroundChecksEnabled"
    static let launchAtLogin = "launchAtLogin"
    static let lastCheckDate = "lastCheckDate"
}
