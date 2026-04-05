import Foundation

actor FilePinningService {

    private let claudeMemoryPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Claude Memory"
    }()

    /// Pin the Claude Memory iCloud folder (and key subfolders) so they're downloaded locally.
    /// Returns true if at least the main folder was pinned successfully.
    @discardableResult
    func pinClaudeMemoryFolder() async -> Bool {
        let fm = FileManager.default

        guard fm.fileExists(atPath: claudeMemoryPath) else {
            return false
        }

        let success = await pin(path: claudeMemoryPath)

        // Also pin known subfolders if they exist — best-effort
        let subfolders = [
            "Kennedy Family Docs/Claude",
            "Weekly Flow"
        ]
        for subfolder in subfolders {
            let fullPath = (claudeMemoryPath as NSString).appendingPathComponent(subfolder)
            if fm.fileExists(atPath: fullPath) {
                await pin(path: fullPath)
            }
        }

        return success
    }

    @discardableResult
    private func pin(path: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        process.arguments = ["download", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            await ErrorLogger.shared.log(
                componentId: "icloud-pinning",
                displayName: "iCloud Folder Pinning",
                error: "brctl download failed for \(path): \(error.localizedDescription)",
                installedVersion: nil
            )
            return false
        }
    }
}
