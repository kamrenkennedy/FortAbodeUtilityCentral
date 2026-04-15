import Foundation

// MARK: - Error Log Entry

/// Single line in the Fort Abode log stream. Entries are written as JSON Lines (JSONL).
///
/// v3.7.4 changed the shape: the canonical fields are now `area` + `message` (+ optional
/// `context`) so breadcrumb instrumentation can coexist with component error logs in the
/// same file. The legacy `componentId` / `errorMessage` / `componentDisplayName` fields
/// are decoded on read if they appear in older log files so historical entries stay
/// readable in the debug report.
struct ErrorLogEntry: Sendable {
    let timestamp: Date
    let area: String                          // e.g. "CoworkSkillService.deploySkillFile" or "weekly-rhythm"
    let message: String                       // human-readable description of what happened
    let context: [String: String]?            // optional structured context
    let appVersion: String
    let macOSVersion: String

    // Optional component-specific fields (present when a call site has them)
    let componentDisplayName: String?
    let installedVersion: String?

    init(
        timestamp: Date = Date(),
        area: String,
        message: String,
        context: [String: String]? = nil,
        componentDisplayName: String? = nil,
        installedVersion: String? = nil
    ) {
        self.timestamp = timestamp
        self.area = area
        self.message = message
        self.context = context
        self.componentDisplayName = componentDisplayName
        self.installedVersion = installedVersion
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
    }
}

extension ErrorLogEntry: Codable {

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case area
        case message
        case context
        case appVersion
        case macOSVersion
        case componentDisplayName
        case installedVersion
        // Legacy (v3.7.3 and earlier) — read-only
        case componentId
        case errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        // Prefer new-format fields, fall back to legacy field names
        if let a = try container.decodeIfPresent(String.self, forKey: .area) {
            area = a
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .componentId) {
            area = legacy
        } else {
            area = "unknown"
        }

        if let m = try container.decodeIfPresent(String.self, forKey: .message) {
            message = m
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .errorMessage) {
            message = legacy
        } else {
            message = ""
        }

        context = try container.decodeIfPresent([String: String].self, forKey: .context)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
        macOSVersion = try container.decodeIfPresent(String.self, forKey: .macOSVersion) ?? "unknown"
        componentDisplayName = try container.decodeIfPresent(String.self, forKey: .componentDisplayName)
        installedVersion = try container.decodeIfPresent(String.self, forKey: .installedVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(area, forKey: .area)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(context, forKey: .context)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(macOSVersion, forKey: .macOSVersion)
        try container.encodeIfPresent(componentDisplayName, forKey: .componentDisplayName)
        try container.encodeIfPresent(installedVersion, forKey: .installedVersion)
    }
}

// MARK: - Write Status

/// Result of the most recent dual-write attempt. Surfaced in the debug report so we can
/// instantly tell whether the logger itself is functional on a given machine.
enum LoggerWriteStatus: Sendable {
    case notYetWritten
    case icloudOk(at: Date)
    case localOnlyOk(at: Date, icloudError: String)
    case bothFailed(at: Date, icloudError: String, localError: String)

    var description: String {
        let formatter = ISO8601DateFormatter()
        switch self {
        case .notYetWritten:
            return "no writes attempted yet"
        case .icloudOk(let at):
            return "iCloud write OK at \(formatter.string(from: at))"
        case .localOnlyOk(let at, let icloudError):
            return "iCloud FAILED (\(icloudError)) — local write OK at \(formatter.string(from: at))"
        case .bothFailed(let at, let icloudError, let localError):
            return "BOTH FAILED at \(formatter.string(from: at)): iCloud=\(icloudError); local=\(localError)"
        }
    }
}

// MARK: - Error Logger

/// Dual-write diagnostic logger.
///
/// **Storage layout (v3.7.4):**
/// - Primary: `~/Library/Mobile Documents/com~apple~CloudDocs/Claude Memory/Fort Abode Logs/errors.jsonl`
/// - Fallback: `~/Library/Logs/FortAbodeUtilityCentral/errors.jsonl`
///
/// Both paths are written on every `log()` call so a single write failure (iCloud offline,
/// folder missing, permission error) never eats the log line. The `lastWriteStatus` property
/// exposes what happened so `FeedbackService.generateDebugReport()` can include it in the
/// debug report — any bug report with `bothFailed` tells us to debug the logger before
/// trusting anything else in the report.
///
/// **Why the subfolder:** earlier versions wrote `fort-abode-errors.jsonl` loose inside the
/// Claude Memory iCloud folder, right next to the user's actual memory files. v3.7.4 moves
/// all Fort Abode logs into a dedicated `Fort Abode Logs/` subfolder so the user can nuke
/// the whole folder in Finder without touching their Claude memory. On first write, any
/// legacy loose file is migrated into the subfolder as `errors-legacy.jsonl`, and a
/// `README.txt` is dropped so the folder is self-explanatory.
actor ErrorLogger {

    static let shared = ErrorLogger()

    private(set) var lastWriteStatus: LoggerWriteStatus = .notYetWritten
    private var hasMigrated = false
    private var hasDroppedReadme = false

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Public API (v3.7.4: area/message/context)

    /// General-purpose log — use for breadcrumb instrumentation, failure diagnostics, and
    /// any event that isn't strictly a component error.
    func log(
        area: String,
        message: String,
        context: [String: String]? = nil,
        componentDisplayName: String? = nil,
        installedVersion: String? = nil
    ) {
        let entry = ErrorLogEntry(
            area: area,
            message: message,
            context: context,
            componentDisplayName: componentDisplayName,
            installedVersion: installedVersion
        )
        write(entry)
    }

    // MARK: - Public API (legacy, kept for backwards compat)

    /// Legacy component-error log. Preserved so existing call sites keep compiling unchanged.
    /// Internally creates the same ErrorLogEntry shape as the new log() method.
    func log(
        componentId: String,
        displayName: String,
        error: String,
        installedVersion: String?
    ) {
        let entry = ErrorLogEntry(
            area: componentId,
            message: error,
            context: nil,
            componentDisplayName: displayName,
            installedVersion: installedVersion
        )
        write(entry)
    }

    /// Heartbeat probe — call once on app launch. If this entry appears in Tiera's next
    /// debug report, the logger works on her machine and any downstream failures will be
    /// visible. If it doesn't appear, the logger itself is broken and needs fixing before
    /// we trust any other debug output.
    func logHeartbeat() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        log(
            area: "ErrorLogger.heartbeat",
            message: "App launched — logger is alive",
            context: ["appVersion": version, "build": build]
        )
    }

    // MARK: - Reading

    /// Read the most recent N entries from both log files, merged and sorted by timestamp.
    /// Returns newest entries last so the caller can prepend/append in order.
    func recentErrors(limit: Int = 50) -> [ErrorLogEntry] {
        var merged: [ErrorLogEntry] = []
        if let url = icloudLogURL() {
            merged.append(contentsOf: readEntries(at: url))
        }
        merged.append(contentsOf: readEntries(at: localLogURL()))

        merged.sort { $0.timestamp < $1.timestamp }
        return Array(merged.suffix(limit))
    }

    // MARK: - Private: Write

    private func write(_ entry: ErrorLogEntry) {
        // Encode the entry to a single JSONL line
        guard let data = try? encoder.encode(entry),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let line = json + "\n"

        // Run folder housekeeping once per session
        if !hasMigrated {
            migrateLegacyFileIfNeeded()
            hasMigrated = true
        }
        if !hasDroppedReadme {
            dropReadmeIfNeeded()
            hasDroppedReadme = true
        }

        // Always try both paths. If iCloud is offline or the folder doesn't exist,
        // the local fallback still gets the entry so nothing is dropped silently.
        let icloudResult = tryWrite(line, to: icloudLogURL())
        let localResult = tryWrite(line, to: localLogURL())

        let now = Date()
        switch (icloudResult, localResult) {
        case (.success, _):
            lastWriteStatus = .icloudOk(at: now)
        case (.failure(let icloudErr), .success):
            lastWriteStatus = .localOnlyOk(at: now, icloudError: icloudErr.localizedDescription)
        case (.failure(let icloudErr), .failure(let localErr)):
            lastWriteStatus = .bothFailed(
                at: now,
                icloudError: icloudErr.localizedDescription,
                localError: localErr.localizedDescription
            )
        }
    }

    private func tryWrite(_ line: String, to url: URL?) -> Result<Void, Error> {
        guard let url else {
            return .failure(LoggerError.pathUnavailable)
        }
        guard let data = line.data(using: .utf8) else {
            return .failure(LoggerError.encodingFailed)
        }

        do {
            try ensureDirectoryExists(url.deletingLastPathComponent())

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private: Read

    private func readEntries(at url: URL) -> [ErrorLogEntry] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.compactMap { line -> ErrorLogEntry? in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ErrorLogEntry.self, from: data)
        }
    }

    // MARK: - Private: Paths

    /// New iCloud path:
    /// `~/Library/Mobile Documents/com~apple~CloudDocs/Claude Memory/Fort Abode Logs/errors.jsonl`
    ///
    /// Returns nil if the Claude Memory folder doesn't exist — we never create Claude Memory
    /// from scratch just to drop logs in it. If nil, the dual-write falls through to the
    /// local path only.
    private func icloudLogURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeMemory = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/Claude Memory"
        )
        guard FileManager.default.fileExists(atPath: claudeMemory.path) else {
            return nil
        }
        return claudeMemory
            .appendingPathComponent("Fort Abode Logs")
            .appendingPathComponent("errors.jsonl")
    }

    /// Local fallback — always available, auto-created on first write.
    private func localLogURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Logs/FortAbodeUtilityCentral")
            .appendingPathComponent("errors.jsonl")
    }

    // MARK: - Private: Migration + README

    /// If a legacy loose `fort-abode-errors.jsonl` exists at the Claude Memory root from
    /// v3.7.3 or earlier, move it into the new `Fort Abode Logs/` subfolder as
    /// `errors-legacy.jsonl` so the old entries stay available and nothing gets left behind
    /// at the Claude Memory root.
    private func migrateLegacyFileIfNeeded() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let legacy = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/Claude Memory/fort-abode-errors.jsonl"
        )
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        guard let destination = icloudLogURL() else { return }

        let migratedName = destination
            .deletingLastPathComponent()
            .appendingPathComponent("errors-legacy.jsonl")

        do {
            try ensureDirectoryExists(migratedName.deletingLastPathComponent())
            if FileManager.default.fileExists(atPath: migratedName.path) {
                // Already migrated in a prior run — just remove the stray source file
                try? FileManager.default.removeItem(at: legacy)
                return
            }
            try FileManager.default.moveItem(at: legacy, to: migratedName)
        } catch {
            // Best-effort. If the move fails, the legacy file stays where it is and new
            // writes still land in the new location — nothing is lost.
        }
    }

    /// Drop a README.txt into `Fort Abode Logs/` once so a human browsing the folder in
    /// Finder immediately understands what it is and that it's safe to delete.
    private func dropReadmeIfNeeded() {
        guard let logURL = icloudLogURL() else { return }
        let readmeURL = logURL
            .deletingLastPathComponent()
            .appendingPathComponent("README.txt")
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else { return }

        let contents = """
            This folder contains diagnostic logs from Fort Abode Utility Central.

            errors.jsonl        — current error + instrumentation log (JSON Lines format)
            errors-legacy.jsonl — prior logs migrated from the old location (if present)

            Safe to delete at any time — Fort Abode will recreate this folder as needed.
            """
        do {
            try ensureDirectoryExists(readmeURL.deletingLastPathComponent())
            try contents.write(to: readmeURL, atomically: true, encoding: .utf8)
        } catch {
            // Best-effort.
        }
    }
}

// MARK: - Logger Errors

private enum LoggerError: LocalizedError {
    case pathUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .pathUnavailable:
            return "log path unavailable"
        case .encodingFailed:
            return "encoding failed"
        }
    }
}
