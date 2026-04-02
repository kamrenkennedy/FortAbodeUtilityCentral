import Foundation
import AppKit

// MARK: - Update Execution Service

actor UpdateExecutionService {

    /// Execute an update for a component. Returns true if the update was started successfully.
    func executeUpdate(for component: Component) async -> Bool {
        switch component.updateCommand {
        case .npxInstall(let packageName):
            return await openInTerminal(command: "npx \(packageName)")

        case .shellCommand(let command, let args):
            return await runShellCommand(command, args: args)

        case .parentPackage:
            // Should be handled by the ViewModel routing to the parent
            return false

        case .none:
            return false
        }
    }

    // MARK: - Terminal Handoff (MVP)

    /// Opens Terminal.app and runs the given command. Returns true if Terminal opened.
    @MainActor
    private func openInTerminal(command: String) async -> Bool {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return false }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            print("[UpdateExecution] AppleScript error: \(error)")
            return false
        }

        return true
    }

    // MARK: - Shell Command (for git pull etc.)

    private func runShellCommand(_ command: String, args: [String]) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("[UpdateExecution] Failed to run \(command): \(error)")
            return false
        }
    }
}
