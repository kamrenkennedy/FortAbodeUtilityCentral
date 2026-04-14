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

        case .none:
            return UpdateResult(success: false, output: "", errorOutput: "No update command configured")
        }
    }

    // MARK: - npx Cache Update

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

        // Step 2: Find node/npx
        guard let nodePath = findNodePath() else {
            let errorMsg = "Node.js not found on this machine. Please install Node.js."
            await ErrorLogger.shared.log(
                componentId: "system",
                displayName: "System",
                error: errorMsg,
                installedVersion: nil
            )
            return UpdateResult(success: false, output: "", errorOutput: errorMsg)
        }

        let npxPath = (nodePath as NSString).deletingLastPathComponent + "/npx"

        // Step 3: Pre-fetch the latest version
        let process = Process()
        process.executableURL = URL(fileURLWithPath: npxPath)
        process.arguments = ["-y", "\(packageName)@latest", "--version"]

        // Set up environment with comprehensive PATH
        var env = ProcessInfo.processInfo.environment
        let binDir = (nodePath as NSString).deletingLastPathComponent
        let extraPaths = "/usr/local/bin:/opt/homebrew/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(binDir):\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(binDir):\(extraPaths):/usr/bin:/bin"
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
                errorOutput: "Failed to run npx: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Family Memory Setup

    /// Runs `npx -y setup-claude-memory --family` to deploy the shared family memory
    /// structure. The `--family` flag is the non-interactive entry point added in
    /// setup-claude-memory v1.5.0 — it creates the iCloud folder and appends the
    /// routing block to ~/.claude/CLAUDE.md without prompting.
    func executeFamilyMemorySetup() async -> UpdateResult {
        guard let nodePath = findNodePath() else {
            let errorMsg = "Node.js not found on this machine. Please install Node.js."
            return UpdateResult(success: false, output: "", errorOutput: errorMsg)
        }

        let npxPath = (nodePath as NSString).deletingLastPathComponent + "/npx"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: npxPath)
        process.arguments = ["-y", "setup-claude-memory@latest", "--family"]

        // Same PATH construction as clearAndRefreshNpxCache so npx can find its tooling
        var env = ProcessInfo.processInfo.environment
        let binDir = (nodePath as NSString).deletingLastPathComponent
        let extraPaths = "/usr/local/bin:/opt/homebrew/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(binDir):\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(binDir):\(extraPaths):/usr/bin:/bin"
        }
        // Force non-interactive mode in case any CLI tool reads this
        env["CI"] = "1"
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

            return UpdateResult(
                success: process.terminationStatus == 0,
                output: String(data: outData, encoding: .utf8) ?? "",
                errorOutput: String(data: errData, encoding: .utf8) ?? ""
            )
        } catch {
            return UpdateResult(
                success: false,
                output: "",
                errorOutput: "Failed to run setup-claude-memory --family: \(error.localizedDescription)"
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

    // MARK: - Node.js Discovery

    /// Find node binary using login shell (handles nvm, fnm, Homebrew on both Intel and Apple Silicon)
    private func findNodePath() -> String? {
        // Method 1: Use login shell to find node (handles nvm, fnm, custom PATHs)
        if let path = runWhichNode() {
            return path
        }

        // Method 2: Check common static locations
        let candidates = [
            "/opt/homebrew/bin/node",       // Apple Silicon Homebrew
            "/usr/local/bin/node",          // Intel Homebrew / manual install
            "/usr/bin/node"                 // System
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Method 3: Check nvm default location
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmDir = "\(homeDir)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            // Use the most recent version
            let sorted = versions.sorted().reversed()
            for version in sorted {
                let nodePath = "\(nvmDir)/\(version)/bin/node"
                if FileManager.default.fileExists(atPath: nodePath) {
                    return nodePath
                }
            }
        }

        print("[UpdateExecution] Node.js not found anywhere")
        return nil
    }

    /// Run `which node` in a login shell to get the full PATH (including nvm/fnm)
    private func runWhichNode() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which node"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let path, !path.isEmpty,
                  FileManager.default.fileExists(atPath: path) else { return nil }

            return path
        } catch {
            return nil
        }
    }
}
