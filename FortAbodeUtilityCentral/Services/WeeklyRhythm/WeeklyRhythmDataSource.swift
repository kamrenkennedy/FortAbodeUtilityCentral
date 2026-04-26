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

    public init(impl: any WeeklyRhythmDataSourceImpl) {
        self.impl = impl
    }

    public func load(weekOffset: Int) async {
        loadStatus = .loading
        let result = await impl.fetch(weekOffset: weekOffset)
        snapshot = result.snapshot
        loadStatus = result.status
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
