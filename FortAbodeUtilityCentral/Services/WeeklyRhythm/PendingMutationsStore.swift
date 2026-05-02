import Foundation

// Actor wrapper around the sibling pending-mutations JSON file at
// `{user}/dashboards/dashboard-{ISODate}-pending.json`. The app writes user
// mutations here; the engine drains the file on its next run by applying each
// entry to the appropriate destination (Apple Reminders, Google Calendar,
// Memory MCP) and renaming the file to `…-pending.applied-{ISO}.json` for a
// 30-day audit breadcrumb.
//
// All file IO is atomic (Data.write `.atomic` does .tmp + rename under the
// hood). Reads are tolerant: a missing file is the happy path (most weeks
// won't accumulate any mutations); a malformed file logs a warning and is
// treated as empty rather than crashing.
//
// See `Resources/dashboard-json-shape.md` for the wire-format spec.

public actor PendingMutationsStore {

    public init() {}

    /// Read the pending bundle at `path`. nil = file doesn't exist or fails to
    /// decode. Decode failures are logged via ErrorLogger.
    public func read(at path: String) async -> PendingMutationsBundle? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PendingMutationsBundle.self, from: data)
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.PendingMutations",
                message: "failed to decode pending mutations file",
                context: ["path": path, "error": "\(error)"]
            )
            return nil
        }
    }

    /// Append a mutation entry. Reads the existing bundle (or creates a new
    /// one for `weekISODate`), appends, writes back atomically. Returns true
    /// on success.
    public func append(
        _ entry: PendingMutationEntry,
        weekISODate: String,
        at path: String
    ) async -> Bool {
        var bundle = await read(at: path) ?? PendingMutationsBundle(weekISODate: weekISODate)
        bundle.mutations.append(entry)
        return await write(bundle, to: path)
    }

    /// Atomic write. Creates intermediate directories. Returns true on
    /// success, false on any failure (logged).
    public func write(_ bundle: PendingMutationsBundle, to path: String) async -> Bool {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.PendingMutations",
                message: "failed to create directory",
                context: ["dir": dir.path, "error": "\(error)"]
            )
            return false
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(bundle)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.PendingMutations",
                message: "failed to write pending mutations file",
                context: ["path": path, "error": "\(error)"]
            )
            return false
        }
    }
}
