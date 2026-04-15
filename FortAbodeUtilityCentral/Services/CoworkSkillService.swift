import Foundation

// MARK: - Plugin Install Result

/// Outcome of the most recent call to `installWeeklyRhythmPlugin()`. Exposed so the
/// manual "Install Plugin in Claude Code" button in ComponentDetailView can surface
/// a user-facing result inline, and so FeedbackService can include the state in
/// bug reports.
enum PluginInstallResult: Sendable, Equatable {
    case notYetAttempted
    case succeeded(at: Date, output: String)
    case failed(at: Date, step: String, error: String, output: String)
    case claudeCLINotFound

    var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    var displayMessage: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        switch self {
        case .notYetAttempted:
            return "Not yet attempted"
        case .succeeded(let at, _):
            return "Plugin installed at \(formatter.string(from: at)) — quit and relaunch Claude Code to activate"
        case .failed(_, let step, let error, _):
            return "Failed at \(step): \(error)"
        case .claudeCLINotFound:
            return "Claude Code CLI not found — is Claude Code installed?"
        }
    }

    /// Raw CLI output (stdout + stderr) for display in a disclosure region. Lets Kam see
    /// exactly what the `claude plugin install` command printed when debugging.
    var rawOutput: String? {
        switch self {
        case .notYetAttempted, .claudeCLINotFound:
            return nil
        case .succeeded(_, let output):
            return output.isEmpty ? nil : output
        case .failed(_, _, _, let output):
            return output.isEmpty ? nil : output
        }
    }
}

// MARK: - Cowork Skill Service (v3.7.6 plugin-system rewrite)

/// Manages the Weekly Rhythm Engine's presence in Claude Code / Cowork.
///
/// **v3.7.6 architectural shift:** previous versions tried to write directly to
/// Cowork's `manifest.json` and `skills/<name>/SKILL.md` files to register the
/// skill. That approach is fundamentally broken — Cowork owns those files and
/// periodically rewrites them from its own internal state, clobbering Fort Abode's
/// writes. On Kam's Mac it APPEARED to work because he had registered the skill
/// via Cowork's own tools at some earlier point, so Cowork preserved it in its
/// internal state. On Tiera's Mac, Cowork had never been told about the skill,
/// and Fort Abode's writes had no lasting effect.
///
/// The correct path is to install the skill as a proper Claude Code plugin via
/// the `claude plugin install` CLI. Fort Abode ships a bundled plugin marketplace
/// inside its app bundle (`Resources/weekly-rhythm-plugin-bundle/`), copies it to
/// a stable user-writable location, registers it with `claude plugin marketplace add`,
/// and then installs the plugin with `claude plugin install`. Cowork picks up
/// the plugin through its own plugin-discovery mechanism — no fighting, no clobbering.
actor CoworkSkillService {

    private let fm = FileManager.default

    /// Most recent outcome — read by the UI and the debug report.
    private(set) var lastInstallResult: PluginInstallResult = .notYetAttempted

    // MARK: - Constants

    private static let marketplaceName = "fort-abode-marketplace"
    private static let pluginName = "weekly-rhythm-engine"
    private static let pluginIdentifier = "weekly-rhythm-engine@fort-abode-marketplace"

    /// Stable user-writable directory where Fort Abode copies the bundled marketplace.
    /// We can't point `claude plugin marketplace add` at the path inside the app bundle
    /// directly because that path changes on every Sparkle update (the .app lives in
    /// a versioned location during the install flow). A stable path under
    /// Application Support survives updates and gives the Claude CLI a fixed target.
    private var stableMarketplacePath: URL {
        let home = fm.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/FortAbodeUtilityCentral")
            .appendingPathComponent("plugins")
            .appendingPathComponent("fort-abode-marketplace")
    }

    // MARK: - Public API

    /// Install the bundled `weekly-rhythm-engine` plugin via `claude plugin install`.
    /// Called both from the launch-time self-heal (once-per-machine via UserDefaults
    /// guard) and from the manual "Install Plugin in Claude Code" button.
    ///
    /// Steps:
    ///   1. Find the `claude` CLI binary on the user's PATH
    ///   2. Copy the bundled marketplace from Fort Abode's app bundle to the stable
    ///      user-writable path (always refresh so wrapper updates are picked up)
    ///   3. `claude plugin marketplace add <path>` (idempotent — "already on disk" is success)
    ///   4. `claude plugin install weekly-rhythm-engine@fort-abode-marketplace`
    ///   5. Capture stdout/stderr, log breadcrumbs at every step, return structured result
    @discardableResult
    func installWeeklyRhythmPlugin() async -> PluginInstallResult {
        await ErrorLogger.shared.log(
            area: "installWeeklyRhythmPlugin",
            message: "STEP 1: starting plugin install via claude CLI"
        )

        // STEP 1: locate the claude CLI
        guard let claudePath = await findClaudeCLI() else {
            await ErrorLogger.shared.log(
                area: "installWeeklyRhythmPlugin",
                message: "FAILED at STEP 1: claude CLI not found on PATH or in common install locations"
            )
            lastInstallResult = .claudeCLINotFound
            return .claudeCLINotFound
        }
        await ErrorLogger.shared.log(
            area: "installWeeklyRhythmPlugin",
            message: "STEP 2: found claude CLI",
            context: ["claudePath": claudePath]
        )

        // STEP 3: copy bundled marketplace to the stable path
        let marketplacePath: URL
        do {
            marketplacePath = try copyBundledMarketplace()
            await ErrorLogger.shared.log(
                area: "installWeeklyRhythmPlugin",
                message: "STEP 3: bundled marketplace copied to stable path",
                context: ["path": marketplacePath.path]
            )
        } catch {
            let message = "Failed to copy bundled marketplace: \(error.localizedDescription)"
            await ErrorLogger.shared.log(
                area: "installWeeklyRhythmPlugin",
                message: "FAILED at STEP 3: \(message)"
            )
            let result = PluginInstallResult.failed(
                at: Date(),
                step: "copyBundledMarketplace",
                error: message,
                output: ""
            )
            lastInstallResult = result
            return result
        }

        // STEP 4: register the marketplace
        await ErrorLogger.shared.log(
            area: "installWeeklyRhythmPlugin",
            message: "STEP 4: running claude plugin marketplace add"
        )
        let marketplaceResult = runClaudeCLI(
            at: claudePath,
            args: ["plugin", "marketplace", "add", marketplacePath.path]
        )
        if marketplaceResult.exitCode != 0 {
            // `marketplace add` when the marketplace is already declared in user settings
            // prints "already on disk" and exits 0, so a non-zero exit is a real failure.
            let combined = "STDOUT:\n\(marketplaceResult.stdout)\n\nSTDERR:\n\(marketplaceResult.stderr)"
            await ErrorLogger.shared.log(
                area: "installWeeklyRhythmPlugin",
                message: "FAILED at STEP 4: claude plugin marketplace add exited \(marketplaceResult.exitCode)",
                context: ["stdout": marketplaceResult.stdout, "stderr": marketplaceResult.stderr]
            )
            let result = PluginInstallResult.failed(
                at: Date(),
                step: "marketplace add",
                error: marketplaceResult.stderr.isEmpty ? "exited with code \(marketplaceResult.exitCode)" : marketplaceResult.stderr,
                output: combined
            )
            lastInstallResult = result
            return result
        }
        await ErrorLogger.shared.log(
            area: "installWeeklyRhythmPlugin",
            message: "STEP 5: marketplace add succeeded",
            context: ["stdout": marketplaceResult.stdout]
        )

        // STEP 6: install the plugin
        await ErrorLogger.shared.log(
            area: "installWeeklyRhythmPlugin",
            message: "STEP 6: running claude plugin install"
        )
        let installResult = runClaudeCLI(
            at: claudePath,
            args: ["plugin", "install", Self.pluginIdentifier]
        )
        let combinedOutput = """
            marketplace add stdout:
            \(marketplaceResult.stdout)
            marketplace add stderr:
            \(marketplaceResult.stderr)

            plugin install stdout:
            \(installResult.stdout)
            plugin install stderr:
            \(installResult.stderr)
            """

        if installResult.exitCode != 0 {
            await ErrorLogger.shared.log(
                area: "installWeeklyRhythmPlugin",
                message: "FAILED at STEP 6: claude plugin install exited \(installResult.exitCode)",
                context: ["stdout": installResult.stdout, "stderr": installResult.stderr]
            )
            let result = PluginInstallResult.failed(
                at: Date(),
                step: "plugin install",
                error: installResult.stderr.isEmpty ? "exited with code \(installResult.exitCode)" : installResult.stderr,
                output: combinedOutput
            )
            lastInstallResult = result
            return result
        }

        await ErrorLogger.shared.log(
            area: "installWeeklyRhythmPlugin",
            message: "STEP 7: plugin install succeeded — DONE",
            context: ["stdout": installResult.stdout]
        )
        let result = PluginInstallResult.succeeded(at: Date(), output: combinedOutput)
        lastInstallResult = result
        return result
    }

    /// Uninstall the `weekly-rhythm-engine` plugin via `claude plugin uninstall`.
    /// Called from `ComponentListViewModel.uninstallComponent` for the weekly-rhythm
    /// component. Best-effort — if the CLI call fails, the uninstall still proceeds
    /// locally (engine-spec.md removal, config cleanup) so the user isn't stuck.
    @discardableResult
    func uninstallWeeklyRhythmPlugin() async -> Bool {
        await ErrorLogger.shared.log(
            area: "uninstallWeeklyRhythmPlugin",
            message: "starting plugin uninstall via claude CLI"
        )
        guard let claudePath = await findClaudeCLI() else {
            await ErrorLogger.shared.log(
                area: "uninstallWeeklyRhythmPlugin",
                message: "claude CLI not found — skipping CLI uninstall (rest of uninstall will proceed)"
            )
            return false
        }

        let result = runClaudeCLI(
            at: claudePath,
            args: ["plugin", "uninstall", Self.pluginIdentifier]
        )
        if result.exitCode == 0 {
            await ErrorLogger.shared.log(
                area: "uninstallWeeklyRhythmPlugin",
                message: "plugin uninstall succeeded",
                context: ["stdout": result.stdout]
            )
            return true
        } else {
            await ErrorLogger.shared.log(
                area: "uninstallWeeklyRhythmPlugin",
                message: "plugin uninstall exited \(result.exitCode) — likely already uninstalled, continuing",
                context: ["stdout": result.stdout, "stderr": result.stderr]
            )
            return false
        }
    }

    // MARK: - Private: CLI Discovery

    /// Find the `claude` CLI binary. Uses a login shell's `which claude` first (picks
    /// up user-local installs like `~/.local/bin/claude`), then falls back to common
    /// static paths. Same pattern as `UpdateExecutionService.findNodePath()`.
    private func findClaudeCLI() async -> String? {
        // Method 1: Login-shell `which claude` — handles $PATH additions from dotfiles
        if let path = runWhichClaude() {
            return path
        }

        // Method 2: Common static locations
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]
        for path in candidates {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func runWhichClaude() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which claude"]

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

            guard let path, !path.isEmpty, fm.fileExists(atPath: path) else { return nil }
            return path
        } catch {
            return nil
        }
    }

    // MARK: - Private: Bundled Marketplace

    /// Copy the bundled marketplace from Fort Abode's app bundle to a stable
    /// user-writable location. Always refreshes — if the stable path already
    /// exists, we remove and recopy so app updates that change the plugin
    /// content (e.g. a new wrapper version) are picked up.
    ///
    /// The bundled marketplace is declared in `project.yml` as a folder reference
    /// at `Resources/weekly-rhythm-plugin-bundle/`. After build, it lives inside
    /// the .app at `Contents/Resources/weekly-rhythm-plugin-bundle/`.
    private func copyBundledMarketplace() throws -> URL {
        // Bundle.main.url(forResource:withExtension:) works for individual files
        // but NOT for folder references. We look up the folder by constructing the
        // path manually from the bundle resource root.
        guard let resourcePath = Bundle.main.resourceURL else {
            throw CoworkSkillError.bundleResourceNotFound
        }
        let bundledDir = resourcePath.appendingPathComponent("weekly-rhythm-plugin-bundle")
        guard fm.fileExists(atPath: bundledDir.path) else {
            throw CoworkSkillError.bundleResourceNotFound
        }

        let destination = stableMarketplacePath

        // Ensure the parent directory exists
        let parent = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        // Remove the existing copy (if any) so we're always picking up the latest
        // wrapper content from the app bundle.
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        try fm.copyItem(at: bundledDir, to: destination)
        return destination
    }

    // MARK: - Private: CLI Invocation

    /// Run the `claude` CLI with the given arguments and capture stdout/stderr.
    /// Runs via a login shell so PATH entries from the user's dotfiles are available
    /// (node, git, etc. might be needed by plugin install internals).
    private func runClaudeCLI(
        at claudePath: String,
        args: [String]
    ) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = args

        // Inherit the user's login-shell environment by running through zsh -l -c
        // which picks up PATH additions from .zshrc / .zprofile. This matters for
        // `claude plugin install` because it may invoke git or other tools.
        var env = ProcessInfo.processInfo.environment
        // Ensure HOME is set — Process can sometimes drop it
        if env["HOME"] == nil {
            env["HOME"] = fm.homeDirectoryForCurrentUser.path
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (
                stdout: "",
                stderr: "Failed to run \(claudePath): \(error.localizedDescription)",
                exitCode: -1
            )
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return (stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

// MARK: - Errors

enum CoworkSkillError: LocalizedError {
    case bundleResourceNotFound

    var errorDescription: String? {
        switch self {
        case .bundleResourceNotFound:
            return "Bundled weekly-rhythm-plugin-bundle directory not found inside the Fort Abode app bundle. The build may be corrupted — reinstall Fort Abode."
        }
    }
}
