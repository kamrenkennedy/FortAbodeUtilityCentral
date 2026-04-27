import Foundation

// MARK: - Claude CLI Detector
//
// Phase 6 (embedded engine runner): finds the `claude` CLI binary on the
// user's machine. Search order — user override → `which claude` → common
// install locations. Returns `.found(path, version)` or `.notFound` so the
// UI layer can either spawn a run or surface the install prompt.
//
// Detection is cheap (a process spawn or two) but we still let the store
// cache the result per-session and force a refresh from Settings so a fresh
// `brew install claude` shows up without needing an app restart.

public struct ClaudeCLIDetector: Sendable {

    public enum Result: Sendable, Equatable {
        case found(path: String, version: String)
        case notFound
    }

    public init() {}

    /// Run the full detection waterfall. Returns the first hit.
    public func detect() async -> Result {
        // 1. Honor the explicit override if the user pinned a path in Settings.
        let defaults = UserDefaults.standard
        if let override = defaults.string(forKey: AppSettingsKey.weeklyRhythmEngineCLIPathOverride),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override),
           let version = await captureVersion(at: override) {
            return .found(path: override, version: version)
        }

        // 2. `which claude` honors the user's PATH (zsh login shell, fnm/nvm shims, etc).
        if let path = await whichClaude(),
           let version = await captureVersion(at: path) {
            return .found(path: path, version: version)
        }

        // 3. Fall back to the common install locations a user might have without
        // those locations on the GUI app's PATH (Sparkle-launched processes
        // inherit a minimal PATH).
        for path in candidatePaths() {
            if FileManager.default.isExecutableFile(atPath: path),
               let version = await captureVersion(at: path) {
                return .found(path: path, version: version)
            }
        }

        return .notFound
    }

    // MARK: - Private

    private func candidatePaths() -> [String] {
        let home = NSHomeDirectory() as NSString
        return [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/bin/claude")
        ]
    }

    /// Run `which claude` under the user's login shell so PATH additions from
    /// `.zshrc` / `.zprofile` are picked up. The GUI app inherits launchd's
    /// minimal PATH otherwise.
    private func whichClaude() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // `-l` runs as a login shell so `.zprofile` (where Homebrew typically
        // exports `/opt/homebrew/bin`) is sourced. `-c` runs the inline command.
        process.arguments = ["-l", "-c", "command -v claude"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Run `<path> --version` and return the trimmed first line. Falls back to
    /// `"installed"` if the binary exists but doesn't print a parseable version
    /// — better than refusing to surface a working CLI just because we can't
    /// label it.
    private func captureVersion(at path: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus == 0, !raw.isEmpty {
            // First line tends to be the version string; anything below is
            // help-text noise.
            return raw.split(separator: "\n").first.map(String.init) ?? raw
        }
        return process.terminationStatus == 0 ? "installed" : nil
    }
}
