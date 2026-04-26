import Foundation

// Static mock implementation of `WeeklyRhythmDataSource`. Data comes verbatim
// from the prior `@State` arrays + `makeMocked…()` factories that lived inside
// `WeeklyRhythmView` until the Phase 5 wire-up. The visual output is intended
// to be identical pre/post-extraction.
//
// Used as:
//   • Default impl when the engine hasn't emitted JSON yet
//   • Fallback delegate from `FileBackedWeeklyRhythmDataSource` on miss/decode-fail
//   • Test/preview source

public struct MockWeeklyRhythmDataSource: WeeklyRhythmDataSourceImpl {

    public init() {}

    public func fetch(weekOffset: Int) async -> WeeklyRhythmFetchResult {
        let snapshot = Self.snapshot(weekOffset: weekOffset)
        return WeeklyRhythmFetchResult(
            snapshot: snapshot,
            status: .mockFallback(reason: "mock data source — no engine wire yet")
        )
    }

    /// Mocks have no durable destination. Persist always succeeds; the
    /// optimistic update on the in-memory snapshot is the only effect.
    public func persist(mutation: WeeklyRhythmMutation, weekOffset: Int) async -> Bool {
        true
    }

    /// Public so `FileBackedWeeklyRhythmDataSource` can fall back to the same
    /// snapshot when its file decode fails.
    public static func snapshot(weekOffset: Int) -> WeeklyRhythmSnapshot {
        // For weekOffset != 0 we render a sparser snapshot so navigation feels
        // alive — same project pulse + run health, but no events and a weak
        // brief. When the engine wires up, this synthetic-empty path goes away.
        if weekOffset != 0 {
            return WeeklyRhythmSnapshot(
                weekMetadata: weekMetadataFor(offset: weekOffset),
                todaysBrief: nil,
                pulseProjects: pulseProjects,
                alerts: [],
                weekDays: emptyWeekDays(),
                triage: [],
                proposals: [],
                errands: [],
                dayBreakdown: [],
                runHealth: .allGood
            )
        }

        return WeeklyRhythmSnapshot(
            weekMetadata: WeekMetadata(eyebrow: "Week 17", title: "April 21 — 27"),
            todaysBrief: TodaysBrief(
                dayType: .move,
                label: "Today · Thursday April 24",
                narrative: "Ship pass 3 of Braxton edit, then prep for Tiera's birthday window.",
                weekGoalsComplete: 3,
                weekGoalsTotal: 5
            ),
            pulseProjects: pulseProjects,
            alerts: alerts,
            weekDays: weekDays,
            triage: triage,
            proposals: proposals,
            errands: errands,
            dayBreakdown: dayBreakdown,
            runHealth: .allGood
        )
    }

    // MARK: - Week metadata for non-current offsets

    private static func weekMetadataFor(offset: Int) -> WeekMetadata {
        switch offset {
        case 1:  return WeekMetadata(eyebrow: "Week 18", title: "April 28 — May 4")
        case -1: return WeekMetadata(eyebrow: "Week 16", title: "April 14 — 20")
        case let n where n > 0:
            return WeekMetadata(eyebrow: "+\(n) weeks", title: "Future week")
        default:
            return WeekMetadata(eyebrow: "\(offset) weeks", title: "Past week")
        }
    }

    private static func emptyWeekDays() -> [WeekDay] {
        let names = [("Mon", "28"), ("Tue", "29"), ("Wed", "30"), ("Thu", "1"), ("Fri", "2"), ("Sat", "3"), ("Sun", "4")]
        return names.map { name, num in
            WeekDay(
                id: "wd-\(name)-\(num)",
                name: name,
                num: num,
                dayTypes: [.open],
                isToday: false,
                events: []
            )
        }
    }

    // MARK: - Pulse projects

    private static let pulseProjects: [PulseProject] = [
        PulseProject(id: "proj-braxton",  status: .review,    statusLabel: "In review",  title: "Braxton edit",                touched: "Touched 4h ago",     action: "Pass 3 → client today"),
        PulseProject(id: "proj-gallery",  status: .draft,     statusLabel: "Draft",      title: "Downtown Gallery delivery",   touched: "Touched yesterday",  action: "Sat 12pm drop-off"),
        PulseProject(id: "proj-rae",      status: .scheduled, statusLabel: "Scheduled",  title: "Rae reels",                   touched: "Touched 2 days ago", action: "Review Sat 3pm"),
        PulseProject(id: "proj-aligned",  status: .neutral,   statusLabel: "Idle",       title: "Aligned suite landing",       touched: "Touched 6 days ago", action: "Waiting on Tiera copy"),
        PulseProject(id: "proj-studio",   status: .error,     statusLabel: "Blocked",    title: "Studio site rebuild",         touched: "Touched 9 days ago", action: "Domain DNS issue"),
        PulseProject(id: "proj-may",      status: .scheduled, statusLabel: "Scheduled",  title: "May newsletter",              touched: "Touched today",      action: "Outline due Mon")
    ]

    // MARK: - Alerts

    private static let alerts: [WeeklyRhythmAlert] = [
        WeeklyRhythmAlert(
            id: "alert-saturday-travel",
            kind: .travel,
            day: "Saturday",
            title: "Gallery drop-off — 12 PM downtown",
            detail: "18 min drive each way. Plan a 30 min buffer for parking + load-in.",
            actionLabel: "View itinerary"
        ),
        WeeklyRhythmAlert(
            id: "alert-friday-commute",
            kind: .commuteConflict,
            day: "Friday",
            title: "Tight commute window before Braxton sync",
            detail: "Studio-site DNS work runs to noon, but the dry cleaner closes at 12:30 — fits with a buffer or push to Saturday.",
            actionLabel: "Reschedule"
        )
    ]

    // MARK: - Week grid (events keyed by day)
    //
    // Original mock used 64pt-baseline pixel positions; converted to hour-relative
    // here. 8 AM = 8.0, 9 AM = 9.0, etc. (renderer multiplies by hourScale at
    // render time.)

    private static let weekDays: [WeekDay] = [
        WeekDay(id: "wd-mon", name: "Mon", num: "21", dayTypes: [.admin], isToday: false, events: [
            WREvent(id: "ev-mon-inbox",    startHour: 9.0,  endHour: 10.5, time: "9 — 10:30 AM", title: "Inbox triage",     kind: .regular),
            WREvent(id: "ev-mon-postoffice", startHour: 12.0, endHour: 12.5, time: nil,           title: "Errand: post office", kind: .errand),
            WREvent(id: "ev-mon-ops",      startHour: 14.0, endHour: 15.0, time: "2 — 3 PM",     title: "Ops review",       kind: .accent)
        ]),
        WeekDay(id: "wd-tue", name: "Tue", num: "22", dayTypes: [.make], isToday: false, events: [
            WREvent(id: "ev-tue-braxton2", startHour: 10.0, endHour: 13.0, time: "10 AM — 1 PM", title: "Braxton edit · pass 2", kind: .regular),
            WREvent(id: "ev-tue-sync",     startHour: 15.0, endHour: 16.0, time: "3 — 4 PM",     title: "Braxton sync",          kind: .accent)
        ]),
        WeekDay(id: "wd-wed", name: "Wed", num: "23", dayTypes: [.make], isToday: false, events: [
            WREvent(id: "ev-wed-rae",      startHour: 9.5,  endHour: 13.0, time: "9:30 AM — 1 PM", title: "Rae reels · cuts", kind: .regular),
            WREvent(id: "ev-wed-lab",      startHour: 13.0, endHour: 13.5, time: nil,             title: "Errand: lab pickup", kind: .errand)
        ]),
        WeekDay(id: "wd-thu", name: "Thu · today", num: "24", dayTypes: [.move, .recover], isToday: true, events: [
            WREvent(id: "ev-thu-braxton3", startHour: 10.0, endHour: 12.0, time: "10 AM — 12 PM", title: "Braxton edit · pass 3", kind: .regular),
            WREvent(id: "ev-thu-sync",     startHour: 15.0, endHour: 16.0, time: "3 — 4 PM",      title: "Braxton sync",          kind: .accent)
        ], nowLineHour: 13.5),
        WeekDay(id: "wd-fri", name: "Fri", num: "25", dayTypes: [.make], isToday: false, events: [
            WREvent(id: "ev-fri-dns",      startHour: 9.0,  endHour: 12.0, time: "9 AM — 12 PM", title: "Studio site · DNS fix", kind: .regular),
            WREvent(id: "ev-fri-cleaner",  startHour: 12.5, endHour: 13.0, time: nil,            title: "Errand: dry cleaner",   kind: .errand),
            WREvent(id: "ev-fri-sync",     startHour: 15.0, endHour: 16.0, time: "3 — 4 PM",     title: "Braxton sync (moved)",  kind: .accent)
        ]),
        WeekDay(id: "wd-sat", name: "Sat", num: "26", dayTypes: [.recover], isToday: false, events: [
            WREvent(id: "ev-sat-run",      startHour: 8.5,  endHour: 10.0, time: "8:30 — 10 AM", title: "Long run · with Tiera", kind: .regular),
            WREvent(id: "ev-sat-gallery",  startHour: 12.0, endHour: 12.5, time: "12 PM",        title: "Gallery drop-off",      kind: .accent),
            WREvent(id: "ev-sat-rae",      startHour: 15.0, endHour: 16.0, time: "3 — 4 PM",     title: "Rae reels · review",    kind: .regular)
        ]),
        WeekDay(id: "wd-sun", name: "Sun", num: "27", dayTypes: [.open], isToday: false, events: [])
    ]

    // MARK: - Triage

    private static let triage: [TriageEntry] = [
        TriageEntry(id: "tri-marisol", status: .error, title: "Re: Downtown Gallery — proof timing?",  meta: "Marisol · client · 2h ago"),
        TriageEntry(id: "tri-cf",      status: .draft, title: "Studio site DNS — propagation report", meta: "Cloudflare · 6h ago"),
        TriageEntry(id: "tri-tiera",   status: .draft, title: "Tiera shared a Memory edit — review?", meta: "Family Memory · yesterday")
    ]

    // MARK: - Proposals

    private static let proposals: [Proposal] = [
        Proposal(id: "prop-move-sync",  title: "Move Braxton sync from Tue to Fri",       reasoning: "You asked earlier today. Same call link, same duration."),
        Proposal(id: "prop-prep-block", title: "Add 1h prep block Friday morning",        reasoning: "Before the moved Braxton sync — based on past pattern."),
        Proposal(id: "prop-snooze-dns", title: "Snooze \"Studio site DNS\" until Mon",  reasoning: "Cloudflare propagation reports settle within 24h.")
    ]

    // MARK: - Errands

    private static let errands: [Errand] = [
        Errand(id: "err-amazon",   title: "Return Amazon package",      location: "Downtown · 12 min",   daysPending: 2,  routedTo: "Mon · post office"),
        Errand(id: "err-film",     title: "Pick up film samples",       location: "Lab · 18 min",        daysPending: 5,  routedTo: "Wed · lab pickup"),
        Errand(id: "err-cleaner",  title: "Drop off gear for cleaning", location: "Dry cleaner · 8 min", daysPending: 9,  routedTo: "Fri · dry cleaner"),
        Errand(id: "err-dmv",      title: "New driver's license photo", location: "DMV · 22 min",        daysPending: 17, routedTo: nil),
        Errand(id: "err-gift",     title: "Order Tiera's gift",         location: nil,                   daysPending: 4,  routedTo: nil)
    ]

    // MARK: - Day Breakdown

    private static let dayBreakdown: [DayBreakdown] = [
        DayBreakdown(
            id: "db-mon",
            weekday: "Mon", dateLabel: "Apr 21", dayType: .admin,
            headline: "Clear the runway",
            summary: "2h · 1 err",
            blocks: [
                DayBlock(id: "blk-mon-inbox",   title: "Inbox triage",           kind: .admin,                                  durationLabel: "45m",  tag: .admin),
                DayBlock(id: "blk-mon-q1",      title: "File Q1 expenses",       kind: .admin,                                  durationLabel: "30m",  tag: .admin),
                DayBlock(id: "blk-mon-prep",    title: "Prep Tue's edit block",  kind: .focus,  startHour: 14.5, endHour: 15.5, durationLabel: "1h",   tag: .make),
                DayBlock(id: "blk-mon-postoff", title: "Post office return",     kind: .errand, startHour: 16.0, endHour: 16.5, durationLabel: "15m",  tag: .errand)
            ],
            isToday: false, isPast: true
        ),
        DayBreakdown(
            id: "db-tue",
            weekday: "Tue", dateLabel: "Apr 22", dayType: .make,
            headline: "Deep block + client sync",
            summary: "3h · 1 sync",
            blocks: [
                DayBlock(id: "blk-tue-edit",    title: "Braxton edit pass 2", kind: .focus, startHour: 10.0, endHour: 13.0, durationLabel: "10–1 · 3h", tag: .make),
                DayBlock(id: "blk-tue-sync",    title: "Client sync",         kind: .sync,  startHour: 15.0, endHour: 16.0, timeLabel: "3:00 PM",       tag: .sync),
                DayBlock(id: "blk-tue-noerrs",  title: "No errands routed",   kind: .note,                                                               dim: true)
            ],
            isToday: false, isPast: true
        ),
        DayBreakdown(
            id: "db-wed",
            weekday: "Wed", dateLabel: "Apr 23", dayType: .make,
            headline: "Rae reels — cuts",
            summary: "3.5h · 1 err",
            blocks: [
                DayBlock(id: "blk-wed-rae", title: "Rae reels — cuts", kind: .focus,  startHour: 9.5,  endHour: 13.0, durationLabel: "9:30–1 · 3.5h", tag: .make),
                DayBlock(id: "blk-wed-lab", title: "Lab pickup",       kind: .errand, startHour: 14.0, endHour: 14.5, durationLabel: "mid-PM",        tag: .errand)
            ],
            isToday: false, isPast: true
        ),
        DayBreakdown(
            id: "db-thu",
            weekday: "Thu", dateLabel: "Apr 24", dayType: .move,
            headline: "Ship day",
            summary: "2h · 1 sync",
            blocks: [
                DayBlock(id: "blk-thu-ship", title: "Ship Braxton pass 3", kind: .focus, startHour: 10.0, endHour: 12.0, durationLabel: "10–12 · 2h", tag: .move),
                DayBlock(id: "blk-thu-sync", title: "Client sync",         kind: .sync,  startHour: 15.0, endHour: 16.0, timeLabel: "3:00 PM",       tag: .sync)
            ],
            isToday: true, isPast: false
        ),
        DayBreakdown(
            id: "db-fri",
            weekday: "Fri", dateLabel: "Apr 25", dayType: .make,
            headline: "Studio site DNS fix",
            summary: "3h · sync · err",
            blocks: [
                DayBlock(id: "blk-fri-dns",      title: "Studio site DNS fix",          kind: .focus,  startHour: 9.0,  endHour: 12.0, durationLabel: "3h", tag: .make),
                DayBlock(id: "blk-fri-cleaner",  title: "Dry cleaner",                  kind: .errand, startHour: 16.5, endHour: 17.0, tag: .errand),
                DayBlock(id: "blk-fri-sync",     title: "Braxton sync (moved from Tue)", kind: .sync, startHour: 13.5, endHour: 14.5, tag: .sync)
            ],
            isToday: false, isPast: false
        ),
        DayBreakdown(
            id: "db-sat",
            weekday: "Sat", dateLabel: "Apr 26", dayType: .recover,
            headline: "Long run + gallery drop-off",
            summary: "light · 1 err",
            blocks: [
                DayBlock(id: "blk-sat-run",     title: "Long run with Tiera",      kind: .recover, startHour: 7.0,  endHour: 10.0, timeLabel: "AM"),
                DayBlock(id: "blk-sat-gallery", title: "Gallery drop-off",          kind: .errand,  startHour: 11.5, endHour: 12.0, timeLabel: "12:00 PM", tag: .errand),
                DayBlock(id: "blk-sat-rae",     title: "Light review of Rae cuts", kind: .recover, startHour: 15.0, endHour: 17.0, timeLabel: "PM",       dim: true)
            ],
            isToday: false, isPast: false
        ),
        DayBreakdown(
            id: "db-sun",
            weekday: "Sun", dateLabel: "Apr 27", dayType: .open,
            headline: "No scheduled blocks",
            summary: "—",
            blocks: [],
            isToday: false, isPast: false
        )
    ]
}
