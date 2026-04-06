import Foundation

// MARK: - Version Detection Service

actor VersionDetectionService {

    /// Detect the installed version for a given version source
    func detectInstalledVersion(for source: VersionSource) async -> String? {
        switch source {
        case .npxCache(let packageName):
            return scanNpxCache(for: packageName)
        case .localDirectory(let name):
            return checkLocalDirectory(name: name)
        case .packageJSON(let path):
            return readPackageJSON(at: path)
        case .claudeDesktopConfig(let serverKey):
            return checkClaudeDesktopConfig(serverKey: serverKey)
        }
    }

    // MARK: - npx Cache Scanning

    /// Scans ~/.npm/_npx/*/node_modules/{packageName}/package.json for the version field.
    /// Uses the most recently modified entry if multiple caches exist.
    private func scanNpxCache(for packageName: String) -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let npxCacheDir = homeDir.appendingPathComponent(".npm/_npx")

        guard let cacheEntries = try? FileManager.default.contentsOfDirectory(
            at: npxCacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var bestVersion: String?
        var bestDate: Date = .distantPast

        for entry in cacheEntries {
            let packageJsonPath = entry
                .appendingPathComponent("node_modules")
                .appendingPathComponent(packageName)
                .appendingPathComponent("package.json")

            guard FileManager.default.fileExists(atPath: packageJsonPath.path) else { continue }

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: packageJsonPath.path),
                  let modDate = attrs[.modificationDate] as? Date else { continue }

            if let version = readVersionFromPackageJSON(at: packageJsonPath), modDate > bestDate {
                bestVersion = version
                bestDate = modDate
            }
        }

        return bestVersion
    }

    // MARK: - Local Directory

    private func checkLocalDirectory(name: String) -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let mcpDir = homeDir.appendingPathComponent("mcp-servers/\(name)")

        // Check if directory exists
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: mcpDir.path, isDirectory: &isDir), isDir.boolValue {
            // Try to read package.json for a version
            let packageJson = mcpDir.appendingPathComponent("package.json")
            if let version = readVersionFromPackageJSON(at: packageJson) {
                return version
            }
            // Directory exists but no version info — mark as installed
            return "installed"
        }

        return nil
    }

    // MARK: - Package JSON

    private func readPackageJSON(at path: String) -> String? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return readVersionFromPackageJSON(at: url)
    }

    // MARK: - Claude Desktop Config

    private func checkClaudeDesktopConfig(serverKey: String) -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDir
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")

        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: Any] else {
            return nil
        }

        // If serverKey ends with "-", treat it as a prefix match (multi-instance)
        if serverKey.hasSuffix("-") {
            let hasMatch = mcpServers.keys.contains { $0.hasPrefix(serverKey) }
            return hasMatch ? "configured" : nil
        }

        return mcpServers[serverKey] != nil ? "configured" : nil
    }

    // MARK: - Helpers

    private func readVersionFromPackageJSON(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            return nil
        }
        return version
    }
}
