import Foundation
import AppKit

// MARK: - Update Result

struct UpdateResult: Sendable {
    let success: Bool
    let output: String
    let errorOutput: String
}

// MARK: - Update Execution Service

actor UpdateExecutionService {

    /// Execute an update for a component. Returns the result with output.
    func executeUpdate(for component: Component) async -> UpdateResult {
        switch component.updateCommand {
        case .npxInstall(let packageName):
            return await clearAndRefreshNpxCache(packageName: packageName)

        case .shellCommand(let command, let args):
            return await runShellCommand(command, args: args)

        case .parentPackage:
            // Should be handled by the ViewModel routing to the parent
            return UpdateResult(success: false, output: "", errorOutput: "Routed to parent")

        case .none:
            return UpdateResult(success: false, output: "", errorOutput: "No update command")
        }
    }

    // MARK: - npx Cache Update

    /// Professional update flow: clear old npx cache, then pre-fetch the latest version.
    /// This is what happens when Claude Desktop restarts — npx downloads the newest version.
    private func clearAndRefreshNpxCache(packageName: String) async -> UpdateResult {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let npxCacheDir = homeDir.appendingPathComponent(".npm/_npx")

        // Step 1: Find and remove old cache entries for this package
        var removedCount = 0
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: npxCacheDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                let packagePath = entry
                    .appendingPathComponent("node_modules")
                    .appendingPathComponent(packageName)
                if FileManager.default.fileExists(atPath: packagePath.path) {
                    do {
                        try FileManager.default.removeItem(at: entry)
                        removedCount += 1
                    } catch {
                        print("[UpdateExecution] Failed to remove cache entry: \(error)")
                    }
                }
            }
        }

        // Step 2: Pre-fetch the latest version by running npx with --yes
        // This downloads the package to the npx cache so it's ready when Claude starts
        let nodePath = findNodePath()
        let npxPath = nodePath.replacingOccurrences(of: "/node", with: "/npx")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: npxPath)
        process.arguments = ["-y", "\(packageName)@latest", "--version"]

        // Set up environment with PATH so node can find its dependencies
        var env = ProcessInfo.processInfo.environment
        let binDir = (nodePath as NSString).deletingLastPathComponent
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(binDir):\(existingPath)"
        } else {
            env["PATH"] = binDir
        }
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8) ?? ""
            let errStr = String(data: errData, encoding: .utf8) ?? ""

            let success = process.terminationStatus == 0
            return UpdateResult(
                success: success,
                output: "Cleared \(removedCount) old cache entries. \(success ? "Downloaded latest version." : "Download may have failed.")\n\(outStr)",
                errorOutput: errStr
            )
        } catch {
            return UpdateResult(
                success: false,
                output: "Cleared \(removedCount) old cache entries.",
                errorOutput: "Failed to pre-fetch: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Shell Command

    private func runShellCommand(_ command: String, args: [String]) async -> UpdateResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()

            return UpdateResult(
                success: process.terminationStatus == 0,
                output: String(data: outData, encoding: .utf8) ?? "",
                errorOutput: String(data: errData, encoding: .utf8) ?? ""
            )
        } catch {
            return UpdateResult(
                success: false,
                output: "",
                errorOutput: "Failed to run \(command): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    /// Find the node binary path — checks common locations
    private func findNodePath() -> String {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/opt/homebrew/bin/node"
    }
}
