import Foundation

/// Manages CLAUDE.md template deployment and Claude Code settings.json hooks.
/// Runs during Memory MCP install to set up session protocol for the family.
actor ClaudeCodeConfigService {

    private let fm = FileManager.default

    private var homePath: String {
        fm.homeDirectoryForCurrentUser.path
    }

    /// iCloud path where the shared CLAUDE.md template lives
    private var iCloudClaudePath: String {
        "\(homePath)/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Claude"
    }

    /// The iCloud CLAUDE.md file
    private var iCloudClaudeMD: String {
        "\(iCloudClaudePath)/CLAUDE.md"
    }

    /// The local symlink that Claude Code reads
    private var claudeMDSymlink: String {
        "\(homePath)/.claude/CLAUDE.md"
    }

    /// Claude Code user settings
    private var settingsPath: String {
        "\(homePath)/.claude/settings.json"
    }

    // MARK: - CLAUDE.md Setup

    /// Deploy the CLAUDE.md template and symlink if not already configured.
    /// Does NOT overwrite existing CLAUDE.md — respects user customizations.
    func setupClaudeMD() async throws {
        // If the symlink or file already exists, don't touch it
        if fm.fileExists(atPath: claudeMDSymlink) {
            return
        }

        // Ensure the iCloud Claude directory exists
        if !fm.fileExists(atPath: iCloudClaudePath) {
            try fm.createDirectory(atPath: iCloudClaudePath, withIntermediateDirectories: true)
        }

        // Write the template to iCloud if no CLAUDE.md there yet
        if !fm.fileExists(atPath: iCloudClaudeMD) {
            guard let templateURL = Bundle.main.url(forResource: "claude-md-template", withExtension: "md"),
                  let templateContent = try? String(contentsOf: templateURL, encoding: .utf8) else {
                throw ClaudeCodeConfigError.templateNotFound
            }
            try templateContent.write(toFile: iCloudClaudeMD, atomically: true, encoding: .utf8)
        }

        // Ensure ~/.claude/ directory exists
        let claudeDir = "\(homePath)/.claude"
        if !fm.fileExists(atPath: claudeDir) {
            try fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        }

        // Create symlink: ~/.claude/CLAUDE.md → iCloud path
        try fm.createSymbolicLink(atPath: claudeMDSymlink, withDestinationPath: iCloudClaudeMD)
    }

    // MARK: - Settings.json Hooks

    /// Add session-wrap stop hook to settings.json if not already present.
    /// Preserves all existing settings — only adds the hook.
    func setupSettingsHooks() async throws {
        var settings: [String: Any] = [:]

        // Read existing settings if file exists
        if fm.fileExists(atPath: settingsPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
            if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
        }

        // Check if hooks.Stop already has our session-wrap hook
        if let hooks = settings["hooks"] as? [String: Any],
           let stopHooks = hooks["Stop"] as? [[String: Any]] {
            let hasSessionWrap = stopHooks.contains { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { hook in
                    (hook["type"] as? String) == "prompt" &&
                    ((hook["prompt"] as? String) ?? "").contains("session wrap")
                }
            }
            if hasSessionWrap { return }
        }

        // Build the stop hook
        let sessionWrapHook: [String: Any] = [
            "matcher": "",
            "hooks": [
                [
                    "type": "prompt",
                    "prompt": "Before ending, run the session wrap: update Memory MCP with current status and Deep Context with a session summary."
                ]
            ]
        ]

        // Merge into existing hooks
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var stopHooks = hooks["Stop"] as? [[String: Any]] ?? []
        stopHooks.append(sessionWrapHook)
        hooks["Stop"] = stopHooks
        settings["hooks"] = hooks

        // Ensure ~/.claude/ directory exists
        let claudeDir = (settingsPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: claudeDir) {
            try fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        }

        // Write back — pretty-printed for human readability
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }

    // MARK: - Status Checks

    /// Whether CLAUDE.md is already configured (symlink exists pointing to iCloud)
    func isClaudeMDConfigured() -> Bool {
        fm.fileExists(atPath: claudeMDSymlink)
    }

    /// Read the template version from the first line comment marker
    func templateVersion() -> String? {
        guard let content = try? String(contentsOfFile: iCloudClaudeMD, encoding: .utf8),
              let firstLine = content.components(separatedBy: "\n").first,
              firstLine.contains("Fort Abode Template v") else {
            return nil
        }
        // Extract version from "<!-- Fort Abode Template v1.0 — Do not remove this line -->"
        let pattern = "v([0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)),
              let range = Range(match.range(at: 1), in: firstLine) else {
            return nil
        }
        return String(firstLine[range])
    }
}

enum ClaudeCodeConfigError: LocalizedError {
    case templateNotFound

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "CLAUDE.md template not found in app bundle"
        }
    }
}
