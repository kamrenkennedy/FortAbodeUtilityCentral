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

struct WeeklyRhythmView: View {
    @State private var resolvedProposals: [UUID: ProposalResolution] = [:]
    @State private var weekOffset: Int = 0
    @State private var range: WeeklyRhythmRange = .week
    @State private var selectedProjectId: UUID?
    @State private var detailProject: PulseProject?
    @State private var weekDays: [WeekDay] = WeeklyRhythmView.makeMockedWeekDays()
    @State private var errands: [Errand] = WeeklyRhythmView.makeMockedErrands()
    @State private var dayTypeSettingsOpen: Bool = false
    @State private var editingErrandID: UUID?
    @State private var detailTriage: TriageEntry?
    @State private var detailProposal: Proposal?
    @State private var alertsExpanded: Bool = true
    @State private var alerts: [WeeklyRhythmAlert] = WeeklyRhythmView.makeMockedAlerts()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: "Week 17", title: "April 21 — 27")
                    .overlay(alignment: .topTrailing) {
                        RunHealthPill(state: .allGood)
                            .padding(.top, Space.s10)
                            .padding(.trailing, Space.s16)
                    }

                VStack(alignment: .leading, spacing: Space.s12) {
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
                .padding(.horizontal, Space.s16)
                .padding(.bottom, Space.s24)
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
            DayTypeSettingsSheet()
                .frame(minWidth: 520, idealWidth: 640, minHeight: 480, idealHeight: 600)
        }
        .sheet(isPresented: errandEditSheetBinding) {
            if let id = editingErrandID, let index = errands.firstIndex(where: { $0.id == id }) {
                ErrandDetailSheet(errand: $errands[index])
                    .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 520)
            }
        }
        .sheet(item: $detailTriage) { entry in
            TriageDetailSheet(entry: entry)
                .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 440)
        }
        .sheet(item: $detailProposal) { proposal in
            ProposalDetailSheet(
                proposal: proposal,
                isResolved: resolvedProposals[proposal.id] != nil,
                onAccept: {
                    withAnimation(.easeOut(duration: 0.3)) {
                        resolvedProposals[proposal.id] = .accepted
                    }
                    detailProposal = nil
                },
                onDecline: {
                    withAnimation(.easeOut(duration: 0.3)) {
                        resolvedProposals[proposal.id] = .declined
                    }
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

    // MARK: - Alerts banner (engine-spec.md Step 5g — location intel + conflicts)

    private var alertsBannerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Circle()
                        .fill(Color.brandRust)
                        .frame(width: 6, height: 6)
                    Text("Alerts".uppercased())
                        .font(.labelSM)
                        .tracking(2.0)
                        .foregroundStyle(Color.brandRust)
                    Text("\(alerts.count) need attention")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }

                Spacer(minLength: Space.s2)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        alertsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: alertsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, alertsExpanded ? Space.s4 : 0)

            if alertsExpanded {
                DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s5) {
                    VStack(spacing: 0) {
                        ForEach(alerts.indices, id: \.self) { i in
                            alertRow(alerts[i])
                            if i < alerts.count - 1 {
                                RowSeparator()
                            }
                        }
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.brandRust)
                        .frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func alertRow(_ alert: WeeklyRhythmAlert) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: alert.kind.symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(alert.kind.tint)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(alert.kind.tint.opacity(0.12))
                )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    Text(alert.day.uppercased())
                        .font(.labelSM)
                        .tracking(1.5)
                        .foregroundStyle(Color.secondaryText)
                    Text("·")
                        .foregroundStyle(Color.outlineVariant)
                    Text(alert.kind.label)
                        .font(.labelSM)
                        .foregroundStyle(alert.kind.tint)
                }

                Text(alert.title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)

                Text(alert.detail)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s3)

            if let actionLabel = alert.actionLabel {
                Button {} label: {
                    Text(actionLabel)
                        .font(.labelMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s1_5)
                        .background(Capsule().fill(Color.surfaceContainerHigh))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, Space.s4)
    }

    private static func makeMockedAlerts() -> [WeeklyRhythmAlert] {
        [
            WeeklyRhythmAlert(
                kind: .travel,
                day: "Saturday",
                title: "Gallery drop-off — 12 PM downtown",
                detail: "18 min drive each way. Plan a 30 min buffer for parking + load-in.",
                actionLabel: "View itinerary"
            ),
            WeeklyRhythmAlert(
                kind: .commuteConflict,
                day: "Friday",
                title: "Tight commute window before Braxton sync",
                detail: "Studio-site DNS work runs to noon, but the dry cleaner closes at 12:30 — fits with a buffer or push to Saturday.",
                actionLabel: "Reschedule"
            )
        ]
    }

    // MARK: - Today's Brief (engine-spec.md Step 6 + day-type narrative)

    private var todaysBriefSection: some View {
        DashboardCard(verticalPadding: Space.s5, horizontalPadding: Space.s6) {
            HStack(alignment: .top, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        DayTypePill(kind: .move)
                        Text("Today · Thursday April 24")
                            .font(.labelSM)
                            .tracking(1.5)
                            .foregroundStyle(Color.secondaryText)
                    }

                    Text("Ship pass 3 of Braxton edit, then prep for Tiera's birthday window.")
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
                        Text("3")
                            .font(.custom("Manrope", size: 28).weight(.light))
                            .foregroundStyle(Color.onSurface)
                        Text("of 5")
                            .font(.bodySM)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }

                    GoalsProgressBar(complete: 3, total: 5)
                        .frame(width: 120, height: 4)
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

    private let pulseProjects: [PulseProject] = [
        PulseProject(status: .review, statusLabel: "In review", title: "Braxton edit", touched: "Touched 4h ago", action: "Pass 3 → client today"),
        PulseProject(status: .draft, statusLabel: "Draft", title: "Downtown Gallery delivery", touched: "Touched yesterday", action: "Sat 12pm drop-off"),
        PulseProject(status: .scheduled, statusLabel: "Scheduled", title: "Rae reels", touched: "Touched 2 days ago", action: "Review Sat 3pm"),
        PulseProject(status: .neutral, statusLabel: "Idle", title: "Aligned suite landing", touched: "Touched 6 days ago", action: "Waiting on Tiera copy"),
        PulseProject(status: .error, statusLabel: "Blocked", title: "Studio site rebuild", touched: "Touched 9 days ago", action: "Domain DNS issue"),
        PulseProject(status: .scheduled, statusLabel: "Scheduled", title: "May newsletter", touched: "Touched today", action: "Outline due Mon")
    ]

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
                        dayHeaderRow
                        gridBody
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
            Color.clear.frame(width: 56)
            ForEach($weekDays) { $day in
                DayHeader(day: $day)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var gridBody: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time column
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(timeLabels, id: \.self) { label in
                    Text(label)
                        .font(.custom("Inter-Regular", size: 10))
                        .foregroundStyle(Color.secondaryText)
                        .frame(width: 48, height: 64, alignment: .topTrailing)
                        .padding(.trailing, Space.s2)
                }
            }
            .frame(width: 56)

            ForEach(weekDays.indices, id: \.self) { i in
                DayColumn(day: weekDays[i])
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        if i < weekDays.count - 1 {
                            Rectangle()
                                .fill(Color.outlineVariant.opacity(0.10))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .dropDestination(for: String.self) { droppedItems, location in
                        moveEvent(droppedItems: droppedItems, toDayIndex: i, atY: location.y)
                    }
            }
        }
    }

    private let timeLabels = ["8 AM", "9 AM", "10 AM", "11 AM", "12 PM", "1 PM", "2 PM", "3 PM", "4 PM"]

    private static func makeMockedWeekDays() -> [WeekDay] {
        [
            WeekDay(name: "Mon", num: "21", dayTypes: [.admin], isToday: false, events: [
                Event(top: 64, height: 96, time: "9 — 10:30 AM", title: "Inbox triage", kind: .regular),
                Event(top: 256, height: 32, time: nil, title: "Errand: post office", kind: .errand),
                Event(top: 384, height: 64, time: "2 — 3 PM", title: "Ops review", kind: .accent)
            ]),
            WeekDay(name: "Tue", num: "22", dayTypes: [.make], isToday: false, events: [
                Event(top: 128, height: 192, time: "10 AM — 1 PM", title: "Braxton edit · pass 2", kind: .regular),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Braxton sync", kind: .accent)
            ]),
            WeekDay(name: "Wed", num: "23", dayTypes: [.make], isToday: false, events: [
                Event(top: 96, height: 224, time: "9:30 AM — 1 PM", title: "Rae reels · cuts", kind: .regular),
                Event(top: 320, height: 32, time: nil, title: "Errand: lab pickup", kind: .errand)
            ]),
            WeekDay(name: "Thu · today", num: "24", dayTypes: [.move, .recover], isToday: true, events: [
                Event(top: 128, height: 128, time: "10 AM — 12 PM", title: "Braxton edit · pass 3", kind: .regular),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Braxton sync", kind: .accent)
            ], nowLineOffset: 352),
            WeekDay(name: "Fri", num: "25", dayTypes: [.make], isToday: false, events: [
                Event(top: 64, height: 192, time: "9 AM — 12 PM", title: "Studio site · DNS fix", kind: .regular),
                Event(top: 288, height: 32, time: nil, title: "Errand: dry cleaner", kind: .errand),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Braxton sync (moved)", kind: .accent)
            ]),
            WeekDay(name: "Sat", num: "26", dayTypes: [.recover], isToday: false, events: [
                Event(top: 32, height: 96, time: "8:30 — 10 AM", title: "Long run · with Tiera", kind: .regular),
                Event(top: 256, height: 32, time: "12 PM", title: "Gallery drop-off", kind: .accent),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Rae reels · review", kind: .regular)
            ]),
            WeekDay(name: "Sun", num: "27", dayTypes: [.open], isToday: false, events: [])
        ]
    }

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
                    ForEach(pendingErrands.indices, id: \.self) { i in
                        let actualIndex = errands.firstIndex(where: { $0.id == pendingErrands[i].id })!
                        ErrandRow(
                            errand: $errands[actualIndex],
                            onOpen: { editingErrandID = errands[actualIndex].id }
                        )
                        .draggable(errands[actualIndex].id.uuidString)
                        .dropDestination(for: String.self) { droppedItems, _ in
                            reorderErrands(droppedItems: droppedItems, beforeId: errands[actualIndex].id)
                        }
                        if i < pendingErrands.count - 1 {
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

    @discardableResult
    private func reorderErrands(droppedItems: [String], beforeId: UUID) -> Bool {
        guard let droppedString = droppedItems.first,
              let droppedId = UUID(uuidString: droppedString),
              let fromIndex = errands.firstIndex(where: { $0.id == droppedId }),
              let toIndex = errands.firstIndex(where: { $0.id == beforeId }),
              fromIndex != toIndex
        else { return false }
        let item = errands.remove(at: fromIndex)
        let insertIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
        errands.insert(item, at: insertIndex)
        return true
    }

    @discardableResult
    private func moveEvent(droppedItems: [String], toDayIndex: Int, atY: CGFloat) -> Bool {
        guard let droppedString = droppedItems.first,
              let droppedId = UUID(uuidString: droppedString)
        else { return false }
        // Find source day + event index
        for srcDayIndex in weekDays.indices {
            if let evtIndex = weekDays[srcDayIndex].events.firstIndex(where: { $0.id == droppedId }) {
                // Snap drop position to nearest hour (64pt = 1 hour, starting at 8 AM = top 0)
                let snappedTop = max(0, round(atY / 64) * 64)
                if srcDayIndex == toDayIndex {
                    weekDays[srcDayIndex].events[evtIndex].top = snappedTop
                } else {
                    var moved = weekDays[srcDayIndex].events.remove(at: evtIndex)
                    moved.top = snappedTop
                    weekDays[toDayIndex].events.append(moved)
                }
                return true
            }
        }
        return false
    }

    private static func makeMockedErrands() -> [Errand] {
        [
            Errand(title: "Return Amazon package",     location: "Downtown · 12 min",     daysPending: 2,  routedTo: "Mon · post office"),
            Errand(title: "Pick up film samples",      location: "Lab · 18 min",          daysPending: 5,  routedTo: "Wed · lab pickup"),
            Errand(title: "Drop off gear for cleaning",location: "Dry cleaner · 8 min",   daysPending: 9,  routedTo: "Fri · dry cleaner"),
            Errand(title: "New driver's license photo",location: "DMV · 22 min",          daysPending: 17, routedTo: nil),
            Errand(title: "Order Tiera's gift",        location: nil,                     daysPending: 4,  routedTo: nil)
        ]
    }

    // MARK: - Day Breakdown (engine-spec.md per-day narrative output)

    private var dayBreakdownSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            SectionEyebrow(text: "Day Breakdown")

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    ForEach(dayBreakdownEntries.indices, id: \.self) { i in
                        dayBreakdownRow(dayBreakdownEntries[i])
                        if i < dayBreakdownEntries.count - 1 {
                            RowSeparator()
                        }
                    }
                }
            }
        }
    }

    private let dayBreakdownEntries: [DayBreakdown] = [
        DayBreakdown(label: "Mon · Apr 21", dayType: .admin,    body: "Catch up on inbox, file Q1 expenses, prep Tue's edit block. Light errand: post office return."),
        DayBreakdown(label: "Tue · Apr 22", dayType: .make,     body: "Braxton edit pass 2 (3h block, 10–1). Client sync at 3. No errands routed."),
        DayBreakdown(label: "Wed · Apr 23", dayType: .make,     body: "Rae reels cuts (3.5h, 9:30–1). Quick lab pickup mid-afternoon."),
        DayBreakdown(label: "Thu · Apr 24", dayType: .move,     body: "Move day. Ship pass 3 of Braxton (10–12), then sync at 3. Save creative energy for Fri."),
        DayBreakdown(label: "Fri · Apr 25", dayType: .make,     body: "Studio site DNS fix (3h). Errand: dry cleaner. Braxton sync moved here from Tue."),
        DayBreakdown(label: "Sat · Apr 26", dayType: .recover,  body: "Long run with Tiera. Gallery drop-off at noon. Light review of Rae cuts in the afternoon."),
        DayBreakdown(label: "Sun · Apr 27", dayType: .open,     body: "Open day — no scheduled blocks. Reserve for prep, recovery, or family time as needed.")
    ]

    private func dayBreakdownRow(_ entry: DayBreakdown) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1_5) {
                Text(entry.label)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.onSurface)
                DayTypePill(kind: entry.dayType)
            }
            .frame(width: 132, alignment: .leading)

            Text(entry.body)
                .font(.bodyMD)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.s4)
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
                    ForEach(triageItems.indices, id: \.self) { i in
                        triageRow(triageItems[i])
                        if i < triageItems.count - 1 {
                            RowSeparator()
                        }
                    }
                }
            }
        }
    }

    private let triageItems: [TriageEntry] = [
        TriageEntry(status: .error, title: "Re: Downtown Gallery — proof timing?", meta: "Marisol · client · 2h ago"),
        TriageEntry(status: .draft, title: "Studio site DNS — propagation report", meta: "Cloudflare · 6h ago"),
        TriageEntry(status: .draft, title: "Tiera shared a Memory edit — review?", meta: "Family Memory · yesterday")
    ]

    private func triageRow(_ entry: TriageEntry) -> some View {
        Button {
            detailTriage = entry
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                StatusDot(entry.status)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(entry.title)
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text(entry.meta)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }

                Spacer(minLength: Space.s2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .padding(.top, 7)
            }
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private let proposals: [Proposal] = [
        Proposal(title: "Move Braxton sync from Tue to Fri", reasoning: "You asked earlier today. Same call link, same duration."),
        Proposal(title: "Add 1h prep block Friday morning", reasoning: "Before the moved Braxton sync — based on past pattern."),
        Proposal(title: "Snooze \"Studio site DNS\" until Mon", reasoning: "Cloudflare propagation reports settle within 24h.")
    ]

    private var visibleProposals: [Proposal] {
        proposals.filter { resolvedProposals[$0.id] == nil }
    }

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
            Button("Reset") {
                withAnimation(.easeOut(duration: 0.3)) {
                    resolvedProposals.removeAll()
                }
            }
            .buttonStyle(.plain)
            .font(.labelSM.weight(.medium))
            .foregroundStyle(Color.tertiary)
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
                    withAnimation(.easeOut(duration: 0.3)) {
                        resolvedProposals[proposal.id] = .declined
                    }
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
                    withAnimation(.easeOut(duration: 0.3)) {
                        resolvedProposals[proposal.id] = .accepted
                    }
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

private enum ProposalResolution {
    case accepted
    case declined
}

private struct DayBreakdown {
    let label: String
    let dayType: DayType
    let body: String
}

// MARK: - Alert model + kinds

private struct WeeklyRhythmAlert: Identifiable {
    let id = UUID()
    let kind: AlertKind
    let day: String
    let title: String
    let detail: String
    let actionLabel: String?
}

private enum AlertKind {
    case travel
    case commuteConflict
    case errandBatch
    case lunch

    var label: String {
        switch self {
        case .travel:          return "Travel"
        case .commuteConflict: return "Commute conflict"
        case .errandBatch:     return "Errand batch"
        case .lunch:           return "Lunch"
        }
    }

    var symbol: String {
        switch self {
        case .travel:          return "airplane"
        case .commuteConflict: return "exclamationmark.triangle.fill"
        case .errandBatch:     return "cart.fill"
        case .lunch:           return "fork.knife"
        }
    }

    var tint: Color {
        switch self {
        case .travel:          return Color.tertiary
        case .commuteConflict: return Color.brandRust
        case .errandBatch:     return Color.statusDraft
        case .lunch:           return Color.statusScheduled
        }
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

private struct ErrandDetailSheet: View {
    @Binding var errand: Errand
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                EditorialHeader(eyebrow: "Errand", title: "Edit")

                VStack(alignment: .leading, spacing: Space.s5) {
                    GhostBorderField(label: "Title", text: $errand.title)

                    GhostBorderField(
                        label: "Location",
                        text: locationBinding,
                        placeholder: "e.g. Downtown · 12 min"
                    )

                    GhostBorderField(
                        label: "Routed to",
                        text: routedBinding,
                        placeholder: "e.g. Mon · post office (leave blank for Unrouted)"
                    )

                    HStack(spacing: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("Days Pending".uppercased())
                                .font(.labelSM)
                                .tracking(1.0)
                                .foregroundStyle(Color.onSurfaceVariant)
                            Text("\(errand.daysPending)d")
                                .font(.bodyLG)
                                .foregroundStyle(Color.onSurface)
                        }

                        Spacer(minLength: Space.s4)

                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("Status".uppercased())
                                .font(.labelSM)
                                .tracking(1.0)
                                .foregroundStyle(Color.onSurfaceVariant)
                            Toggle(errand.isDone ? "Done" : "Pending", isOn: $errand.isDone)
                                .toggleStyle(.switch)
                        }
                    }
                }
                .padding(.horizontal, Space.s16)

                Spacer(minLength: Space.s4)
            }
            .padding(.vertical, Space.s8)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.surface)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var locationBinding: Binding<String> {
        Binding(
            get: { errand.location ?? "" },
            set: { errand.location = $0.isEmpty ? nil : $0 }
        )
    }

    private var routedBinding: Binding<String> {
        Binding(
            get: { errand.routedTo ?? "" },
            set: { errand.routedTo = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - Triage Detail sheet (read-only with mock actions)

private struct TriageDetailSheet: View {
    let entry: TriageEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                EditorialHeader(eyebrow: "Triage", title: entry.title)

                VStack(alignment: .leading, spacing: Space.s5) {
                    HStack(spacing: Space.s2) {
                        StatusDot(entry.status)
                        Text(entry.meta)
                            .font(.bodyMD)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }

                    DashboardCard(verticalPadding: Space.s4, horizontalPadding: Space.s4) {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("Snippet".uppercased())
                                .font(.labelSM)
                                .tracking(1.0)
                                .foregroundStyle(Color.secondaryText)
                            Text(snippetForEntry(entry))
                                .font(.bodyMD)
                                .foregroundStyle(Color.onSurface)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: Space.s2) {
                        actionPill(label: "Mark Read", symbol: "envelope.open")
                        actionPill(label: "Reply", symbol: "arrowshape.turn.up.left")
                        actionPill(label: "Snooze", symbol: "clock")
                        actionPill(label: "Archive", symbol: "archivebox")
                    }
                }
                .padding(.horizontal, Space.s16)

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

    private func snippetForEntry(_ entry: TriageEntry) -> String {
        // Mocked snippet text. Phase 5 wires the real source (Gmail/Reminders/Memory).
        "Mock preview of the source content. Phase 5 will fetch the real snippet (Gmail thread, Reminders item, Family Memory edit, etc) based on the triage source."
    }

    private func actionPill(label: String, symbol: String) -> some View {
        Button {} label: {
            HStack(spacing: Space.s1_5) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(label).font(.labelMD.weight(.medium))
            }
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(Capsule().fill(Color.surfaceContainerHigh))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Proposal Detail sheet

private struct ProposalDetailSheet: View {
    let proposal: Proposal
    let isResolved: Bool
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

                    if !isResolved {
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
                    } else {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.statusScheduled)
                            Text("Resolved — close to dismiss")
                                .font(.bodySM)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }
                    }
                }
                .padding(.horizontal, Space.s16)

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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                EditorialHeader(eyebrow: "Settings", title: "Day Types")

                Text("Define the day-type vocabulary the engine uses for your week. Each type can stack additively (a day can be both Creative and Personal). One type can be marked exclusive (Off) — picking it replaces all others on that day.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.s16)

                DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                    VStack(spacing: 0) {
                        ForEach(DayType.allCases, id: \.self) { type in
                            HStack(spacing: Space.s3) {
                                Circle()
                                    .fill(type.tint)
                                    .frame(width: 12, height: 12)

                                Text(type.label)
                                    .font(.bodyMD.weight(.medium))
                                    .foregroundStyle(Color.onSurface)

                                Spacer(minLength: Space.s2)

                                Text("Stackable")
                                    .font(.bodySM)
                                    .foregroundStyle(Color.onSurfaceVariant)
                            }
                            .padding(.vertical, Space.s3)

                            if type != DayType.allCases.last {
                                Rectangle()
                                    .fill(Color.outlineVariant.opacity(0.18))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.s16)

                Text("Phase 5 will wire this to write your day_types config so the engine reads from the same source.")
                    .font(.bodySM)
                    .foregroundStyle(Color.secondaryText)
                    .padding(.horizontal, Space.s16)

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
                StatusDot(project.status)
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

private struct PulseProject: Identifiable {
    let id = UUID()
    let status: StatusKind
    let statusLabel: String
    let title: String
    let touched: String
    let action: String
}

// MARK: - Day header + column

private struct DayHeader: View {
    @Binding var day: WeekDay

    var body: some View {
        VStack(alignment: .center, spacing: Space.s1) {
            Text(day.name)
                .font(.bodySM.weight(.medium))
                .foregroundStyle(day.isToday ? Color.tertiary : Color.onSurfaceVariant)
            Text(day.num)
                .font(.headlineMD)
                .foregroundStyle(day.isToday ? Color.tertiary : Color.onSurface)

            DayTypeEditor(types: $day.dayTypes)
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
        HStack(spacing: 3) {
            ForEach(sortedTypes, id: \.self) { type in
                DayTypePill(kind: type, removable: types.count > 1) {
                    types.remove(type)
                }
            }

            Button {
                dropdownOpen.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .frame(width: 18, height: 16)
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

    private let totalHeight: CGFloat = 576

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(day.isToday ? Color.tertiary.opacity(0.04) : Color.clear)
                .frame(height: totalHeight)

            ForEach(day.events) { event in
                EventBlock(event: event)
                    .frame(height: event.height)
                    .padding(.horizontal, 2)
                    .offset(y: event.top)
                    .draggable(event.id.uuidString)
            }

            if let nowOffset = day.nowLineOffset {
                Rectangle()
                    .fill(Color.tertiary)
                    .frame(height: 1.5)
                    .padding(.horizontal, 2)
                    .offset(y: nowOffset)
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

// MARK: - Models

private struct WeekDay: Identifiable {
    let id = UUID()
    let name: String
    let num: String
    var dayTypes: Set<DayType>
    let isToday: Bool
    var events: [Event]
    var nowLineOffset: CGFloat? = nil

    // Stable ordering of pills (so toggling doesn't reshuffle visually).
    var sortedDayTypes: [DayType] {
        DayType.allCases.filter { dayTypes.contains($0) }
    }

    // First active type, or .open as a sane fallback for downstream UI that
    // surfaces a single representation (e.g. day breakdown narrative).
    var primaryDayType: DayType {
        sortedDayTypes.first ?? .open
    }
}

// MARK: - Errand model + row

private struct Errand: Identifiable {
    let id = UUID()
    var title: String
    var location: String?
    var daysPending: Int
    var routedTo: String?
    var isDone: Bool = false
}

private struct ErrandRow: View {
    @Binding var errand: Errand
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    errand.isDone.toggle()
                }
            } label: {
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

private enum DayType: CaseIterable, Hashable {
    case make, move, recover, admin, open

    var label: String {
        switch self {
        case .make:    return "Make"
        case .move:    return "Move"
        case .recover: return "Recover"
        case .admin:   return "Admin"
        case .open:    return "Open"
        }
    }

    var tint: Color {
        switch self {
        case .make:    return Color.statusScheduled
        case .move:    return Color.tertiary
        case .recover: return Color.brandRust
        case .admin:   return Color.statusDraft
        case .open:    return Color.statusNeutral
        }
    }

    // Engine-spec.md §Day Types: an exclusive type (e.g. Off) replaces all
    // others — the dropdown hides its plus cell. None of the redesign HTML's
    // 5 mock types are exclusive; Phase 5 wires the user's real config which
    // may include Off or similar.
    var isExclusive: Bool { false }
}

private struct Event: Identifiable {
    let id = UUID()
    var top: CGFloat
    var height: CGFloat
    let time: String?
    let title: String
    let kind: EventKind
}

private enum EventKind {
    case regular, accent, errand
}

private struct TriageEntry: Identifiable, Hashable {
    let id = UUID()
    let status: StatusKind
    let title: String
    let meta: String

    static func == (lhs: TriageEntry, rhs: TriageEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct Proposal: Identifiable {
    let id = UUID()
    let title: String
    let reasoning: String
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
                StatusDot(project.status)
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
