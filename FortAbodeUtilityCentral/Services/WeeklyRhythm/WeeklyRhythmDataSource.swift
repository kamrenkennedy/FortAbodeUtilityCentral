import Foundation
import SwiftUI

// MARK: - Protocol
//
// The seam between the Weekly Rhythm engine and the app's Weekly Rhythm view.
// Concrete impls (`MockWeeklyRhythmDataSource`, `FileBackedWeeklyRhythmDataSource`)
// own the actual data; the view consumes them through this protocol.
//
// Single-snapshot model: one call to `load(weekOffset:)` sets the snapshot for
// the requested week. Navigating between weeks calls `load` with a new offset.
// `weekOffset = 0` means "the week containing today."

@MainActor
public protocol WeeklyRhythmDataSource: AnyObject {
    /// Latest loaded snapshot. nil before the first load completes.
    var snapshot: WeeklyRhythmSnapshot? { get }

    /// Status of the most-recent load. UI can surface this on the Run Health pill
    /// so a "real" vs "mock" snapshot is visible without inspecting the data.
    var loadStatus: WeeklyRhythmLoadStatus { get }

    /// Trigger a load for the given week offset. `0` is the current week,
    /// negative values are past weeks, positive are future. Implementations
    /// should be idempotent — calling `load` twice with the same offset is OK.
    func load(weekOffset: Int) async

    /// Apply a user mutation. The store applies the mutation optimistically
    /// to the in-memory snapshot, then asks the impl to persist it to the
    /// appropriate destination (config.md / app UI state / sibling pending
    /// JSON file). On persist failure the snapshot is reloaded to rebase
    /// from authoritative state.
    @discardableResult
    func apply(_ mutation: WeeklyRhythmMutation) async -> Bool
}

// MARK: - Runtime store
//
// `@Observable` wrapper that owns whichever concrete impl is active. The
// indirection lets us swap impls at runtime (previews, tests) without changing
// view code. Views consume `WeeklyRhythmStore` directly via `@Environment`;
// the protocol exists so Mock and FileBacked can be referenced by the same type.

@MainActor
@Observable
public final class WeeklyRhythmStore {
    private let impl: any WeeklyRhythmDataSourceImpl
    public private(set) var snapshot: WeeklyRhythmSnapshot?
    public private(set) var loadStatus: WeeklyRhythmLoadStatus = .idle
    /// Last `weekOffset` passed to `load`. Mutations target this week's
    /// pending file. Defaults to 0 so mutations applied before any load
    /// (shouldn't happen in normal use) target the current week.
    public private(set) var currentWeekOffset: Int = 0

    public init(impl: any WeeklyRhythmDataSourceImpl) {
        self.impl = impl
    }

    public func load(weekOffset: Int) async {
        loadStatus = .loading
        currentWeekOffset = weekOffset
        let result = await impl.fetch(weekOffset: weekOffset)
        snapshot = result.snapshot
        loadStatus = result.status
    }

    /// Apply a user mutation: optimistic update on the in-memory snapshot,
    /// then persist via the impl. On persist failure, reload to rebase from
    /// authoritative state (which drops the optimistic change).
    @discardableResult
    public func apply(_ mutation: WeeklyRhythmMutation) async -> Bool {
        guard var snap = snapshot else { return false }
        MutationApplier.apply(mutation, to: &snap)
        snapshot = snap

        let ok = await impl.persist(mutation: mutation, weekOffset: currentWeekOffset)
        if !ok {
            await load(weekOffset: currentWeekOffset)
        }
        return ok
    }
}

// MARK: - Impl boundary
//
// Concrete data sources (Mock, FileBacked) speak this minimal contract: given
// a week offset, produce a snapshot + a status. Avoids forcing them to also
// be `@Observable` / `@MainActor` — the runtime `WeeklyRhythmStore` handles
// observable state. FileBacked can stay an actor for its file IO.

public protocol WeeklyRhythmDataSourceImpl: Sendable {
    func fetch(weekOffset: Int) async -> WeeklyRhythmFetchResult

    /// Persist a user mutation to the appropriate destination. Returns true
    /// on success. Mock impls return true unconditionally; real impls route
    /// each kind to its durable destination (config.md / app UI state JSON /
    /// sibling pending JSON file). Failures are logged via ErrorLogger.
    func persist(mutation: WeeklyRhythmMutation, weekOffset: Int) async -> Bool
}

public struct WeeklyRhythmFetchResult: Sendable {
    public let snapshot: WeeklyRhythmSnapshot
    public let status: WeeklyRhythmLoadStatus

    public init(snapshot: WeeklyRhythmSnapshot, status: WeeklyRhythmLoadStatus) {
        self.snapshot = snapshot
        self.status = status
    }
}

// MARK: - Environment injection
//
// Views consume the store via `@Environment(WeeklyRhythmStore.self)`. App-level
// code instantiates the store with the chosen impl and passes it through
// `.environment(store)`.
//
// We also expose a convenience method for the view to call once at the top of
// its body that pulls the @Bindable form if needed. Mostly views just read
// `store.snapshot` and `store.loadStatus`.
