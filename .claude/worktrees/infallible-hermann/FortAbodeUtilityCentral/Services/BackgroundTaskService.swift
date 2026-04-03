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

    /// Check if the app was launched with --background-check flag
    static var isBackgroundCheck: Bool {
        CommandLine.arguments.contains("--background-check")
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
}
