import Foundation

// MARK: - Settings ViewModel

@MainActor
@Observable
final class SettingsViewModel {

    var checkInterval: CheckInterval {
        didSet {
            UserDefaults.standard.set(checkInterval.rawValue, forKey: AppSettingsKey.checkInterval)
            if backgroundChecksEnabled {
                BackgroundTaskService.shared.updateInterval(checkInterval.rawValue)
            }
        }
    }

    var backgroundChecksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundChecksEnabled, forKey: AppSettingsKey.backgroundChecksEnabled)
            if backgroundChecksEnabled {
                BackgroundTaskService.shared.installLaunchAgent(interval: checkInterval.rawValue)
            } else {
                BackgroundTaskService.shared.removeLaunchAgent()
            }
        }
    }

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: AppSettingsKey.launchAtLogin)
            BackgroundTaskService.shared.setLaunchAtLogin(launchAtLogin)
        }
    }

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: AppSettingsKey.checkInterval)
        self.checkInterval = CheckInterval(rawValue: savedInterval) ?? .daily
        self.backgroundChecksEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.backgroundChecksEnabled)
        self.launchAtLogin = UserDefaults.standard.bool(forKey: AppSettingsKey.launchAtLogin)
    }
}
