import Foundation

/// Read/write completion state for action items in the shared family memory
/// folder. Sibling to `FamilyMemoryService` (which is read-only) — this one
/// is the only place Fort Abode is allowed to write to that folder, and only
/// for the dynamic completion file (`facts-completion-state.json`). Static
/// facts (FAMILY_MEMORY.md, facts.json) are still authored exclusively by
/// Claude family-memory routing.
///
/// Cross-Mac sync: the completion JSON lives in the SAME shared iCloud folder
/// as facts.json itself (`Kennedy Family Docs/Claude/Family Memory/`). Both
/// Kam's and Tiera's Macs see the same file via iCloud Folder Sharing, so a
/// checkbox toggled on one Mac propagates to the other.
///
/// Atomicity: writes go to a temp file in the same directory and rename onto
/// the target with `Data.write(options: .atomic)`. Reads tolerate file-not-
/// exists by returning an empty default state.
///
/// changelog.md: every toggle appends a single-line entry to the shared
/// changelog (append-only per Kam's family-memory protocol). Format matches
/// the existing protocol — ISO timestamp, initials, short description.
actor FamilyMemoryCompletionService {

    private let fm = FileManager.default

    // MARK: - Paths

    nonisolated private static var folderPath: String {
        FamilyMemoryService.folderPath
    }

    private var completionStatePath: String {
        "\(Self.folderPath)/facts-completion-state.json"
    }

    private var changelogPath: String {
        "\(Self.folderPath)/changelog.md"
    }

    // MARK: - Read

    /// Load the completion state. Missing file returns an empty default.
    /// Decode errors are logged and also return the empty default — a
    /// corrupt file shouldn't lock out toggling new items.
    func loadState() async -> ActionItemCompletionState {
        guard fm.fileExists(atPath: completionStatePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: completionStatePath)) else {
            return ActionItemCompletionState()
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ActionItemCompletionState.self, from: data)
        } catch {
            await ErrorLogger.shared.log(
                area: "FamilyMemoryCompletionService.loadState",
                message: "Failed to decode facts-completion-state.json: \(error.localizedDescription) — returning empty state"
            )
            return ActionItemCompletionState()
        }
    }

    /// Convenience: return ActionItem rows ready to render, by combining the
    /// static labels from facts.json with the dynamic completion state.
    func actionItems(from labels: [String]) async -> [ActionItem] {
        let state = await loadState()
        return labels.map { label in
            let key = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return ActionItem(label: label, completion: state.actionItems2026[key])
        }
    }

    // MARK: - Write

    enum CompletionWriteError: LocalizedError {
        case folderUnavailable
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .folderUnavailable:    return "Family Memory folder not available."
            case .writeFailed(let msg): return "Failed to save completion: \(msg)"
            }
        }
    }

    /// Toggle completion for a single action item. Atomic write to the JSON
    /// file + append a line to changelog.md. `actor: String` is the user
    /// performing the action, e.g. "Kamren" or "Tiera" — surfaces in the
    /// completion record + changelog signature.
    @discardableResult
    func setCompleted(
        label: String,
        completed: Bool,
        actor: String
    ) async throws -> ActionItem {
        let key = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw CompletionWriteError.writeFailed("empty label")
        }
        guard fm.fileExists(atPath: Self.folderPath) else {
            throw CompletionWriteError.folderUnavailable
        }

        var state = await loadState()
        let now = Date()
        let isoNow = Self.iso8601.string(from: now)

        if completed {
            state.actionItems2026[key] = ActionItemCompletion(
                completed: true,
                completedAt: now,
                completedBy: actor
            )
        } else {
            // Mark explicitly as un-completed rather than removing the key, so
            // we keep the audit trail of who unchecked what when. A missing
            // key would also render as un-completed but loses provenance.
            state.actionItems2026[key] = ActionItemCompletion(
                completed: false,
                completedAt: now,
                completedBy: actor
            )
        }
        state.schemaVersion = max(state.schemaVersion, 1)
        state.lastModified = isoNow
        state.lastModifiedBy = actor

        try await persistState(state)
        await appendChangelog(label: label, completed: completed, actor: actor, at: now)

        return ActionItem(label: label, completion: state.actionItems2026[key])
    }

    // MARK: - Private

    private func persistState(_ state: ActionItemCompletionState) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw CompletionWriteError.writeFailed("encode: \(error.localizedDescription)")
        }

        let url = URL(fileURLWithPath: completionStatePath)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            await ErrorLogger.shared.log(
                area: "FamilyMemoryCompletionService.persistState",
                message: "Atomic write failed for \(completionStatePath): \(error.localizedDescription)"
            )
            throw CompletionWriteError.writeFailed("write: \(error.localizedDescription)")
        }
    }

    /// Append a single line to the shared changelog. Format matches the
    /// existing convention used by Claude family-memory routing:
    ///   `- 2026-04-30T20:25 KK — Marked action item complete: "..."`
    /// Failures are logged but don't propagate — the JSON write is the
    /// load-bearing persistence; the changelog is supplementary.
    private func appendChangelog(label: String, completed: Bool, actor: String, at date: Date) async {
        let initials = Self.initials(from: actor)
        let short = Self.shortTimestamp.string(from: date)
        let verb = completed ? "Marked complete" : "Unmarked"
        let truncatedLabel: String = {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 100 ? String(trimmed.prefix(97)) + "…" : trimmed
        }()
        let line = "- \(short) \(initials) — \(verb) action item: \"\(truncatedLabel)\"\n"

        let url = URL(fileURLWithPath: changelogPath)
        do {
            if fm.fileExists(atPath: changelogPath) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                let header = "# Family Memory changelog\n\nAppend-only log of changes to FAMILY_MEMORY.md, facts.json, and completion state.\n\n"
                try (header + line).write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            await ErrorLogger.shared.log(
                area: "FamilyMemoryCompletionService.appendChangelog",
                message: "changelog append failed: \(error.localizedDescription)"
            )
        }
    }

    // ISO8601DateFormatter is documented thread-safe, but Swift 6 doesn't see
    // that. `nonisolated(unsafe)` is Apple's recommended escape hatch for
    // immutable singletons of Foundation classes that aren't Sendable yet.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let shortTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "Kamren" → "KK", "Tiera" → "TK" (legacy convention used in the
    /// shared changelog by Claude routing). Kennedy is implied — initials
    /// pair the first letter of first name with K.
    private static func initials(from actor: String) -> String {
        let trimmed = actor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "??" }
        return "\(first.uppercased())K"
    }
}
