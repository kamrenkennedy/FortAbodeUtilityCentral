import Foundation
import AlignedDesignSystem

// MARK: - Snapshot
//
// Top-level model that the Weekly Rhythm engine emits per generated dashboard
// and the app consumes via `WeeklyRhythmDataSource`. One snapshot covers one
// week-window of data; navigating to a different week loads a different
// snapshot. Codable so the engine can serialize to `dashboard-{ISODate}.json`
// alongside its existing `dashboard-{ISODate}.html` and the app can decode
// without engine cooperation.

public struct WeeklyRhythmSnapshot: Codable, Equatable, Sendable {
    public var weekMetadata: WeekMetadata
    public var todaysBrief: TodaysBrief?
    public var pulseProjects: [PulseProject]
    public var alerts: [WeeklyRhythmAlert]
    public var weekDays: [WeekDay]
    public var triage: [TriageEntry]
    public var proposals: [Proposal]
    public var errands: [Errand]
    public var dayBreakdown: [DayBreakdown]
    public var runHealth: RunHealth
    public var generatedAt: Date

    public init(
        weekMetadata: WeekMetadata,
        todaysBrief: TodaysBrief? = nil,
        pulseProjects: [PulseProject] = [],
        alerts: [WeeklyRhythmAlert] = [],
        weekDays: [WeekDay] = [],
        triage: [TriageEntry] = [],
        proposals: [Proposal] = [],
        errands: [Errand] = [],
        dayBreakdown: [DayBreakdown] = [],
        runHealth: RunHealth = .allGood,
        generatedAt: Date = Date()
    ) {
        self.weekMetadata = weekMetadata
        self.todaysBrief = todaysBrief
        self.pulseProjects = pulseProjects
        self.alerts = alerts
        self.weekDays = weekDays
        self.triage = triage
        self.proposals = proposals
        self.errands = errands
        self.dayBreakdown = dayBreakdown
        self.runHealth = runHealth
        self.generatedAt = generatedAt
    }
}

// MARK: - Week metadata

public struct WeekMetadata: Codable, Equatable, Sendable {
    public var eyebrow: String     // "Week 17"
    public var title: String       // "April 21 — 27"

    public init(eyebrow: String, title: String) {
        self.eyebrow = eyebrow
        self.title = title
    }
}

// MARK: - Today's brief

public struct TodaysBrief: Codable, Equatable, Sendable {
    public var dayType: WRDayType
    public var label: String       // "Today · Thursday April 24"
    public var narrative: String   // "Ship pass 3 of Braxton edit, then prep for…"
    public var weekGoalsComplete: Int
    public var weekGoalsTotal: Int

    public init(dayType: WRDayType, label: String, narrative: String, weekGoalsComplete: Int, weekGoalsTotal: Int) {
        self.dayType = dayType
        self.label = label
        self.narrative = narrative
        self.weekGoalsComplete = weekGoalsComplete
        self.weekGoalsTotal = weekGoalsTotal
    }
}

// MARK: - Day type

public enum WRDayType: String, Codable, CaseIterable, Hashable, Sendable {
    case make
    case move
    case recover
    case admin
    case open

    public var label: String {
        switch self {
        case .make:    return "Make"
        case .move:    return "Move"
        case .recover: return "Recover"
        case .admin:   return "Admin"
        case .open:    return "Open"
        }
    }
}

// MARK: - Project Pulse

public struct PulseProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var status: WRStatusKind
    public var statusLabel: String   // "In Review", "Draft", "Scheduled", "Idle", "Blocked"
    public var title: String         // "Braxton edit"
    public var touched: String       // "Touched 4h ago"
    public var action: String        // "Pass 3 → client today"

    public init(id: String, status: WRStatusKind, statusLabel: String, title: String, touched: String, action: String) {
        self.id = id
        self.status = status
        self.statusLabel = statusLabel
        self.title = title
        self.touched = touched
        self.action = action
    }
}

// MARK: - Status kind (Codable wrapper around AlignedDesignSystem.StatusKind)
//
// `StatusKind` in the design system is `Sendable` but not `Codable`. We carry
// our own enum for serialization and translate at the view boundary.

public enum WRStatusKind: String, Codable, Hashable, Sendable {
    case scheduled
    case draft
    case review
    case error
    case neutral

    public var styleKind: StatusKind {
        switch self {
        case .scheduled: return .scheduled
        case .draft:     return .draft
        case .review:    return .review
        case .error:     return .error
        case .neutral:   return .neutral
        }
    }
}

// MARK: - Alerts

public struct WeeklyRhythmAlert: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: WRAlertKind
    public var day: String           // "Saturday"
    public var title: String         // "Gallery drop-off — 12 PM downtown"
    public var detail: String        // "18 min drive each way…"
    public var actionLabel: String?  // "View itinerary" / nil if none

    public init(id: String, kind: WRAlertKind, day: String, title: String, detail: String, actionLabel: String? = nil) {
        self.id = id
        self.kind = kind
        self.day = day
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
    }
}

public enum WRAlertKind: String, Codable, Hashable, Sendable {
    case travel
    case commuteConflict
    case errandBatch
    case lunch

    public var label: String {
        switch self {
        case .travel:          return "Travel"
        case .commuteConflict: return "Commute conflict"
        case .errandBatch:     return "Errand batch"
        case .lunch:           return "Lunch"
        }
    }

    public var symbol: String {
        switch self {
        case .travel:          return "clock"
        case .commuteConflict: return "exclamationmark.triangle.fill"
        case .errandBatch:     return "cart.fill"
        case .lunch:           return "fork.knife"
        }
    }

    /// Urgent kinds get the brand-rust gradient + underglow.
    public var isUrgent: Bool {
        switch self {
        case .commuteConflict: return true
        default:               return false
        }
    }
}

// MARK: - Week grid

public struct WeekDay: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String                    // "Mon"
    public var num: String                     // "21"
    public var dayTypes: Set<WRDayType>
    public var isToday: Bool
    public var events: [WREvent]
    /// Hour-position of the "now" line within the day (e.g. 13.5 = 1:30 PM).
    /// Only set when `isToday` is true. Renderer translates into pixel offset
    /// via `hourScale`.
    public var nowLineHour: Double?

    public init(
        id: String,
        name: String,
        num: String,
        dayTypes: Set<WRDayType>,
        isToday: Bool,
        events: [WREvent] = [],
        nowLineHour: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.num = num
        self.dayTypes = dayTypes
        self.isToday = isToday
        self.events = events
        self.nowLineHour = nowLineHour
    }

    /// Stable ordering so toggling day-types doesn't reshuffle visually.
    public var sortedDayTypes: [WRDayType] {
        WRDayType.allCases.filter { dayTypes.contains($0) }
    }

    public var primaryDayType: WRDayType {
        sortedDayTypes.first ?? .open
    }
}

public struct WREvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startHour: Double               // 8.0–17.0 (8 AM = 8.0, 9:30 AM = 9.5)
    public var endHour: Double
    public var time: String?                   // "9 — 10:30 AM" — display hint, optional
    public var title: String
    public var kind: WREventKind

    public init(id: String, startHour: Double, endHour: Double, time: String? = nil, title: String, kind: WREventKind) {
        self.id = id
        self.startHour = startHour
        self.endHour = endHour
        self.time = time
        self.title = title
        self.kind = kind
    }
}

public enum WREventKind: String, Codable, Hashable, Sendable {
    case regular
    case accent
    case errand
}

// MARK: - Triage

public struct TriageEntry: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var status: WRStatusKind
    public var title: String        // "Re: Downtown Gallery — proof timing?"
    public var meta: String         // "Marisol · client · 2h ago"

    public init(id: String, status: WRStatusKind, title: String, meta: String) {
        self.id = id
        self.status = status
        self.title = title
        self.meta = meta
    }
}

// MARK: - Proposals

public struct Proposal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var reasoning: String

    public init(id: String, title: String, reasoning: String) {
        self.id = id
        self.title = title
        self.reasoning = reasoning
    }
}

public enum ProposalResolution: String, Codable, Sendable {
    case accepted
    case declined
}

// MARK: - Errands

public struct Errand: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var location: String?
    public var daysPending: Int
    public var routedTo: String?
    public var isDone: Bool

    public init(id: String, title: String, location: String? = nil, daysPending: Int, routedTo: String? = nil, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.location = location
        self.daysPending = daysPending
        self.routedTo = routedTo
        self.isDone = isDone
    }
}

// MARK: - Day Breakdown

public struct DayBreakdown: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var weekday: String        // "Mon"
    public var dateLabel: String      // "Apr 21"
    public var dayType: WRDayType
    public var headline: String?      // "Clear the runway"
    public var summary: String?       // "2h · 1 err"
    public var blocks: [DayBlock]
    public var isToday: Bool
    public var isPast: Bool

    public init(
        id: String,
        weekday: String,
        dateLabel: String,
        dayType: WRDayType,
        headline: String? = nil,
        summary: String? = nil,
        blocks: [DayBlock] = [],
        isToday: Bool = false,
        isPast: Bool = false
    ) {
        self.id = id
        self.weekday = weekday
        self.dateLabel = dateLabel
        self.dayType = dayType
        self.headline = headline
        self.summary = summary
        self.blocks = blocks
        self.isToday = isToday
        self.isPast = isPast
    }

    public var hasBar: Bool {
        blocks.contains { $0.startHour != nil && $0.endHour != nil }
    }
}

public struct DayBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var kind: DayBlockKind
    public var startHour: Double?
    public var endHour: Double?
    public var durationLabel: String?
    public var timeLabel: String?
    public var tag: DayBlockTag?
    public var dim: Bool

    public init(
        id: String,
        title: String,
        kind: DayBlockKind,
        startHour: Double? = nil,
        endHour: Double? = nil,
        durationLabel: String? = nil,
        timeLabel: String? = nil,
        tag: DayBlockTag? = nil,
        dim: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.startHour = startHour
        self.endHour = endHour
        self.durationLabel = durationLabel
        self.timeLabel = timeLabel
        self.tag = tag
        self.dim = dim
    }
}

public enum DayBlockKind: String, Codable, Hashable, Sendable {
    case focus
    case errand
    case sync
    case admin
    case recover
    case note
}

public enum DayBlockTag: String, Codable, Hashable, Sendable {
    case admin
    case make
    case move
    case errand
    case sync

    public var label: String {
        switch self {
        case .admin:  return "Admin"
        case .make:   return "Make"
        case .move:   return "Move"
        case .errand: return "Errand"
        case .sync:   return "Sync"
        }
    }
}

// MARK: - Run health

public enum RunHealth: Codable, Equatable, Sendable {
    case allGood
    case warning(String)
    case error(String)
}

// MARK: - Load status (for the data source)

public enum WeeklyRhythmLoadStatus: Equatable, Sendable {
    case idle
    case loading
    /// Snapshot came from a real engine-emitted JSON file at the given timestamp.
    case real(generatedAt: Date)
    /// Snapshot came from the mock fallback because the real source was unavailable.
    /// The string is a short reason ("file not found at <path>", "decode error: ...").
    case mockFallback(reason: String)
    /// Both the real and the mock paths failed catastrophically — should never happen
    /// since mocks are static, but reserved for future write-back errors.
    case error(String)
}

// MARK: - Mutations (Phase 5b — write-back)
//
// `WeeklyRhythmMutation` describes a user action that needs to persist
// somewhere durable. The data source's `apply(_:)` decides which destination
// each kind lands in: day-type → config.md; errand reorder → app-local UI
// state; everything else → sibling `dashboard-{date}-pending.json` that the
// engine consumes on its next run.
//
// Custom Codable produces a flat `{"kind": "...", ...payload}` JSON shape
// that's readable from the engine side without Swift-specific knowledge of
// enum-with-associated-values.

public enum WeeklyRhythmMutation: Equatable, Sendable {
    case errandDoneToggle(errandID: String, isDone: Bool)
    case eventMove(eventID: String, newDayIndex: Int, newStartHour: Double, newEndHour: Double)
    case proposalAccept(proposalID: String)
    case proposalDecline(proposalID: String)
    case dayTypeChange(weekdayName: String, newType: WRDayType)  // "Sunday" … "Saturday"
    case errandReorder(orderedIDs: [String])
}

extension WeeklyRhythmMutation: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case errandID, isDone
        case eventID, newDayIndex, newStartHour, newEndHour
        case proposalID
        case weekdayName, newType
        case orderedIDs
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .errandDoneToggle(let errandID, let isDone):
            try c.encode("errandDoneToggle", forKey: .kind)
            try c.encode(errandID, forKey: .errandID)
            try c.encode(isDone, forKey: .isDone)
        case .eventMove(let eventID, let newDayIndex, let newStartHour, let newEndHour):
            try c.encode("eventMove", forKey: .kind)
            try c.encode(eventID, forKey: .eventID)
            try c.encode(newDayIndex, forKey: .newDayIndex)
            try c.encode(newStartHour, forKey: .newStartHour)
            try c.encode(newEndHour, forKey: .newEndHour)
        case .proposalAccept(let proposalID):
            try c.encode("proposalAccept", forKey: .kind)
            try c.encode(proposalID, forKey: .proposalID)
        case .proposalDecline(let proposalID):
            try c.encode("proposalDecline", forKey: .kind)
            try c.encode(proposalID, forKey: .proposalID)
        case .dayTypeChange(let weekdayName, let newType):
            try c.encode("dayTypeChange", forKey: .kind)
            try c.encode(weekdayName, forKey: .weekdayName)
            try c.encode(newType, forKey: .newType)
        case .errandReorder(let orderedIDs):
            try c.encode("errandReorder", forKey: .kind)
            try c.encode(orderedIDs, forKey: .orderedIDs)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "errandDoneToggle":
            self = .errandDoneToggle(
                errandID: try c.decode(String.self, forKey: .errandID),
                isDone: try c.decode(Bool.self, forKey: .isDone)
            )
        case "eventMove":
            self = .eventMove(
                eventID: try c.decode(String.self, forKey: .eventID),
                newDayIndex: try c.decode(Int.self, forKey: .newDayIndex),
                newStartHour: try c.decode(Double.self, forKey: .newStartHour),
                newEndHour: try c.decode(Double.self, forKey: .newEndHour)
            )
        case "proposalAccept":
            self = .proposalAccept(proposalID: try c.decode(String.self, forKey: .proposalID))
        case "proposalDecline":
            self = .proposalDecline(proposalID: try c.decode(String.self, forKey: .proposalID))
        case "dayTypeChange":
            self = .dayTypeChange(
                weekdayName: try c.decode(String.self, forKey: .weekdayName),
                newType: try c.decode(WRDayType.self, forKey: .newType)
            )
        case "errandReorder":
            self = .errandReorder(orderedIDs: try c.decode([String].self, forKey: .orderedIDs))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "unknown WeeklyRhythmMutation kind: \(kind)"
            )
        }
    }
}

// MARK: - Pending mutations file
//
// The wire format the app writes to
// `{user}/dashboards/dashboard-{ISODate}-pending.json` and the engine reads on
// its next run. `weekISODate` is the Monday of the target week — matches the
// sibling `dashboard-{ISODate}.json` so the engine knows which week's state
// the pending mutations apply to.

public struct PendingMutationsBundle: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var weekISODate: String
    public var createdAt: Date
    public var mutations: [PendingMutationEntry]

    public init(
        schemaVersion: Int = 1,
        weekISODate: String,
        createdAt: Date = Date(),
        mutations: [PendingMutationEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.weekISODate = weekISODate
        self.createdAt = createdAt
        self.mutations = mutations
    }
}

public struct PendingMutationEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var appliedAt: Date
    public var mutation: WeeklyRhythmMutation

    public init(
        id: String = UUID().uuidString,
        appliedAt: Date = Date(),
        mutation: WeeklyRhythmMutation
    ) {
        self.id = id
        self.appliedAt = appliedAt
        self.mutation = mutation
    }
}

// MARK: - Mutation applier
//
// Pure functions that apply a mutation to an in-memory snapshot. Used in two
// places: (1) optimistic update in `WeeklyRhythmStore.apply(_:)`, and
// (2) replay-on-load in `FileBackedWeeklyRhythmDataSource.fetch(weekOffset:)`
// where pending mutations get layered on top of the engine's last output so
// the user's intent survives across app restarts and engine runs that haven't
// yet drained the pending file.
//
// All functions are pure (no I/O) and `Sendable` so they're safe to call from
// the data-source actor or from `@MainActor` view code.

public enum MutationApplier {
    public static func apply(_ mutation: WeeklyRhythmMutation, to snap: inout WeeklyRhythmSnapshot) {
        switch mutation {
        case .errandDoneToggle(let errandID, let isDone):
            if let i = snap.errands.firstIndex(where: { $0.id == errandID }) {
                snap.errands[i].isDone = isDone
            }

        case .eventMove(let eventID, let newDayIndex, let newStartHour, let newEndHour):
            for d in 0..<snap.weekDays.count {
                if let e = snap.weekDays[d].events.firstIndex(where: { $0.id == eventID }) {
                    var event = snap.weekDays[d].events[e]
                    event.startHour = newStartHour
                    event.endHour = newEndHour
                    snap.weekDays[d].events.remove(at: e)
                    if newDayIndex >= 0 && newDayIndex < snap.weekDays.count {
                        snap.weekDays[newDayIndex].events.append(event)
                    }
                    return
                }
            }

        case .proposalAccept(let proposalID), .proposalDecline(let proposalID):
            snap.proposals.removeAll { $0.id == proposalID }

        case .dayTypeChange(let weekdayName, let newType):
            // Match by short name ("Mon", "Tue", …) since the snapshot's
            // WeekDay only carries that. Caller passes the full name
            // ("Monday") so we compare prefix-insensitively.
            let target = String(weekdayName.prefix(3)).lowercased()
            for i in 0..<snap.weekDays.count {
                if snap.weekDays[i].name.lowercased().hasPrefix(target) {
                    snap.weekDays[i].dayTypes = [newType]
                    return
                }
            }

        case .errandReorder(let orderedIDs):
            // Reorder by orderedIDs; errands not present go to the end in
            // their original relative order. Stable for partial reorderings.
            let byID = Dictionary(uniqueKeysWithValues: snap.errands.map { ($0.id, $0) })
            var reordered: [Errand] = []
            var seen = Set<String>()
            for id in orderedIDs {
                if let e = byID[id] {
                    reordered.append(e)
                    seen.insert(id)
                }
            }
            for e in snap.errands where !seen.contains(e.id) {
                reordered.append(e)
            }
            snap.errands = reordered
        }
    }

    public static func applyAll(_ mutations: [WeeklyRhythmMutation], to snap: inout WeeklyRhythmSnapshot) {
        for m in mutations {
            apply(m, to: &snap)
        }
    }
}
