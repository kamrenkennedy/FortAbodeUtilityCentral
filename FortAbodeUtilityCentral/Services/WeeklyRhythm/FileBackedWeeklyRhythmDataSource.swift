import Foundation

// File-backed `WeeklyRhythmDataSource`. Reads engine-emitted JSON from
// `~/.../Kennedy Family Docs/{Weekly Flow|Weekly Rhythm}/{user}/dashboards/
// dashboard-{ISODate}.json`. Falls back to `MockWeeklyRhythmDataSource` whenever
// the file is missing, unreadable, or fails to decode — so on Tiera's machine
// (where no engine has run yet) the app shows the same mock UI Kam's machine
// shows, never an empty page.
//
// Phase 5b: also persists user mutations and replays them on load.
//   • `dayTypeChange` → `ConfigMdEditor` writes to `{user}/config.md`
//   • `errandReorder` → `WeeklyRhythmUIStateStore` (Application Support, app-local)
//   • everything else → `PendingMutationsStore` writes to
//     `{user}/dashboards/dashboard-{ISODate}-pending.json` for the engine to
//     drain on its next run
// On load, pending mutations + UI state are replayed on top of the engine
// snapshot so the user's intent survives across app restarts and engine runs
// that haven't yet drained the pending file.
//
// `actor` matches the `WeeklyRhythmService` precedent for filesystem ops.

public actor FileBackedWeeklyRhythmDataSource: WeeklyRhythmDataSourceImpl {

    private let resolver: WeeklyRhythmPathResolver
    private let mock: MockWeeklyRhythmDataSource
    private let pendingStore: PendingMutationsStore
    private let configEditor: ConfigMdEditor
    private let uiStateStore: WeeklyRhythmUIStateStore
    private let calendar: Calendar
    private let isoDateFormatter: DateFormatter

    public init(
        resolver: WeeklyRhythmPathResolver = WeeklyRhythmPathResolver(),
        mock: MockWeeklyRhythmDataSource = MockWeeklyRhythmDataSource(),
        pendingStore: PendingMutationsStore = PendingMutationsStore(),
        configEditor: ConfigMdEditor = ConfigMdEditor(),
        uiStateStore: WeeklyRhythmUIStateStore = WeeklyRhythmUIStateStore()
    ) {
        self.resolver = resolver
        self.mock = mock
        self.pendingStore = pendingStore
        self.configEditor = configEditor
        self.uiStateStore = uiStateStore
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday
        self.calendar = cal

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        self.isoDateFormatter = fmt
    }

    // MARK: - Fetch

    public func fetch(weekOffset: Int) async -> WeeklyRhythmFetchResult {
        let context = await resolveContext(weekOffset: weekOffset)
        let baseResult = await loadBaseSnapshot(weekOffset: weekOffset, context: context)

        // Replay queued mutations + UI state on top of the base snapshot so
        // the user's intent survives across app restarts and partial engine
        // drains. If we couldn't resolve a context (e.g. iCloud folder
        // missing on this machine) there's nothing to replay; return base.
        guard let context else {
            return baseResult
        }

        var snapshot = baseResult.snapshot

        // 1. Pending mutations
        if let bundle = await pendingStore.read(at: context.pendingPath) {
            for entry in bundle.mutations {
                MutationApplier.apply(entry.mutation, to: &snapshot)
            }
        }

        // 2. UI state (errand sort order)
        let uiState = await uiStateStore.read(weekISODate: context.mondayISO)
        if !uiState.errandOrder.isEmpty {
            MutationApplier.apply(
                .errandReorder(orderedIDs: uiState.errandOrder),
                to: &snapshot
            )
        }

        return WeeklyRhythmFetchResult(snapshot: snapshot, status: baseResult.status)
    }

    // MARK: - Persist (Phase 5b)

    public func persist(mutation: WeeklyRhythmMutation, weekOffset: Int) async -> Bool {
        guard let context = await resolveContext(weekOffset: weekOffset) else {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.FileBacked",
                message: "cannot persist mutation — no resolved iCloud context",
                context: ["weekOffset": "\(weekOffset)"]
            )
            return false
        }

        switch mutation {
        case .dayTypeChange(let weekdayName, let newType):
            return await configEditor.updateDayType(
                weekdayName: weekdayName,
                newType: newType,
                configPath: context.configPath
            )

        case .errandReorder(let orderedIDs):
            let state = WeeklyRhythmUIStateStore.WeekUIState(errandOrder: orderedIDs)
            return await uiStateStore.write(state, weekISODate: context.mondayISO)

        case .errandDoneToggle, .eventMove, .proposalAccept, .proposalDecline,
             .eventEdit, .reminderEdit, .triageEdit, .triageRsvp, .errandEdit:
            let entry = PendingMutationEntry(mutation: mutation)
            return await pendingStore.append(
                entry,
                weekISODate: context.mondayISO,
                at: context.pendingPath
            )
        }
    }

    // MARK: - Context resolution
    //
    // `ResolvedContext` bundles everything fetch + persist need: the active
    // user, the Monday ISO date for this week offset, and the derived file
    // paths. nil means we can't reach iCloud (folder missing, no user folder,
    // bad date math) — caller falls back to mock for fetch and refuses to
    // persist for write paths.

    private struct ResolvedContext {
        let userName: String
        let mondayISO: String
        let dashboardPath: String
        let pendingPath: String
        let configPath: String
    }

    private func resolveContext(weekOffset: Int) async -> ResolvedContext? {
        guard let resolved = resolver.resolve() else { return nil }
        guard let userName = resolved.detectActiveUser() else { return nil }
        guard let mondayISO = mondayISODate(forWeekOffset: weekOffset) else { return nil }
        return ResolvedContext(
            userName: userName,
            mondayISO: mondayISO,
            dashboardPath: resolved.dashboardJSONPath(for: userName, isoDate: mondayISO),
            pendingPath: resolved.pendingMutationsPath(for: userName, isoDate: mondayISO),
            configPath: resolved.configPath(for: userName)
        )
    }

    /// Load the base snapshot from the engine JSON file, or fall back to the
    /// mock with a logged reason. Pure read — replay happens after.
    private func loadBaseSnapshot(
        weekOffset: Int,
        context: ResolvedContext?
    ) async -> WeeklyRhythmFetchResult {
        guard let context else {
            return await mockResult(
                weekOffset: weekOffset,
                reason: "Weekly Flow folder not found in iCloud (not configured on this machine)"
            )
        }

        guard FileManager.default.fileExists(atPath: context.dashboardPath) else {
            return await mockResult(
                weekOffset: weekOffset,
                reason: "no dashboard JSON at \(context.dashboardPath)"
            )
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: context.dashboardPath))
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
                message: "failed to decode \(context.dashboardPath)",
                context: ["error": "\(error)"]
            )
            return await mockResult(
                weekOffset: weekOffset,
                reason: "decode error at \(context.dashboardPath): \(error.localizedDescription)"
            )
        }
    }

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
