import Foundation

// MARK: - Claude Desktop Config Service

/// Actor that manages reads and writes to Claude Desktop's configuration file.
/// Actor isolation serializes concurrent access and prevents file corruption.
actor ClaudeDesktopConfigService {

    // MARK: - Properties

    private let configURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.configURL = home
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    // MARK: - Public API

    /// Add or overwrite MCP server entries in the config file.
    /// Replaces `{{MEMORY_PATH}}` in args with the provided memoryPath.
    /// Preserves all other top-level keys (preferences, etc.) and existing mcpServers entries.
    func addServerEntries(_ entries: [ClaudeConfigEntry], memoryPath: String?) throws {
        var root = try readConfig()
        var servers = root["mcpServers"] as? [String: Any] ?? [:]

        for entry in entries {
            let resolvedArgs = entry.args.map { arg -> String in
                if let path = memoryPath {
                    return arg.replacingOccurrences(of: "{{MEMORY_PATH}}", with: path)
                }
                return arg
            }

            servers[entry.key] = [
                "command": entry.command,
                "args": resolvedArgs
            ]
        }

        root["mcpServers"] = servers
        try writeConfig(root)
    }

    /// Remove MCP server entries from the config file by key.
    /// Returns the keys that were actually removed.
    @discardableResult
    func removeServerEntries(keys: [String]) throws -> [String] {
        var root = try readConfig()
        var servers = root["mcpServers"] as? [String: Any] ?? [:]

        var removed: [String] = []
        for key in keys {
            if servers.removeValue(forKey: key) != nil {
                removed.append(key)
            }
        }

        root["mcpServers"] = servers
        try writeConfig(root)
        return removed
    }

    /// Check if all specified keys exist in the mcpServers dictionary.
    func hasEntries(keys: [String]) -> Bool {
        guard let root = try? readConfig(),
              let servers = root["mcpServers"] as? [String: Any] else {
            return false
        }
        return keys.allSatisfy { servers[$0] != nil }
    }

    // MARK: - Private

    private func readConfig() throws -> [String: Any] {
        let fm = FileManager.default

        // If the file doesn't exist, return a seed structure
        guard fm.fileExists(atPath: configURL.path) else {
            return ["mcpServers": [String: Any]()]
        }

        let data = try Data(contentsOf: configURL)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.malformedJSON
        }

        return json
    }

    private func writeConfig(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )

        // Ensure parent directory exists
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try data.write(to: configURL, options: .atomic)
    }

    // MARK: - Errors

    enum ConfigError: LocalizedError {
        case malformedJSON

        var errorDescription: String? {
            switch self {
            case .malformedJSON:
                return "claude_desktop_config.json is malformed — cannot safely modify it"
            }
        }
    }
}
