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

    // Weekly Rhythm Engine (Phase 6 — embedded `claude` CLI runner)
    static let weeklyRhythmEngineScheduleEnabled    = "WeeklyRhythmEngine.scheduleEnabled"
    static let weeklyRhythmEngineScheduleHour       = "WeeklyRhythmEngine.scheduleHour"
    static let weeklyRhythmEngineScheduleWeekday    = "WeeklyRhythmEngine.scheduleWeekday"
    static let weeklyRhythmEngineSurfaceOnCompletion = "WeeklyRhythmEngine.surfaceOnCompletion"
    static let weeklyRhythmEngineCLIPathOverride    = "WeeklyRhythmEngine.cliPathOverride"
    static let weeklyRhythmEngineLastRunAt          = "WeeklyRhythmEngine.lastRunAt"
    static let weeklyRhythmEngineLastRunSucceeded   = "WeeklyRhythmEngine.lastRunSucceeded"
    static let weeklyRhythmEngineLastRunSummary     = "WeeklyRhythmEngine.lastRunSummary"
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the user taps a `weekly-rhythm-run-*` system notification so
    /// the app layer can deep-link the foregrounded window to the Weekly Rhythm
    /// tab. Bridges `NotificationService` (singleton, no AppState access) and
    /// `AppState.selectedDestination` without coupling them directly.
    static let engineRunNotificationTapped = Notification.Name("FortAbode.engineRunNotificationTapped")
}
