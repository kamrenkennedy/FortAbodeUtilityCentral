import Foundation

// File-backed `WeeklyRhythmDataSource`. Reads engine-emitted JSON from
// `~/.../Kennedy Family Docs/{Weekly Flow|Weekly Rhythm}/{user}/dashboards/
// dashboard-{ISODate}.json`. Falls back to `MockWeeklyRhythmDataSource` whenever
// the file is missing, unreadable, or fails to decode — so on Tiera's machine
// (where no engine has run yet) the app shows the same mock UI Kam's machine
// shows, never an empty page.
//
// `actor` matches the `WeeklyRhythmService` precedent for filesystem ops.
//
// The engine doesn't emit JSON yet (Phase 5b on the weekly-rhythm repo). This
// impl exists now so the moment the engine starts emitting, the app picks it
// up automatically — no swap needed.

public actor FileBackedWeeklyRhythmDataSource: WeeklyRhythmDataSourceImpl {

    private let resolver: WeeklyRhythmPathResolver
    private let mock: MockWeeklyRhythmDataSource
    private let calendar: Calendar
    private let isoDateFormatter: DateFormatter

    public init(
        resolver: WeeklyRhythmPathResolver = WeeklyRhythmPathResolver(),
        mock: MockWeeklyRhythmDataSource = MockWeeklyRhythmDataSource()
    ) {
        self.resolver = resolver
        self.mock = mock
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday
        self.calendar = cal

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        self.isoDateFormatter = fmt
    }

    public func fetch(weekOffset: Int) async -> WeeklyRhythmFetchResult {
        // Resolve iCloud root. nil = neither folder exists on this machine →
        // fall back to mock with a clear status.
        guard let resolved = resolver.resolve() else {
            return await mockResult(
                weekOffset: weekOffset,
                reason: "Weekly Flow folder not found in iCloud (not configured on this machine)"
            )
        }

        // Resolve the active user folder.
        guard let userName = resolved.detectActiveUser() else {
            return await mockResult(
                weekOffset: weekOffset,
                reason: "no user folder with config.md inside \(resolved.rootPath)"
            )
        }

        // Compute target file path.
        guard let mondayISO = mondayISODate(forWeekOffset: weekOffset) else {
            return await mockResult(
                weekOffset: weekOffset,
                reason: "could not compute monday ISO date for offset \(weekOffset)"
            )
        }
        let path = resolved.dashboardJSONPath(for: userName, isoDate: mondayISO)

        // Read + decode.
        guard FileManager.default.fileExists(atPath: path) else {
            return await mockResult(
                weekOffset: weekOffset,
                reason: "no dashboard JSON at \(path)"
            )
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WeeklyRhythmSnapshot.self, from: data)
            return WeeklyRhythmFetchResult(
                snapshot: snapshot,
                status: .real(generatedAt: snapshot.generatedAt)
            )
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.FileBacked",
                message: "failed to decode \(path)",
                context: ["error": "\(error)"]
            )
            return await mockResult(
                weekOffset: weekOffset,
                reason: "decode error at \(path): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private func mockResult(weekOffset: Int, reason: String) async -> WeeklyRhythmFetchResult {
        await ErrorLogger.shared.log(
            area: "WeeklyRhythm.FileBacked",
            message: "falling back to mock",
            context: ["weekOffset": "\(weekOffset)", "reason": reason]
        )
        let result = await mock.fetch(weekOffset: weekOffset)
        return WeeklyRhythmFetchResult(
            snapshot: result.snapshot,
            status: .mockFallback(reason: reason)
        )
    }

    /// Compute the Monday-of-week ISO date string for the given offset.
    /// `weekOffset = 0` is the Monday of the current week.
    private func mondayISODate(forWeekOffset weekOffset: Int) -> String? {
        let now = Date()
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        ) else {
            return nil
        }
        guard let target = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart) else {
            return nil
        }
        return isoDateFormatter.string(from: target)
    }
}
