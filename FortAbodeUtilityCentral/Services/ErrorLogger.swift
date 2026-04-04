import Foundation

// MARK: - Error Log Entry

struct ErrorLogEntry: Codable, Sendable {
    let timestamp: Date
    let componentId: String
    let componentDisplayName: String
    let errorMessage: String
    let installedVersion: String?
    let appVersion: String
    let macOSVersion: String
}

// MARK: - Error Logger

/// Silently logs errors to a shared iCloud folder so they can be reviewed remotely.
/// Falls back to ~/Library/Logs/ if iCloud path is unavailable.
actor ErrorLogger {

    static let shared = ErrorLogger()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Log an error for a component
    func log(componentId: String, displayName: String, error: String, installedVersion: String?) {
        let entry = ErrorLogEntry(
            timestamp: Date(),
            componentId: componentId,
            componentDisplayName: displayName,
            errorMessage: error,
            installedVersion: installedVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )

        guard let data = try? encoder.encode(entry) else { return }
        guard let line = String(data: data, encoding: .utf8) else { return }

        let logPath = resolveLogPath()
        appendLine(line, to: logPath)
    }

    // MARK: - Private

    private func resolveLogPath() -> URL {
        // Try iCloud shared folder first (Claude Memory folder)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let iCloudPath = homeDir
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Claude Memory")

        if FileManager.default.fileExists(atPath: iCloudPath.path) {
            return iCloudPath.appendingPathComponent("fort-abode-errors.jsonl")
        }

        // Fallback to local logs
        let logsDir = homeDir.appendingPathComponent("Library/Logs/FortAbodeUtilityCentral")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("errors.jsonl")
    }

    private func appendLine(_ line: String, to url: URL) {
        let lineWithNewline = line + "\n"
        guard let data = lineWithNewline.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
