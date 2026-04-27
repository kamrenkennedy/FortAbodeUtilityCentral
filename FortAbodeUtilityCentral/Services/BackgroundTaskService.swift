import Foundation
import ServiceManagement

// MARK: - Background Task Service

final class BackgroundTaskService: @unchecked Sendable {

    static let shared = BackgroundTaskService()

    private let launchAgentLabel = "com.kamstudios.fortabodeutilitycentral.checker"
    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    /// Phase 6: separate LaunchAgent for the embedded Weekly Rhythm Engine
    /// runner. Distinct from the component-checker so the user can schedule
    /// engine runs independently of update polling.
    private let engineLaunchAgentLabel = "com.kamstudios.fortabodeutilitycentral.weekly-rhythm-engine"
    private var engineLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(engineLaunchAgentLabel).plist")
    }

    /// Check if the app was launched with --background-check flag
    static var isBackgroundCheck: Bool {
        CommandLine.arguments.contains("--background-check")
    }

    /// Phase 6: launched by the engine LaunchAgent for a scheduled run. Entry
    /// point spawns the runner headlessly and exits, so the WindowGroup body
    /// never instantiates.
    static var isRunEngine: Bool {
        CommandLine.arguments.contains("--run-engine")
    }

    // MARK: - LaunchAgent Management

    /// Install the LaunchAgent plist with the given interval
    func installLaunchAgent(interval: Int) {
        guard let appPath = Bundle.main.bundlePath as String? else { return }

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [
                "\(appPath)/Contents/MacOS/Fort Abode Utility Central",
                "--background-check"
            ],
            "StartInterval": interval,
            "RunAtLoad": false
        ]

        let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        guard let data else { return }

        do {
            try data.write(to: launchAgentURL)
            loadLaunchAgent()
        } catch {
            print("[BackgroundTaskService] Failed to write LaunchAgent: \(error)")
        }
    }

    /// Remove the LaunchAgent
    func removeLaunchAgent() {
        unloadLaunchAgent()
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    /// Update the check interval
    func updateInterval(_ interval: Int) {
        unloadLaunchAgent()
        installLaunchAgent(interval: interval)
    }

    // MARK: - Weekly Rhythm Engine LaunchAgent (Phase 6)

    /// Install the engine LaunchAgent for a weekly run. `weekday` follows the
    /// macOS `Calendar.weekday` convention (1=Sunday … 7=Saturday). `hour` is
    /// 0-23.
    func installEngineLaunchAgent(weekday: Int, hour: Int) {
        guard let appPath = Bundle.main.bundlePath as String? else { return }

        let plist: [String: Any] = [
            "Label": engineLaunchAgentLabel,
            "ProgramArguments": [
                "\(appPath)/Contents/MacOS/Fort Abode Utility Central",
                "--run-engine"
            ],
            "StartCalendarInterval": [
                "Weekday": weekday,
                "Hour": hour,
                "Minute": 0
            ],
            "RunAtLoad": false
        ]

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ) else { return }

        unloadEngineLaunchAgent()

        do {
            try data.write(to: engineLaunchAgentURL)
            loadEngineLaunchAgent()
        } catch {
            print("[BackgroundTaskService] Failed to write engine LaunchAgent: \(error)")
        }
    }

    /// Remove the engine LaunchAgent — both the loaded process and the plist file.
    func removeEngineLaunchAgent() {
        unloadEngineLaunchAgent()
        try? FileManager.default.removeItem(at: engineLaunchAgentURL)
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[BackgroundTaskService] Launch at login error: \(error)")
        }
    }

    // MARK: - Private

    private func loadLaunchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", launchAgentURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func unloadLaunchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func loadEngineLaunchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", engineLaunchAgentURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func unloadEngineLaunchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", engineLaunchAgentURL.path]
        try? process.run()
        process.waitUntilExit()
    }
}
