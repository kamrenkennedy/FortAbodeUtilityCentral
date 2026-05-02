import Foundation

// MARK: - Weekly Rhythm Skill Installer (Phase 6.1)
//
// Detects whether the `weekly-rhythm-engine` plugin is installed in the
// user's `claude` CLI, and runs the three-step install flow if not. The
// bundled marketplace at `Resources/weekly-rhythm-plugin-bundle/` ships with
// the app — at install time we copy it to a stable on-disk location, register
// it via `claude plugin marketplace add`, and install the plugin.
//
// Idempotent: the CLI's marketplace-add and plugin-install commands both
// return 0 when the marketplace/plugin already exists, so re-running the
// install flow is safe.

public actor WeeklyRhythmSkillInstaller {

    public enum InstallOutcome: Sendable, Equatable {
        case alreadyInstalled
        case installed
        case failed(step: String, output: String)
    }

    /// Skill / plugin name that we're installing. Must match the entry in
    /// `Resources/weekly-rhythm-plugin-bundle/.claude-plugin/marketplace.json`.
    public static let pluginName = "weekly-rhythm-engine"
    public static let marketplaceName = "fort-abode-marketplace"

    public init() {}

    // MARK: - Detection

    /// Check if `weekly-rhythm-engine` is installed via `claude plugin list`.
    /// Returns false on any CLI failure — we'd rather try (and re-install
    /// idempotently) than skip a needed install.
    public func detectInstalled(cliPath: String) async -> Bool {
        let outcome = await runProcess(cliPath: cliPath, arguments: ["plugin", "list"])
        guard outcome.exitCode == 0 else { return false }
        // `claude plugin list` either prints "No plugins installed." or a list
        // that includes the plugin name. Substring match is good enough — the
        // names are kebab-case + uniquely scoped.
        let combined = outcome.stdout + "\n" + outcome.stderr
        return combined.contains(Self.pluginName)
    }

    // MARK: - Install

    /// Three-step install: copy bundled marketplace → register → install.
    /// Each step's stdout/stderr is logged via `ErrorLogger` for diagnostics.
    public func install(cliPath: String) async -> InstallOutcome {
        // STEP 1 — copy bundled marketplace to a stable location
        let marketplacePath: String
        do {
            marketplacePath = try await copyBundledMarketplace()
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythmEngine.SkillInstall.step1",
                message: "Failed to copy bundled marketplace",
                context: ["error": "\(error)"]
            )
            return .failed(step: "Copy bundled marketplace", output: "\(error)")
        }
        await ErrorLogger.shared.log(
            area: "WeeklyRhythmEngine.SkillInstall.step1",
            message: "Bundled marketplace copied",
            context: ["destination": marketplacePath]
        )

        // STEP 2 — register the marketplace with claude
        let addOutcome = await runProcess(
            cliPath: cliPath,
            arguments: ["plugin", "marketplace", "add", marketplacePath]
        )
        await ErrorLogger.shared.log(
            area: "WeeklyRhythmEngine.SkillInstall.step2",
            message: "claude plugin marketplace add finished",
            context: [
                "exitCode": "\(addOutcome.exitCode)",
                "stdout": String(addOutcome.stdout.suffix(500)),
                "stderr": String(addOutcome.stderr.suffix(500))
            ]
        )
        if addOutcome.exitCode != 0 {
            return .failed(
                step: "Register marketplace",
                output: addOutcome.combined
            )
        }

        // STEP 3 — install the plugin from the registered marketplace.
        let installOutcome = await runProcess(
            cliPath: cliPath,
            arguments: [
                "plugin", "install",
                "\(Self.pluginName)@\(Self.marketplaceName)",
                "--scope", "user"
            ]
        )
        await ErrorLogger.shared.log(
            area: "WeeklyRhythmEngine.SkillInstall.step3",
            message: "claude plugin install finished",
            context: [
                "exitCode": "\(installOutcome.exitCode)",
                "stdout": String(installOutcome.stdout.suffix(500)),
                "stderr": String(installOutcome.stderr.suffix(500))
            ]
        )
        if installOutcome.exitCode != 0 {
            return .failed(
                step: "Install plugin",
                output: installOutcome.combined
            )
        }

        return .installed
    }

    // MARK: - Marketplace copy

    /// Copy the bundled `weekly-rhythm-plugin-bundle` from the app bundle to
    /// `~/Library/Application Support/Fort Abode Utility Central/marketplace/`.
    /// Overwrites existing contents so a Fort Abode update with a refreshed
    /// marketplace propagates without manual intervention.
    private func copyBundledMarketplace() async throws -> String {
        guard let bundledURL = Bundle.main.url(forResource: "weekly-rhythm-plugin-bundle", withExtension: nil) else {
            throw NSError(
                domain: "WeeklyRhythmSkillInstaller",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled marketplace not found in app bundle. Reinstall Fort Abode."]
            )
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let marketplaceRoot = appSupport
            .appendingPathComponent("Fort Abode Utility Central", isDirectory: true)
            .appendingPathComponent("marketplace", isDirectory: true)

        // Ensure parent exists, then replace the marketplace dir wholesale.
        try FileManager.default.createDirectory(
            at: marketplaceRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: marketplaceRoot.path) {
            try FileManager.default.removeItem(at: marketplaceRoot)
        }
        try FileManager.default.copyItem(at: bundledURL, to: marketplaceRoot)

        return marketplaceRoot.path
    }

    // MARK: - Process helper

    private struct ProcessOutcome: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var combined: String {
            let sections = [stdout, stderr].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return sections.joined(separator: "\n")
        }
    }

    /// Run a synchronous CLI command and capture stdout/stderr. Used for the
    /// short-lived plugin-management commands; the engine itself runs through
    /// `WeeklyRhythmEngineRunner` for streaming output.
    private func runProcess(cliPath: String, arguments: [String]) async -> ProcessOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<ProcessOutcome, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = arguments

                var environment = ProcessInfo.processInfo.environment
                if let existing = environment["PATH"] {
                    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existing)"
                } else {
                    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                }
                process.environment = environment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: ProcessOutcome(
                        exitCode: -1,
                        stdout: "",
                        stderr: "Failed to spawn process: \(error.localizedDescription)"
                    ))
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ProcessOutcome(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                ))
            }
        }
    }
}
