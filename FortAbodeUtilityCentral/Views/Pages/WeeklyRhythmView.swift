import SwiftUI
import AlignedDesignSystem

// Weekly Rhythm — bento dashboard. Project Pulse strip → Week Grid (7 days,
// absolute-positioned event blocks) → Triage + Claude Proposals two-column →
// sticky Confirm Bar (visible when at least one proposal is checked).
//
// Mocked data for v4.0.0; live wiring against the engine output (existing
// dashboard-template.html structure / WeeklyRhythmService) is a Phase 5
// concern.

enum WeeklyRhythmRange: Hashable {
    case week
    case thirtyDay
}

// Phase 5 wire-up: types lifted to `Models/WeeklyRhythm.swift` and stamped on
// engine output via `WeeklyRhythmDataSource`. Some type names diverged from
// the prior in-file privates so the public Models layer reads cleanly across
// all consumers; these typealiases keep the existing view body code working
// unchanged where the rename was purely cosmetic.
private typealias DayType = WRDayType
private typealias AlertKind = WRAlertKind
private typealias EventKind = WREventKind
private typealias Event = WREvent

// View-only extensions on the Codable Models types — colors and behavior flags
// that don't belong in the data model but the renderer needs. Living here keeps
// `Models/WeeklyRhythm.swift` SwiftUI-free and Codable-clean.

private extension WRDayType {
    var tint: Color {
        switch self {
        case .make:    return Color.statusScheduled
        case .move:    return Color.tertiary
        case .recover: return Color.brandRust
        case .admin:   return Color.statusDraft
        case .open:    return Color.statusNeutral
        }
    }

    /// engine-spec.md §Day Types: an exclusive type (e.g. Off) replaces all
    /// others — the dropdown hides its plus cell. None of the redesign HTML's
    /// 5 mock types are exclusive; v4.1 wiring may surface real exclusives.
    var isExclusive: Bool { false }
}

private extension WRAlertKind {
    var tint: Color {
        switch self {
        case .travel:          return Color.onSurfaceVariant
        case .commuteConflict: return Color.brandRustSoft
        case .errandBatch:     return Color.statusDraft
        case .lunch:           return Color.statusScheduled
        }
    }
}

struct WeeklyRhythmView: View {
    @Environment(WeeklyRhythmStore.self) private var store

    // Transient UI state — view-only, NOT engine-emitted. Stays @State.
    @State private var weekOffset: Int = 0
    @State private var range: WeeklyRhythmRange = .week
    @State private var selectedProjectId: String?
    @State private var detailProject: PulseProject?
    @State private var dayTypeSettingsOpen: Bool = false
    @State private var editingErrandID: String?
    @State private var detailTriage: TriageEntry?
    @State private var detailProposal: Proposal?
    @State private var alertsExpanded: Bool = true
    /// Local-only RSVP selection per triage entry. Resets on snapshot reload
    /// since the engine drains the pending file and re-emits authoritative
    /// state (where invites have either been resolved or remain pending).
    @State private var rsvpSelections: [String: RsvpResponse] = [:]
    /// ID of the event currently open in the EditEventSheet, or nil when
    /// no edit is in flight. The sheet looks up the event by ID rather than
    /// holding a value copy so optimistic snapshot updates flow through.
    @State private var editingEventID: String?

    // Vertical zoom — controls hour-row height. Default 52pt is the desktop
    // spec value (UPDATE-2026-04-26-desktop-mac.md week-grid table). Dragged
    // via the WeekGridZoomSlider in weekNavRow within [40, 80] bounds. Event
    // positions are stored in 64pt-baseline units in mocks and scaled by
    // `hourScale` at render time (`hourHeight / 64`). When the engine wires
    // up real events in v4.1, switch the model to hour-relative units.
    @State private var hourHeight: CGFloat = 52

    // MARK: - Snapshot reads
    //
    // The view consumes per-section arrays through these computed accessors so
    // the existing render code (e.g. `alerts.indices`, `pulseProjects.count`)
    // works unchanged after the data-source rewire. nil snapshot → empty array
    // → existing empty-state branches render naturally.

    private var snapshot: WeeklyRhythmSnapshot? { store.snapshot }
    private var weekMetadata: WeekMetadata { snapshot?.weekMetadata ?? WeekMetadata(eyebrow: "", title: "—") }
    private var todaysBrief: TodaysBrief? { snapshot?.todaysBrief }
    private var pulseProjects: [PulseProject] { snapshot?.pulseProjects ?? [] }
    private var alerts: [WeeklyRhythmAlert] { snapshot?.alerts ?? [] }
    private var weekDays: [WeekDay] { snapshot?.weekDays ?? [] }
    private var triageItems: [TriageEntry] { snapshot?.triage ?? [] }
    private var proposals: [Proposal] { snapshot?.proposals ?? [] }
    private var errands: [Errand] { snapshot?.errands ?? [] }
    private var dayBreakdownEntries: [DayBreakdown] { snapshot?.dayBreakdown ?? [] }
    private var runHealth: RunHealth { snapshot?.runHealth ?? .allGood }

    private var hourScale: CGFloat { hourHeight / 64 }
    private var dayColumnHeight: CGFloat { hourHeight * CGFloat(hourCount) }
    // 6 AM → 9 PM = 16 hourly grid rows. Same axis the day-breakdown focus bar
    // uses, so events that fall outside 8–4 PM ("dinner with Tiera at 7", "Long
    // run at 6 AM") show up on the calendar instead of getting clipped.
    private let hourCount: Int = 16
    private let visibleStartHour: Double = 6.0   // top of the rendered grid
    /// Default-visible hours (rendered card height = `defaultVisibleHours * 64`
    /// at default zoom). The card stays this tall regardless of zoom; the user
    /// scrolls to see hours outside the window. Apple Calendar / Google Calendar /
    /// Notion Calendar all use this pattern — fixed card, scrollable contents.
    private let defaultVisibleHours: CGFloat = 10
    private var visibleWindowHeight: CGFloat { defaultVisibleHours * 64 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: weekMetadata.eyebrow, title: weekMetadata.title)
                    .overlay(alignment: .topTrailing) {
                        RunHealthPill(state: runHealthDisplayState)
                            .padding(.top, Space.s10)
                            .padding(.trailing, Space.s10)
                    }

                VStack(alignment: .leading, spacing: Space.s8) {
                    if !alerts.isEmpty {
                        alertsBannerSection
                    }
                    todaysBriefSection
                    projectPulseSection
                    weekGridSection
                    triageAndProposalsSection
                    errandsSection
                    dayBreakdownSection
                }
                .padding(.horizontal, Space.s10)
                .padding(.bottom, Space.s16)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(item: $detailProject) { project in
            ProjectDetailSheet(project: project)
                .frame(minWidth: 520, idealWidth: 640, minHeight: 480, idealHeight: 600)
        }
        .sheet(isPresented: $dayTypeSettingsOpen) {
            DayTypeSettingsSheet(
                weekDays: weekDays,
                onChange: { fullName, newType in
                    Task {
                        await store.apply(.dayTypeChange(weekdayName: fullName, newType: newType))
                    }
                }
            )
            .frame(minWidth: 520, idealWidth: 640, minHeight: 480, idealHeight: 600)
        }
        .sheet(isPresented: errandEditSheetBinding) {
            if let id = editingErrandID, let errand = errands.first(where: { $0.id == id }) {
                ErrandDetailSheet(
                    initialErrand: errand,
                    onSave: { patch in
                        Task { await store.apply(.errandEdit(errandID: errand.id, patch: patch)) }
                    },
                    onMarkDone: {
                        Task { await store.apply(.errandDoneToggle(errandID: errand.id, isDone: true)) }
                    },
                    onDismiss: { editingErrandID = nil }
                )
                .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 560)
            }
        }
        .task(id: weekOffset) {
            await store.load(weekOffset: weekOffset)
        }
        .sheet(item: $detailTriage) { entry in
            EditTriageSheet(
                entry: entry,
                reasoning: triageReasoning(for: entry),
                onSave: { patch in
                    Task { await store.apply(.triageEdit(triageID: entry.id, patch: patch)) }
                },
                onDismiss: { detailTriage = nil }
            )
            .frame(minWidth: 720, idealWidth: 760, minHeight: 460, idealHeight: 560)
        }
        .sheet(isPresented: editEventSheetBinding) {
            if let id = editingEventID, let event = findEvent(byID: id) {
                EditEventSheet(
                    event: event,
                    reasoning: eventReasoning(for: event),
                    onSave: { patch in
                        Task { await store.apply(.eventEdit(eventID: event.id, patch: patch)) }
                    },
                    onDelete: {
                        // Local-only optimistic remove; engine will reconcile on next run.
                        // No dedicated mutation case yet — surface as a `.errandDoneToggle`-style
                        // signal once the engine drain spec gains delete semantics.
                    },
                    onDismiss: { editingEventID = nil }
                )
                .frame(minWidth: 720, idealWidth: 760, minHeight: 460, idealHeight: 580)
            }
        }
        .sheet(item: $detailProposal) { proposal in
            ProposalDetailSheet(
                proposal: proposal,
                onAccept: {
                    Task { await store.apply(.proposalAccept(proposalID: proposal.id)) }
                    detailProposal = nil
                },
                onDecline: {
                    Task { await store.apply(.proposalDecline(proposalID: proposal.id)) }
                    detailProposal = nil
                }
            )
            .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 480)
        }
    }

    private var errandEditSheetBinding: Binding<Bool> {
        Binding(
            get: { editingErrandID != nil },
            set: { if !$0 { editingErrandID = nil } }
        )
    }

    private var editEventSheetBinding: Binding<Bool> {
        Binding(
            get: { editingEventID != nil },
            set: { if !$0 { editingEventID = nil } }
        )
    }

    /// Locate an event by ID across all weekDays. Used by the edit sheet to
    /// resolve `editingEventID` to a live event from the snapshot — keeping
    /// the sheet in sync with optimistic mutations.
    private func findEvent(byID id: String) -> WREvent? {
        for day in weekDays {
            if let e = day.events.first(where: { $0.id == id }) {
                return e
            }
        }
        return nil
    }

    /// Placeholder reasoning text. Future: engine emits per-item reasoning
    /// via the dashboard JSON; this helper reads from the snapshot.
    private func eventReasoning(for event: WREvent) -> String {
        "This block came from the engine's most recent run. Adjust the time, day, or duration here — changes queue in the pending file and the engine reconciles on its next run."
    }

    private func triageReasoning(for entry: TriageEntry) -> String {
        switch entry.kind {
        case .pendingInvite:
            return "Calendar invite from \(entry.meta). RSVP inline or open Edit to set a follow-up plus dismiss reason."
        case .overdueTask:
            return "This task slipped past its scheduled day. Pick a new follow-up time or dismiss with a reason."
        case .needsTimeBlock:
            return "Engine flagged this for a time block but couldn't auto-place it. Edit to manually schedule or dismiss."
        case .other:
            return "Engine queued this for review based on recent activity in the source thread."
        }
    }

    /// Map our Codable `RunHealth` model onto the existing `RunHealthPill.State`
    /// enum. The pill type is a view-only thing — we don't make it Codable.
    private var runHealthDisplayState: RunHealthPill.State {
        switch runHealth {
        case .allGood:           return .allGood
        case .warning(let msg):  return .warning(msg)
        case .error(let msg):    return .error(msg)
        }
    }

    // MARK: - Alerts banner (engine-spec.md Step 5g — location intel + conflicts)

    // Alerts banner per UPDATE-2026-04-26-desktop-mac.md §`.alerts-shell` block.
    //
    // Outer shell (.alerts-shell): surfaceContainerLow bg, 1pt outlineVariant
    // border, r12, padding 14×16×16. Header is just "N need attention" + chevron
    // (the prior brandRust "● ALERTS" eyebrow is gone — the shell + per-row glow
    // carry the visual weight now).
    //
    // Each alert row has its own gradient bg (warmAmber 3% mix at bottom for
    // normal, brandRust 5% mix for `.is-urgent` kinds like commuteConflict) plus
    // its own underglow halo (warmAmber for normal, brandRust 0.75 opacity for
    // urgent). Action button is outlined transparent r6.
    private var alertsBannerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(alerts.count) need attention")
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurfaceVariant)
                Spacer(minLength: Space.s2)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        alertsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: alertsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if alertsExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceContainerLow)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.outlineVariant.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Today's Brief (engine-spec.md Step 6 + day-type narrative)

    @ViewBuilder
    private var todaysBriefSection: some View {
        if let brief = todaysBrief {
            DashboardCard(verticalPadding: Space.s5, horizontalPadding: Space.s6) {
                HStack(alignment: .top, spacing: Space.s5) {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        HStack(spacing: Space.s2) {
                            DayTypePill(kind: brief.dayType)
                            Text(brief.label)
                                .font(.labelSM)
                                .tracking(1.5)
                                .foregroundStyle(Color.secondaryText)
                        }

                        Text(brief.narrative)
                            .font(.bodyMD)
                            .foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Week Goals".uppercased())
                            .font(.labelSM)
                            .tracking(1.5)
                            .foregroundStyle(Color.secondaryText)

                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(brief.weekGoalsComplete)")
                                .font(.custom("Manrope", size: 28).weight(.light))
                                .foregroundStyle(Color.onSurface)
                            Text("of \(brief.weekGoalsTotal)")
                                .font(.bodySM)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }

                        GoalsProgressBar(complete: brief.weekGoalsComplete, total: brief.weekGoalsTotal)
                            .frame(width: 120, height: 4)
                    }
                }
            }
        }
    }

    // MARK: - Project Pulse

    private var projectPulseSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            SectionEyebrow(text: "Project Pulse", trailing: "\(pulseProjects.count) active")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.s4) {
                    ForEach(pulseProjects) { project in
                        Button {
                            selectedProjectId = project.id
                            detailProject = project
                        } label: {
                            ProjectPulseCard(project: project, isSelected: selectedProjectId == project.id)
                                .frame(width: 220, height: 168)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Week Grid

    private var weekGridSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("Week Grid".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)

                Button { dayTypeSettingsOpen = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Day type settings")

                Spacer(minLength: Space.s2)

                Text("8 AM — 6 PM · drag to reschedule")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            DashboardCard(verticalPadding: Space.s4, horizontalPadding: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    weekNavRow

                    switch range {
                    case .week:
                        // Day headers stay above the scroll region so they
                        // remain visible while the user scrolls hours.
                        dayHeaderRow

                        // Grid body lives inside a fixed-height ScrollView so
                        // zooming inflates the contents (more pixels per hour)
                        // without inflating the card itself. Apple Calendar /
                        // Google Calendar / Notion Calendar pattern.
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: true) {
                                gridBody
                                    .frame(height: dayColumnHeight)
                            }
                            .frame(height: visibleWindowHeight)
                            .onAppear {
                                // Scroll the grid so 8 AM sits at the visible
                                // top by default — the prior fixed window. User
                                // can scroll up to reach 6/7 AM or down for
                                // evening events.
                                proxy.scrollTo("hour-8", anchor: .top)
                            }
                        }
                    case .thirtyDay:
                        thirtyDayGrid
                    }
                }
            }
        }
    }

    // MARK: - 30 Day calendar grid

    private var thirtyDayGrid: some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                    Text(day.uppercased())
                        .font(.labelSM)
                        .tracking(1.5)
                        .foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 7),
                spacing: Space.s2
            ) {
                ForEach(thirtyDayCells) { cell in
                    ThirtyDayCalendarCell(cell: cell)
                }
            }
        }
    }

    private var thirtyDayCells: [ThirtyDayCell] {
        // Mocked: Apr 21 (Mon) → May 25 — 35 cells (5 rows × 7 cols).
        // Phase 5 wires real date math via the engine.
        let baseline = 21
        let todayOffset = 3   // Thu Apr 24
        return (0..<35).map { i in
            let absoluteDay = baseline + i
            let displayDay = absoluteDay > 30 ? absoluteDay - 30 : absoluteDay
            let monthLabel = absoluteDay > 30 ? "May" : "Apr"
            let weekdayIndex = i % 7   // 0 = Mon
            let isWeekend = weekdayIndex >= 5
            let dayType: DayType
            switch weekdayIndex {
            case 0: dayType = .admin
            case 1, 2: dayType = .make
            case 3: dayType = (i == todayOffset) ? .move : .make
            case 4: dayType = .make
            case 5: dayType = .recover
            default: dayType = .open
            }
            // Mocked event-count pattern — denser on weekdays
            let eventCount: Int
            if isWeekend {
                eventCount = (i % 4 == 0) ? 1 : 0
            } else {
                eventCount = ((i * 3) % 5)
            }
            return ThirtyDayCell(
                id: i,
                day: displayDay,
                monthLabel: i == 0 ? monthLabel : (absoluteDay == 31 ? "May" : ""),
                dayType: dayType,
                eventCount: eventCount,
                isToday: i == todayOffset
            )
        }
    }

    private var weekNavRow: some View {
        HStack(spacing: Space.s2) {
            navIconButton(symbol: "chevron.left", help: "Previous week") {
                weekOffset -= 1
            }

            Text(weekRangeLabel)
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
                .padding(.horizontal, Space.s2)

            navIconButton(symbol: "chevron.right", help: "Next week") {
                weekOffset += 1
            }

            if weekOffset != 0 {
                Button {
                    weekOffset = 0
                } label: {
                    Text("Today")
                        .font(.labelMD.weight(.medium))
                        .foregroundStyle(Color.tertiary)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s1_5)
                        .background(
                            Capsule()
                                .fill(Color.tertiary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: Space.s4)

            // Vertical zoom — small minimal slider that scales hour-row height.
            // Only shown for the week range (irrelevant in 30-day grid).
            if range == .week {
                WeekGridZoomSlider(
                    value: Binding(
                        get: { hourHeight },
                        set: { hourHeight = $0 }
                    ),
                    range: 40...80
                )
            }

            let rangeBinding = Binding<WeeklyRhythmRange>(
                get: { range },
                set: { range = $0 }
            )
            SegmentedTabBar(
                options: [WeeklyRhythmRange.week, WeeklyRhythmRange.thirtyDay],
                selection: rangeBinding,
                label: { $0 == .week ? "Week" : "30 Day" }
            )
            .frame(maxWidth: 180)
        }
        .padding(.bottom, Space.s2)
    }

    private var weekRangeLabel: String {
        // Mocked range — Phase 5 wires WeeklyRhythmService for real dates.
        switch (range, weekOffset) {
        case (.week, 0):       return "April 21 — 27"
        case (.week, 1):       return "April 28 — May 4"
        case (.week, -1):      return "April 14 — 20"
        case (.week, let n):   return n > 0 ? "+\(n) weeks" : "\(n) weeks"
        case (.thirtyDay, 0):  return "Apr 21 — May 20"
        case (.thirtyDay, _):  return "30 day window"
        }
    }

    private func navIconButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.surfaceContainerHigh)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var dayHeaderRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 44)
            ForEach(weekDays) { day in
                DayHeader(day: day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // Week-grid body — time column on the left + 7 day columns. Horizontal
    // hour dividers span the full grid width (across both time and day
    // columns) so each hour reads as a discrete row, with fainter half-hour
    // lines between them for finer eyeballing (à la Apple/Google Calendar).
    // Vertical dividers separate adjacent days. All at outlineVariant w/
    // tiered opacity (hour 18% > half-hour 7%).
    private var gridBody: some View {
        ZStack(alignment: .topLeading) {
            // Background hour + half-hour dividers — full-width horizontal lines.
            // Drawn first so day-column events render on top.
            VStack(spacing: 0) {
                ForEach(0..<hourCount, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.outlineVariant.opacity(0.18))
                        .frame(height: 1)
                    Spacer().frame(height: max(0, hourHeight / 2 - 1))
                    Rectangle()
                        .fill(Color.outlineVariant.opacity(0.07))
                        .frame(height: 1)
                    Spacer().frame(height: max(0, hourHeight / 2 - 1))
                }
            }
            .frame(height: dayColumnHeight)

            HStack(alignment: .top, spacing: 0) {
                // Time column — each label tagged with its hour ID so
                // ScrollViewReader can target a specific hour (default scroll
                // jumps to "hour-8" = 8 AM on appearance).
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(timeLabels.enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.custom("Inter-Regular", size: 9))
                            .foregroundStyle(Color.secondaryText)
                            .frame(width: 40, height: hourHeight, alignment: .topTrailing)
                            .padding(.trailing, Space.s1_5)
                            .offset(y: -5)   // pull label up so it sits on top of the divider line
                            .id("hour-\(Int(visibleStartHour) + index)")
                    }
                }
                .frame(width: 44)

                ForEach(Array(weekDays.enumerated()), id: \.element.id) { index, day in
                    DayColumn(
                        day: day,
                        totalHeight: dayColumnHeight,
                        hourScale: hourScale,
                        onEditEvent: { event in editingEventID = event.id }
                    )
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        // Vertical day-divider on the LEFT of every column except the first.
                        if index > 0 {
                            Rectangle()
                                .fill(Color.outlineVariant.opacity(0.18))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .dropDestination(for: String.self) { droppedItems, location in
                        moveEvent(droppedItems: droppedItems, toDayIndex: index, atY: location.y)
                    }
                }
            }
        }
    }

    private let timeLabels = [
        "6 AM", "7 AM", "8 AM", "9 AM", "10 AM", "11 AM",
        "12 PM", "1 PM", "2 PM", "3 PM", "4 PM", "5 PM",
        "6 PM", "7 PM", "8 PM", "9 PM"
    ]


    // MARK: - Errands (smart routing pool — engine-spec.md Errand Handling)

    private var errandsSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Errands".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Spacer(minLength: Space.s2)
                Text("\(pendingErrands.count) pending")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    ForEach(pendingErrands) { errand in
                        ErrandRow(
                            errand: errand,
                            onOpen: { editingErrandID = errand.id },
                            onToggleDone: {
                                Task {
                                    await store.apply(
                                        .errandDoneToggle(errandID: errand.id, isDone: !errand.isDone)
                                    )
                                }
                            }
                        )
                        .draggable(errand.id)
                        .dropDestination(for: String.self) { droppedItems, _ in
                            reorderErrands(droppedItems: droppedItems, beforeId: errand.id)
                        }
                        if errand.id != pendingErrands.last?.id {
                            RowSeparator()
                        }
                    }

                    if pendingErrands.isEmpty {
                        VStack(spacing: Space.s2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(Color.statusScheduled)
                            Text("All errands routed for the week")
                                .font(.bodySM)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s5)
                    }
                }
            }
        }
    }

    private var pendingErrands: [Errand] {
        errands.filter { !$0.isDone }
    }

    // Phase 5b: mutations flow through `store.apply(_:)`. Optimistic update
    // applies to the in-memory snapshot immediately; the data source persists
    // to `{user}/dashboards/dashboard-{ISODate}-pending.json` for `eventMove`
    // and to the app-local UI state JSON for `errandReorder`. Engine drains
    // the pending file on its next run.
    @discardableResult
    private func reorderErrands(droppedItems: [String], beforeId: String) -> Bool {
        let dropped = Set(droppedItems)
        let current = errands.map(\.id)
        var remaining = current.filter { !dropped.contains($0) }
        // Insert dropped items before beforeId (or at end if beforeId was itself dropped)
        if let insertAt = remaining.firstIndex(of: beforeId) {
            remaining.insert(contentsOf: droppedItems, at: insertAt)
        } else {
            remaining.append(contentsOf: droppedItems)
        }
        Task { await store.apply(.errandReorder(orderedIDs: remaining)) }
        return true
    }

    @discardableResult
    private func moveEvent(droppedItems: [String], toDayIndex: Int, atY: CGFloat) -> Bool {
        guard let droppedID = droppedItems.first else { return false }
        guard let snap = store.snapshot else { return false }

        // Locate the source event so we can preserve its duration.
        var source: WREvent?
        for day in snap.weekDays {
            if let e = day.events.first(where: { $0.id == droppedID }) {
                source = e
                break
            }
        }
        guard let source else { return false }

        // Convert pixel y → hour (relative to grid's visible-start at 6 AM).
        // Snap to the nearest half-hour for predictable placement.
        let unscaledY = atY / hourScale
        let rawHour = (unscaledY / 64) + 6.0
        let snappedStart = (rawHour * 2).rounded() / 2  // half-hour grid
        let duration = source.endHour - source.startHour
        let snappedEnd = snappedStart + duration

        Task {
            await store.apply(
                .eventMove(
                    eventID: droppedID,
                    newDayIndex: toDayIndex,
                    newStartHour: snappedStart,
                    newEndHour: snappedEnd
                )
            )
        }
        return true
    }

    // MARK: - Day Breakdown (engine-spec.md per-day narrative output)

    // Day Breakdown section — "blocks + focus bar" pattern per
    // UPDATE-2026-04-25-day-breakdown.md (chosen artboard "v23 / 2 + 3 combined"
    // from day-breakdown-variants.html).
    //
    // Each day: head row (weekday + date + type-pill + headline) → focus bar
    // (segments mapped across 6 AM → 9 PM, with summary on the right) → block
    // list (glyph + title + meta + type tag). Time axis (6 AM · 9 · 12 · 3 ·
    // 6 PM · 9) prints ONCE at the bottom of the section, not per row.
    private var dayBreakdownSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            SectionEyebrow(text: "Day Breakdown")

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    ForEach(dayBreakdownEntries) { entry in
                        DayBreakdownDayRow(entry: entry)
                        if entry.id != dayBreakdownEntries.last?.id {
                            Rectangle()
                                .fill(Color.outlineVariant.opacity(0.5))
                                .frame(height: 1)
                        }
                    }

                    // Time axis — once per section, justified across the bar's
                    // span (the 56pt right summary column is excluded from the
                    // axis range).
                    DayBreakdownTimeAxis()
                        .padding(.top, Space.s4)
                }
            }
        }
    }

    // MARK: - Triage + Claude Proposals

    private var triageAndProposalsSection: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            triageCard.frame(maxWidth: .infinity)
            proposalsCard.frame(maxWidth: .infinity)
        }
    }

    private var triageCard: some View {
        DashboardCard(verticalPadding: Space.s6, horizontalPadding: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s5) {
                HStack {
                    Text("Triage".uppercased())
                        .font(.labelSM)
                        .tracking(2.0)
                        .foregroundStyle(Color.secondaryText)
                    Spacer(minLength: Space.s2)
                    Text("**12** unread · 3 urgent")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }

                VStack(spacing: 0) {
                    ForEach(triageItems) { entry in
                        triageRow(entry)
                        if entry.id != triageItems.last?.id {
                            RowSeparator()
                        }
                    }
                }
            }
        }
    }


    private func triageRow(_ entry: TriageEntry) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            StatusDot(entry.status.styleKind)
                .padding(.top, 7)

            // Title + meta — keep clickable to open the detail sheet.
            Button {
                detailTriage = entry
            } label: {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(entry.title)
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text(entry.meta)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // RSVP buttons render only on pending-invite triage items.
            // Inline next to the row, padded to not bump row height.
            if entry.kind == .pendingInvite {
                TriageRsvpControl(
                    selected: rsvpSelections[entry.id],
                    onSelect: { response in
                        if response == .cleared {
                            rsvpSelections[entry.id] = nil
                        } else {
                            rsvpSelections[entry.id] = response
                        }
                        Task {
                            await store.apply(.triageRsvp(triageID: entry.id, response: response))
                        }
                    }
                )
                .padding(.top, 4)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.top, 7)
        }
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
        .onTapGesture { detailTriage = entry }
    }

    private var proposalsCard: some View {
        DashboardCard(verticalPadding: Space.s6, horizontalPadding: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s5) {
                HStack {
                    Text("Claude Proposals".uppercased())
                        .font(.labelSM)
                        .tracking(2.0)
                        .foregroundStyle(Color.secondaryText)
                    Spacer(minLength: Space.s2)
                    Text(proposalCountLabel)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }

                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(visibleProposals) { proposal in
                        proposalRow(proposal)
                    }

                    if visibleProposals.isEmpty {
                        emptyProposalsState
                    }
                }
            }
        }
    }

    // Phase 5b: accepted/declined proposals are filtered out of the snapshot
    // by `MutationApplier`, so `visibleProposals` is just the snapshot's list.
    private var visibleProposals: [Proposal] { proposals }

    private var proposalCountLabel: String {
        let count = visibleProposals.count
        return count == 0 ? "All resolved" : "\(count) new"
    }

    private var emptyProposalsState: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.statusScheduled)
            Text("All proposals reviewed")
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
    }

    private func proposalRow(_ proposal: Proposal) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Button {
                detailProposal = proposal
            } label: {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(proposal.title)
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text(proposal.reasoning)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: Space.s1) {
                Button {
                    Task { await store.apply(.proposalDecline(proposalID: proposal.id)) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color.surfaceContainerHigh)
                        )
                }
                .buttonStyle(.plain)
                .help("Decline")

                Button {
                    Task { await store.apply(.proposalAccept(proposalID: proposal.id)) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.onTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color.tertiary)
                        )
                }
                .buttonStyle(.plain)
                .help("Accept")
            }
            .padding(.top, 1)
        }
    }
}

// MARK: - Day breakdown views

private struct DayBreakdownDayRow: View {
    let entry: DayBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            head
            barRow
            blocksList
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(
            entry.isToday
                ? Color.tertiary.opacity(0.04)
                : Color.clear
        )
        .opacity(entry.isPast ? 0.7 : 1)
    }

    private var head: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(entry.weekday)
                    .font(.custom("Manrope", size: 13).weight(.semibold))
                    .foregroundStyle(entry.isToday ? Color.tertiaryBright : Color.onSurface)
                Text(" · \(entry.dateLabel)")
                    .font(.custom("Manrope", size: 13))
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            DayTypePill(kind: entry.dayType)

            Spacer(minLength: 8)

            if let headline = entry.headline, !headline.isEmpty {
                Text(headline)
                    .font(.custom("Inter-Regular", size: 11))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var barRow: some View {
        if entry.dayType == .open && entry.blocks.isEmpty {
            // No bar row for fully-empty Open days; the empty-state line in the
            // block list carries the message.
            EmptyView()
        } else {
            HStack(spacing: 12) {
                DayBreakdownFocusBar(blocks: entry.blocks)
                    .frame(maxWidth: .infinity)
                Text(entry.summary ?? "—")
                    .font(.custom("Inter-Regular", size: 9.5).monospacedDigit())
                    .foregroundStyle(Color.onSurfaceVariant)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var blocksList: some View {
        if entry.blocks.isEmpty {
            Text("Reserved for prep, recovery, or family time.")
                .font(.custom("Inter-Regular", size: 12.5).italic())
                .foregroundStyle(Color.onSurfaceVariant)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.blocks) { block in
                    DayBreakdownBlockRow(block: block)
                }
            }
        }
    }
}

// Focus bar — segments mapped from block start/end hours onto a 6 AM → 9 PM
// (15-hour) horizontal axis. Focus/recover blocks render full bar height (6pt);
// errand and sync render half-height (3pt) so they read as punctuation rather
// than blocks. Track is `surfaceContainer` 6pt.
private struct DayBreakdownFocusBar: View {
    let blocks: [DayBlock]

    private static let dayStart: Double = 6.0
    private static let daySpan:  Double = 15.0   // 6 AM → 9 PM

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.surfaceContainer)
                    .frame(height: 6)

                ForEach(positionedBlocks(width: proxy.size.width)) { positioned in
                    let block = positioned.block
                    Capsule()
                        .fill(fill(for: block))
                        .opacity(opacity(for: block))
                        .frame(width: positioned.width, height: barHeight(for: block))
                        .offset(x: positioned.x, y: barYOffset(for: block))
                }
            }
            .frame(height: 6)
        }
        .frame(height: 6)
    }

    private struct PositionedBlock: Identifiable {
        let id: String
        let block: DayBlock
        let x: CGFloat
        let width: CGFloat
    }

    private func positionedBlocks(width: CGFloat) -> [PositionedBlock] {
        blocks.compactMap { block in
            guard let start = block.startHour, let end = block.endHour, end > start else { return nil }
            let leftFraction  = max(0, (start - Self.dayStart) / Self.daySpan)
            let rightFraction = min(1, (end   - Self.dayStart) / Self.daySpan)
            let widthFraction = max(0, rightFraction - leftFraction)
            return PositionedBlock(
                id: block.id,
                block: block,
                x: width * leftFraction,
                width: max(2, width * widthFraction)
            )
        }
    }

    private func fill(for block: DayBlock) -> Color {
        switch block.kind {
        case .focus:    return Color.tertiary
        case .errand:   return Color.warmAmber
        case .sync:     return Color.onSurfaceVariant
        case .recover:  return Color.warmAmber
        case .admin:    return Color.onSurfaceVariant
        case .note:     return Color.clear
        }
    }

    private func opacity(for block: DayBlock) -> Double {
        switch block.kind {
        case .focus:    return 1.0
        case .errand:   return 0.55
        case .sync:     return 0.55
        case .recover:  return 0.35
        case .admin:    return 0.45
        case .note:     return 0
        }
    }

    private func barHeight(for block: DayBlock) -> CGFloat {
        switch block.kind {
        case .focus, .recover: return 6
        case .errand, .sync, .admin: return 3
        case .note: return 0
        }
    }

    private func barYOffset(for block: DayBlock) -> CGFloat {
        // half-height bars vertically centered in the 6pt track
        switch block.kind {
        case .focus, .recover, .note: return 0
        case .errand, .sync, .admin:  return 1.5
        }
    }
}

// Single block row in the per-day list — leading glyph + title + meta + tag.
private struct DayBreakdownBlockRow: View {
    let block: DayBlock

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(glyph)
                .font(.custom("Inter-Medium", size: glyphSize).weight(glyphWeight))
                .foregroundStyle(glyphColor)
                .frame(width: 14, alignment: .center)

            Text(block.title)
                .font(.custom("Inter-Regular", size: 12.5))
                .foregroundStyle(block.dim ? Color.onSurfaceVariant : Color.onSurface)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let meta = block.durationLabel ?? block.timeLabel {
                Text(meta)
                    .font(.custom("Inter-Regular", size: 10.5).monospacedDigit())
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            if let tag = block.tag {
                DayBreakdownTagChip(tag: tag)
            }
        }
        .padding(.vertical, 2)
    }

    private var glyph: String {
        switch block.kind {
        case .focus:  return "●"
        case .errand: return "→"
        default:      return "·"
        }
    }

    private var glyphSize: CGFloat {
        switch block.kind {
        case .focus:  return 9
        case .errand: return 12
        default:      return 14
        }
    }

    private var glyphWeight: Font.Weight {
        block.kind == .focus ? .semibold : .regular
    }

    private var glyphColor: Color {
        switch block.kind {
        case .focus:  return Color.tertiaryBright
        case .errand: return Color.warmAmber
        default:      return Color.onSurfaceVariant
        }
    }
}

// Small uppercase type tag — Admin / Make / Move / Errand / Sync.
private struct DayBreakdownTagChip: View {
    let tag: DayBlockTag

    var body: some View {
        Text(tag.label.uppercased())
            .font(.custom("Inter-Medium", size: 9).weight(.semibold))
            .tracking(0.4)
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(bgColor)
            )
    }

    private var textColor: Color {
        switch tag {
        case .admin:  return Color.onSurfaceVariant
        case .make:   return Color.onSurface
        case .move:   return Color.tertiaryBright
        case .errand: return Color.warmAmber
        case .sync:   return Color.onSurfaceVariant
        }
    }

    private var bgColor: Color {
        switch tag {
        case .admin:  return Color.surfaceContainer
        case .make:   return Color.surfaceContainer
        case .move:   return Color.chipTertiaryBg
        case .errand: return Color.warmAmberDim
        case .sync:   return Color.surfaceContainer
        }
    }
}

// Time axis printed once below the day breakdown — 6 AM · 9 · 12 · 3 · 6 PM · 9.
// Justified across the bar's span; the right summary column is excluded so the
// labels line up under the bar segments.
private struct DayBreakdownTimeAxis: View {
    private let labels = ["6 AM", "9", "12", "3", "6 PM", "9"]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.custom("Inter-Regular", size: 9).monospacedDigit())
                        .foregroundStyle(Color.onSurfaceVariant.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            // Reserve the same 64pt right gutter as the bar's summary column so
            // the labels stay aligned with the bar's actual horizontal range.
            Color.clear.frame(width: 64)
        }
    }
}

// MARK: - Week grid zoom slider
//
// Small minimal slider for vertical zoom on the week calendar — drives the
// `hourHeight` state. Track is 80pt × 2pt in surfaceContainerHigh; thumb is
// an 8pt circle in onSurface. Tiny − / + glyphs flank the track. Drag the
// thumb or click the glyphs to adjust. Designed to read as a "subtle utility
// control" rather than a primary affordance.

private struct WeekGridZoomSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    private let trackWidth: CGFloat = 72
    private let trackHeight: CGFloat = 2
    private let thumbSize: CGFloat = 9

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "minus")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .onTapGesture { adjust(-8) }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.surfaceContainerHigh)
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .fill(Color.onSurface.opacity(0.35))
                    .frame(width: max(0, fraction * trackWidth), height: trackHeight)

                Circle()
                    .fill(Color.onSurface)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: fraction * trackWidth - thumbSize / 2)
            }
            .frame(width: trackWidth, height: max(thumbSize, trackHeight))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = gesture.location.x / trackWidth
                        let clamped = min(max(raw, 0), 1)
                        let span = range.upperBound - range.lowerBound
                        value = range.lowerBound + clamped * span
                    }
            )

            Image(systemName: "plus")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .onTapGesture { adjust(8) }
        }
        .help("Vertical zoom")
    }

    private func adjust(_ delta: CGFloat) {
        let next = value + delta
        value = min(max(next, range.lowerBound), range.upperBound)
    }
}

// MARK: - Alert card
//
// Translated from `.alert-row` + `.alert-row.is-urgent` in
// family-dashboard-mockup-desktop-v1.html. Per-row gradient bg, per-row warm
// or rust underglow, outlined action button. Sized at desktop scale: 11×13
// padding, gap 11, radius 10, icon 26pt circle.

private struct AlertCard: View {
    let alert: WeeklyRhythmAlert

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private var glowTint: Color {
        alert.kind.isUrgent ? .brandRust : .warmAmber
    }

    private var gradientBg: LinearGradient {
        let base = Color.surfaceContainer
        let bottom: Color = alert.kind.isUrgent
            ? Color(light: 0x2C2624, dark: 0x2C2624)   // surfaceContainer + 5% brandRust mix
            : Color(light: 0x2A2722, dark: 0x2A2722)   // surfaceContainer + 3% warmAmber mix
        return LinearGradient(colors: [base, bottom], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Alert icon — 26pt circle, surfaceContainerHigh bg
            ZStack {
                Circle().fill(Color.surfaceContainerHigh)
                Image(systemName: alert.kind.symbol)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(alert.kind.tint)
            }
            .frame(width: 26, height: 26)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(alert.day.uppercased())
                        .font(.labelSM)
                        .tracking(1.5)
                        .foregroundStyle(Color.onSurfaceVariant)
                    Text(alert.kind.label)
                        .font(.labelSM)
                        .foregroundStyle(alert.kind.isUrgent ? Color.brandRustSoft : Color.onSurfaceVariant)
                }

                Text(alert.title)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(alert.detail)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionLabel = alert.actionLabel {
                AlertActionButton(label: actionLabel) {}
                    .padding(.top, 2)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(gradientBg)
        )
        .overlay(alignment: .bottom) {
            // Per-row underglow — warm amber (normal) or brand rust (urgent).
            // Geometry matches `.alert-row::after` desktop spec: bottom -10pt,
            // height 22pt, blur 10pt, 12% horizontal inset.
            GeometryReader { proxy in
                let glowWidth = proxy.size.width * 0.76
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: alert.kind.isUrgent ? [
                                .init(color: glowTint.opacity(0.60), location: 0.0),
                                .init(color: glowTint.opacity(0.28), location: 0.35),
                                .init(color: glowTint.opacity(0.0),  location: 0.75)
                            ] : [
                                .init(color: glowTint.opacity(0.35), location: 0.0),
                                .init(color: glowTint.opacity(0.15), location: 0.40),
                                .init(color: glowTint.opacity(0.0),  location: 0.75)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: glowWidth / 2
                        )
                    )
                    .frame(width: glowWidth, height: 22)
                    .blur(radius: 10)
                    .opacity({
                        let base = alert.kind.isUrgent ? 0.75 : 0.5
                        if reduceMotion { return base }
                        return animate ? base + 0.20 : base - 0.10
                    }())
                    .scaleEffect(
                        x: reduceMotion ? 1.0 : (animate ? 1.02 : 0.96),
                        y: 1,
                        anchor: .center
                    )
                    .position(x: proxy.size.width / 2, y: 11)
            }
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .offset(y: 10)
            .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Alert-action button (outlined, transparent)
//
// Per `.alert-action` desktop spec — transparent bg, 1pt outline-variant border,
// r6, 5×11 padding, 12px font weight 500. NOT one of the standard button styles
// because the alerts module specifically wants a quieter outlined treatment vs.
// the filled `.alignedSecondary` used elsewhere.

private struct AlertActionButton: View {
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.labelLG)
                .foregroundStyle(Color.onSurface)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.surfaceContainerHigh : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isHovering ? Color.onSurfaceVariant : Color.outlineVariant,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.18), value: isHovering)
    }
}

// MARK: - Run Health pill (engine-spec.md run health diagnostic)

private struct RunHealthPill: View {
    enum State {
        case allGood
        case warning(String)
        case error(String)
    }

    let state: State

    var body: some View {
        HStack(spacing: Space.s1_5) {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.labelMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1_5)
        .background(
            Capsule()
                .fill(Color.surfaceContainerHigh)
        )
    }

    private var glyph: String {
        switch state {
        case .allGood: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .allGood:        return Color.statusScheduled
        case .warning:        return Color.statusDraft
        case .error:          return Color.statusError
        }
    }

    private var label: String {
        switch state {
        case .allGood:                 return "All good"
        case .warning(let message):    return message
        case .error(let message):      return message
        }
    }
}

// MARK: - Errand Detail sheet (edit fields)

// Errand edit sheet — re-skinned on AlignedSheet (v4.x parity pass).
// Spec: .claude/design/v4-parity-pass/README.md §4
private struct ErrandDetailSheet: View {
    let initialErrand: Errand
    let onSave: (ErrandPatch) -> Void
    let onMarkDone: () -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var location: String
    @State private var routedTo: String
    @State private var notes: String

    init(
        initialErrand: Errand,
        onSave: @escaping (ErrandPatch) -> Void,
        onMarkDone: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.initialErrand = initialErrand
        self.onSave = onSave
        self.onMarkDone = onMarkDone
        self.onDismiss = onDismiss
        _title = State(initialValue: initialErrand.title)
        _location = State(initialValue: initialErrand.location ?? "")
        _routedTo = State(initialValue: initialErrand.routedTo ?? "")
        _notes = State(initialValue: "")
    }

    var body: some View {
        AlignedSheet(
            eyebrow: "Errand",
            title: title.isEmpty ? "Edit errand" : title,
            badge: AnyView(daysPendingBadge),
            idealWidth: 560,
            onDismiss: onDismiss,
            content: { editBody },
            footer: { footerActions }
        )
    }

    // MARK: - Header badge

    private var daysPendingBadge: some View {
        let isOverdue = initialErrand.daysPending >= 14
        return Text("\(initialErrand.daysPending)d pending")
            .font(.labelSM)
            .tracking(0.4)
            .foregroundStyle(isOverdue ? Color.onSurface : Color.onSurfaceVariant)
            .padding(.horizontal, Space.s2_5)
            .frame(height: 22)
            .background(
                Capsule().fill(
                    isOverdue ? Color.brandRust.opacity(0.85) : Color.surfaceContainerHigh
                )
            )
    }

    // MARK: - Body

    private var editBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GhostBorderField(label: "Title", text: $title)

            HStack(alignment: .top, spacing: Space.s3) {
                GhostBorderField(
                    label: "Location",
                    text: $location,
                    placeholder: "e.g. Downtown · 12 min"
                )
                GhostBorderField(
                    label: "Route to",
                    text: $routedTo,
                    placeholder: "e.g. Monday (leave blank for Unrouted)"
                )
            }

            GhostBorderField(
                label: "Notes",
                text: $notes,
                axis: .vertical,
                placeholder: "Optional context for this errand",
                lineLimit: 3...6
            )

            if initialErrand.daysPending >= 9 {
                nudgeCard
            }
        }
    }

    private var nudgeCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Circle()
                .fill(Color.brandRust)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Pending \(initialErrand.daysPending)d")
                    .font(.headlineSM)
                    .foregroundStyle(Color.onSurface)

                Text(initialErrand.daysPending >= 14
                     ? "This errand has aged past two weeks. Route it to a day this week or mark it done."
                     : "Approaching the two-week threshold. Consider routing it now.")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .padding(.horizontal, Space.s1)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.brandRust.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(Color.brandRust.opacity(0.28), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footerActions: some View {
        Group {
            // Leading slot — Mark done with a status-scheduled tile + label.
            Button(action: {
                onMarkDone()
                onDismiss()
            }) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.statusScheduled)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(Color.statusScheduled.opacity(0.18))
                        )
                    Text("Mark done")
                        .font(.labelLG.weight(.medium))
                        .foregroundStyle(Color.statusScheduled)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Cancel", action: onDismiss)
                .buttonStyle(.alignedSecondary)

            Button("Save changes") {
                onSave(buildPatch())
                onDismiss()
            }
            .buttonStyle(.alignedPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Patch

    private func buildPatch() -> ErrandPatch {
        ErrandPatch(
            title: title != initialErrand.title ? title : nil,
            location: normalizedLocation(),
            routedTo: normalizedRoutedTo(),
            notes: notes.isEmpty ? nil : notes,
            isDone: nil  // Mark done flows through onMarkDone, not the patch
        )
    }

    private func normalizedLocation() -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = initialErrand.location ?? ""
        return trimmed != original ? (trimmed.isEmpty ? "" : trimmed) : nil
    }

    private func normalizedRoutedTo() -> String? {
        let trimmed = routedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = initialErrand.routedTo ?? ""
        return trimmed != original ? (trimmed.isEmpty ? "" : trimmed) : nil
    }
}

// MARK: - Proposal Detail sheet

private struct ProposalDetailSheet: View {
    let proposal: Proposal
    let onAccept: () -> Void
    let onDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                EditorialHeader(eyebrow: "Claude Proposal", title: proposal.title)

                VStack(alignment: .leading, spacing: Space.s5) {
                    DashboardCard(verticalPadding: Space.s4, horizontalPadding: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("Reasoning".uppercased())
                                .font(.labelSM)
                                .tracking(1.0)
                                .foregroundStyle(Color.secondaryText)
                            Text(proposal.reasoning)
                                .font(.bodyMD)
                                .foregroundStyle(Color.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    DashboardCard(verticalPadding: Space.s4, horizontalPadding: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("Proposed Change".uppercased())
                                .font(.labelSM)
                                .tracking(1.0)
                                .foregroundStyle(Color.secondaryText)
                            Text("Phase 5 wires the real before/after diff from the engine. For now this is the proposal title rendered as the change summary.")
                                .font(.bodyMD)
                                .foregroundStyle(Color.onSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: Space.s2) {
                        Spacer()
                        Button(action: onDecline) {
                            Text("Decline")
                                .font(.labelLG.weight(.medium))
                                .foregroundStyle(Color.onSurface)
                                .padding(.horizontal, Space.s4)
                                .padding(.vertical, Space.s2_5)
                                .background(Capsule().fill(Color.surfaceContainerHigh))
                        }
                        .buttonStyle(.plain)

                        Button(action: onAccept) {
                            HStack(spacing: Space.s1_5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Accept")
                                    .font(.labelLG.weight(.semibold))
                            }
                            .foregroundStyle(Color.onTertiary)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s2_5)
                            .background(Capsule().fill(Color.tertiary))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.s10)

                Spacer(minLength: Space.s4)
            }
            .padding(.vertical, Space.s8)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.surface)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

// MARK: - Day Type Settings sheet

private struct DayTypeSettingsSheet: View {
    let weekDays: [WeekDay]
    let onChange: (String, WRDayType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                EditorialHeader(eyebrow: "Settings", title: "Day Types")

                Text("Tap a type to set the day's primary mode. Edits write to your config.md so the engine picks them up on its next run.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.s10)

                DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                    VStack(spacing: 0) {
                        ForEach(weekDays) { day in
                            dayRow(day)
                            if day.id != weekDays.last?.id {
                                Rectangle()
                                    .fill(Color.outlineVariant.opacity(0.18))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.s10)

                Spacer(minLength: Space.s4)
            }
            .padding(.vertical, Space.s8)
        }
        .background(Color.surface)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ day: WeekDay) -> some View {
        let fullName = Self.fullName(for: day.name)
        let current = day.primaryDayType
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Text(fullName)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                    .frame(width: 96, alignment: .leading)

                Spacer(minLength: Space.s2)

                HStack(spacing: Space.s1_5) {
                    ForEach(WRDayType.allCases, id: \.self) { type in
                        Button {
                            onChange(fullName, type)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(type.tint)
                                    .frame(width: 8, height: 8)
                                Text(type.label)
                                    .font(.labelSM.weight(.medium))
                                    .foregroundStyle(
                                        type == current ? Color.onTertiary : Color.onSurface
                                    )
                            }
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    type == current ? Color.tertiary : Color.surfaceContainerHigh
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, Space.s3)
    }

    /// Map a WeekDay's short `name` ("Mon") to a full English name ("Monday")
    /// for display and for the mutation. Defaults to the short name itself if
    /// nothing matches (engine could emit any string).
    private static func fullName(for shortName: String) -> String {
        let map: [String: String] = [
            "sun": "Sunday", "mon": "Monday", "tue": "Tuesday",
            "wed": "Wednesday", "thu": "Thursday", "fri": "Friday",
            "sat": "Saturday"
        ]
        return map[shortName.prefix(3).lowercased()] ?? shortName
    }
}

// MARK: - Goals progress bar

private struct GoalsProgressBar: View {
    let complete: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.surfaceContainerHigh)
                Capsule()
                    .fill(Color.tertiary)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
    }

    private var fraction: CGFloat {
        total <= 0 ? 0 : CGFloat(complete) / CGFloat(total)
    }
}

// Workaround: Space doesn't define s3_5 (14pt). Use s4 (16) where 14 was specced.
// Kept as a private alias to flag the spec drift if it bites later.
private extension Space {
    static let s3_5: CGFloat = Space.s4
}

// MARK: - Project Pulse card

// MARK: - 30 day calendar models + cell

private struct ThirtyDayCell: Identifiable {
    let id: Int
    let day: Int
    let monthLabel: String   // empty unless this cell is the first of a month
    let dayType: DayType
    let eventCount: Int
    let isToday: Bool
}

private struct ThirtyDayCalendarCell: View {
    let cell: ThirtyDayCell

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1_5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(cell.day)")
                    .font(.system(size: 14, weight: cell.isToday ? .semibold : .regular))
                    .foregroundStyle(cell.isToday ? Color.tertiary : Color.onSurface)
                if !cell.monthLabel.isEmpty {
                    Text(cell.monthLabel)
                        .font(.labelSM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                DayTypePill(kind: cell.dayType)
            }

            Spacer(minLength: 0)

            if cell.eventCount > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<min(cell.eventCount, 4), id: \.self) { _ in
                        Circle()
                            .fill(cell.dayType.tint)
                            .frame(width: 5, height: 5)
                    }
                    if cell.eventCount > 4 {
                        Text("+\(cell.eventCount - 4)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                }
            }
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(cell.isToday ? Color.tertiary.opacity(0.08) : Color.surfaceContainerLow)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(cell.isToday ? Color.tertiary : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Project Pulse card

private struct ProjectPulseCard: View {
    let project: PulseProject
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                StatusDot(project.status.styleKind)
                Text(project.statusLabel.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .padding(.bottom, Space.s2_5)

            Text(project.title)
                .font(.headlineSM)
                .foregroundStyle(Color.onSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Space.s2)

            Text(project.touched)
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)

            Spacer(minLength: Space.s2)

            Text(project.action)
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isSelected ? Color.tertiary : Color.clear, lineWidth: 1.5)
        )
        .offset(y: (isHovering && !isSelected) ? -2 : 0)
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .whisperShadow()
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Day header + column

private struct DayHeader: View {
    // Phase 5a: read-only day header. The inline DayTypeEditor (which mutated
    // a binding into day.dayTypes) is gone; day-type editing flows through the
    // gear-icon → DayTypeSettingsSheet path until write-back lands in 5b.
    let day: WeekDay

    var body: some View {
        VStack(alignment: .center, spacing: Space.s1) {
            Text(day.name)
                .font(.bodySM.weight(.medium))
                .foregroundStyle(day.isToday ? Color.tertiary : Color.onSurfaceVariant)
            Text(day.num)
                .font(.headlineMD)
                .foregroundStyle(day.isToday ? Color.tertiary : Color.onSurface)

            VStack(spacing: 3) {
                ForEach(day.sortedDayTypes, id: \.self) { type in
                    DayTypePill(kind: type)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.vertical, Space.s2)
        .padding(.horizontal, Space.s2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(day.isToday ? Color.tertiary.opacity(0.06) : Color.clear)
        )
    }
}

// MARK: - Day Type editor (custom dropdown matching engine HTML design)
//
// Replaces SwiftUI's native Menu so we control the visual language. Layout
// mirrors the dashboard-template.html .dt-area pattern: each active type
// renders as a pill (with × to remove when count > 1), followed by a small
// ▼ chevron that opens a popover. The popover lists each available type
// with two cells: name (replaces all current types) + plus (stacks
// additionally). Exclusive types hide the plus cell.

private struct DayTypeEditor: View {
    @Binding var types: Set<DayType>
    @State private var dropdownOpen: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            ForEach(sortedTypes, id: \.self) { type in
                DayTypePill(kind: type, removable: types.count > 1) {
                    types.remove(type)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Button {
                dropdownOpen.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .frame(width: 22, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.surfaceContainerHigh)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $dropdownOpen, arrowEdge: .top) {
                DayTypeDropdown(activeTypes: types) { newTypes in
                    types = newTypes
                }
                .frame(minWidth: 220)
            }
            .help("Change or stack day types")
        }
    }

    private var sortedTypes: [DayType] {
        DayType.allCases.filter { types.contains($0) }
    }
}

private struct DayTypeDropdown: View {
    let activeTypes: Set<DayType>
    let onChange: (Set<DayType>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(DayType.allCases.enumerated()), id: \.offset) { index, type in
                DayTypeOption(
                    type: type,
                    isActive: activeTypes.contains(type),
                    onReplace: {
                        onChange([type])
                    },
                    onStack: {
                        var next = activeTypes.filter { !$0.isExclusive }
                        next.insert(type)
                        onChange(next)
                    }
                )

                if index < DayType.allCases.count - 1 {
                    Rectangle()
                        .fill(Color.outlineVariant.opacity(0.2))
                        .frame(height: 1)
                }
            }
        }
        .background(Color.cardBackground)
    }
}

private struct DayTypeOption: View {
    let type: DayType
    let isActive: Bool
    let onReplace: () -> Void
    let onStack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onReplace) {
                HStack(spacing: Space.s2) {
                    Circle()
                        .fill(type.tint)
                        .frame(width: 8, height: 8)
                    Text(type.label)
                        .font(.bodySM.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Color.tertiary : Color.onSurface)
                    Spacer(minLength: Space.s2)
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.tertiary)
                    }
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !type.isExclusive {
                Rectangle()
                    .fill(Color.outlineVariant.opacity(0.18))
                    .frame(width: 1, height: 28)

                Button(action: onStack) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stack this type alongside existing")
            }
        }
    }
}

private struct DayTypePill: View {
    let kind: DayType
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            Text(kind.label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(kind.tint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if removable, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(kind.tint.opacity(0.6))
                        .frame(width: 10, height: 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this day type")
            }
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(kind.tint.opacity(0.12))
        )
    }
}

private struct DayColumn: View {
    let day: WeekDay
    let totalHeight: CGFloat
    let hourScale: CGFloat
    let onEditEvent: (WREvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(day.isToday ? Color.tertiary.opacity(0.04) : Color.clear)
                .frame(height: totalHeight)

            ForEach(day.events) { event in
                // Hour-relative positioning per the engine JSON spec — 8 AM is
                // the visible top of the grid (offset 0). 64pt baseline × hourScale
                // = current hourHeight, so the math collapses to (h × hourHeight).
                Button { onEditEvent(event) } label: {
                    EventBlock(event: event)
                        .frame(height: (event.endHour - event.startHour) * 64 * hourScale)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: (event.startHour - 6.0) * 64 * hourScale)
                .draggable(event.id)
            }

            if let nowHour = day.nowLineHour {
                Rectangle()
                    .fill(Color.tertiary)
                    .frame(height: 1.5)
                    .padding(.horizontal, 2)
                    .offset(y: (nowHour - 6.0) * 64 * hourScale)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
    }
}

private struct EventBlock: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let time = event.time {
                Text(time)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(timeColor)
                    .padding(.bottom, 1)
            }
            Text(event.title)
                .font(event.kind == .errand ? .system(size: 10) : .system(size: 11, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(2)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, event.kind == .errand ? 2 : Space.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(fill)
        )
    }

    private var fill: Color {
        switch event.kind {
        case .regular: return Color.surfaceContainerHigh
        case .accent:  return Color.tertiary
        case .errand:  return Color.surfaceContainer
        }
    }

    private var textColor: Color {
        event.kind == .accent ? Color.onTertiary : Color.onSurface
    }

    private var timeColor: Color {
        event.kind == .accent ? Color.onTertiary.opacity(0.85) : Color.onSurfaceVariant
    }
}

// MARK: - Errand row
//
// Per Phase 5a wire-up: takes the errand by value + a callback for toggle-done
// since the data source is read-only at this stage. Parent routes the callback
// to a TODO until Phase 5b adds write-back to the engine.

private struct ErrandRow: View {
    let errand: Errand
    let onOpen: () -> Void
    let onToggleDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Button(action: onToggleDone) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(errand.isDone ? Color.statusScheduled : Color.outlineVariant, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(errand.isDone ? Color.statusScheduled : Color.clear)
                        )
                        .frame(width: 18, height: 18)
                    if errand.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
            .help(errand.isDone ? "Mark as pending" : "Mark done")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(errand.title)
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(errand.isDone ? Color.onSurfaceVariant : Color.onSurface)
                        .strikethrough(errand.isDone, color: Color.onSurfaceVariant)

                    HStack(spacing: Space.s2) {
                        if let location = errand.location {
                            Label(location, systemImage: "location")
                                .font(.bodySM)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }

                        if let routed = errand.routedTo {
                            Label(routed, systemImage: "calendar")
                                .font(.bodySM)
                                .foregroundStyle(Color.tertiary)
                        } else {
                            Text("Unrouted")
                                .font(.bodySM)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            DaysPendingPill(days: errand.daysPending)
                .padding(.top, 2)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.onSurfaceVariant.opacity(0.45))
                .padding(.leading, Space.s2)
                .padding(.top, 4)
                .help("Drag to reorder")
        }
        .padding(.vertical, Space.s3)
    }
}

private struct DaysPendingPill: View {
    let days: Int

    var body: some View {
        Text("\(days)d")
            .font(.labelSM.weight(.medium))
            .foregroundStyle(textColor)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(fillColor)
            )
    }

    // Engine-spec.md Errand Handling: nudge errands sitting longer than the
    // config threshold (default 14 days). brandRust on the pill flags those.
    private var fillColor: Color {
        days >= 14 ? Color.brandRust.opacity(0.14) : Color.surfaceContainerHigh
    }

    private var textColor: Color {
        days >= 14 ? Color.brandRust : Color.onSurfaceVariant
    }
}

// MARK: - Project Detail sheet

private struct ProjectDetailSheet: View {
    let project: PulseProject

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                header

                section(title: "This Week") {
                    VStack(alignment: .leading, spacing: 0) {
                        relatedEvent(time: "Today · 10:00 AM", title: "Braxton edit · pass 3", meta: "Make block · 2h")
                        RowSeparator()
                        relatedEvent(time: "Today · 3:00 PM", title: "Braxton sync", meta: "Recurring · video call")
                        RowSeparator()
                        relatedEvent(time: "Friday · 3:00 PM", title: "Braxton sync (moved)", meta: "Per accepted proposal")
                    }
                    .padding(.vertical, Space.s2)
                    .padding(.horizontal, Space.s4)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(Color.surfaceContainerLow)
                    )
                }

                section(title: "Recent Activity") {
                    VStack(alignment: .leading, spacing: 0) {
                        activityRow(when: "4h ago", text: "Pushed pass 2 to client folder")
                        RowSeparator()
                        activityRow(when: "Yesterday", text: "Added scene-04 cut + lower-thirds revision")
                        RowSeparator()
                        activityRow(when: "Tue", text: "Notion: status moved In Progress → In Review")
                    }
                    .padding(.vertical, Space.s2)
                    .padding(.horizontal, Space.s4)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(Color.surfaceContainerLow)
                    )
                }

                section(title: "Quick Actions") {
                    HStack(spacing: Space.s2) {
                        actionButton(label: "Mark Complete", symbol: "checkmark.circle")
                        actionButton(label: "Block", symbol: "exclamationmark.octagon")
                        actionButton(label: "Snooze", symbol: "clock")
                        actionButton(label: "Open in Notion", symbol: "arrow.up.right.square")
                    }
                }

                Spacer(minLength: Space.s4)
            }
            .padding(Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.surface)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                StatusDot(project.status.styleKind)
                Text(project.statusLabel.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            Text(project.title)
                .font(.displaySM)
                .foregroundStyle(Color.onSurface)

            Text(project.touched)
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)

            Text(project.action)
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
                .padding(.top, Space.s1)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title.uppercased())
                .font(.labelSM)
                .tracking(1.5)
                .foregroundStyle(Color.secondaryText)
            content()
        }
    }

    private func relatedEvent(time: String, title: String, meta: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(time)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 140, alignment: .leading)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(meta)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func activityRow(when label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(label)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 80, alignment: .leading)
            Text(text)
                .font(.bodyMD)
                .foregroundStyle(Color.onSurface)
        }
        .padding(.vertical, Space.s3)
    }

    private func actionButton(label: String, symbol: String) -> some View {
        Button {} label: {
            HStack(spacing: Space.s1_5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .regular))
                Text(label)
                    .font(.labelMD.weight(.medium))
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(
                Capsule()
                    .fill(Color.surfaceContainerHigh)
            )
        }
        .buttonStyle(.plain)
    }
}
