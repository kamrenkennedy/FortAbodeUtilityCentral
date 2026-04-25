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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: "Week 17", title: "April 21 — 27")

                VStack(alignment: .leading, spacing: Space.s12) {
                    todaysBriefSection
                    projectPulseSection
                    weekGridSection
                    errandsSection
                    triageAndProposalsSection
                    familyMessagesSection
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
            SectionEyebrow(text: "Week Grid", trailing: "8 AM — 6 PM · drag to reschedule")

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
            }
        }
    }

    private let timeLabels = ["8 AM", "9 AM", "10 AM", "11 AM", "12 PM", "1 PM", "2 PM", "3 PM", "4 PM"]

    private static func makeMockedWeekDays() -> [WeekDay] {
        [
            WeekDay(name: "Mon", num: "21", dayType: .admin, isToday: false, events: [
                Event(top: 64, height: 96, time: "9 — 10:30 AM", title: "Inbox triage", kind: .regular),
                Event(top: 256, height: 32, time: nil, title: "Errand: post office", kind: .errand),
                Event(top: 384, height: 64, time: "2 — 3 PM", title: "Ops review", kind: .accent)
            ]),
            WeekDay(name: "Tue", num: "22", dayType: .make, isToday: false, events: [
                Event(top: 128, height: 192, time: "10 AM — 1 PM", title: "Braxton edit · pass 2", kind: .regular),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Braxton sync", kind: .accent)
            ]),
            WeekDay(name: "Wed", num: "23", dayType: .make, isToday: false, events: [
                Event(top: 96, height: 224, time: "9:30 AM — 1 PM", title: "Rae reels · cuts", kind: .regular),
                Event(top: 320, height: 32, time: nil, title: "Errand: lab pickup", kind: .errand)
            ]),
            WeekDay(name: "Thu · today", num: "24", dayType: .move, isToday: true, events: [
                Event(top: 128, height: 128, time: "10 AM — 12 PM", title: "Braxton edit · pass 3", kind: .regular),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Braxton sync", kind: .accent)
            ], nowLineOffset: 352),
            WeekDay(name: "Fri", num: "25", dayType: .make, isToday: false, events: [
                Event(top: 64, height: 192, time: "9 AM — 12 PM", title: "Studio site · DNS fix", kind: .regular),
                Event(top: 288, height: 32, time: nil, title: "Errand: dry cleaner", kind: .errand),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Braxton sync (moved)", kind: .accent)
            ]),
            WeekDay(name: "Sat", num: "26", dayType: .recover, isToday: false, events: [
                Event(top: 32, height: 96, time: "8:30 — 10 AM", title: "Long run · with Tiera", kind: .regular),
                Event(top: 256, height: 32, time: "12 PM", title: "Gallery drop-off", kind: .accent),
                Event(top: 448, height: 64, time: "3 — 4 PM", title: "Rae reels · review", kind: .regular)
            ]),
            WeekDay(name: "Sun", num: "27", dayType: .open, isToday: false, events: [])
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
                        ErrandRow(errand: $errands[actualIndex])
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

    private static func makeMockedErrands() -> [Errand] {
        [
            Errand(title: "Return Amazon package",     location: "Downtown · 12 min",     daysPending: 2,  routedTo: "Mon · post office"),
            Errand(title: "Pick up film samples",      location: "Lab · 18 min",          daysPending: 5,  routedTo: "Wed · lab pickup"),
            Errand(title: "Drop off gear for cleaning",location: "Dry cleaner · 8 min",   daysPending: 9,  routedTo: "Fri · dry cleaner"),
            Errand(title: "New driver's license photo",location: "DMV · 22 min",          daysPending: 17, routedTo: nil),
            Errand(title: "Order Tiera's gift",        location: nil,                     daysPending: 4,  routedTo: nil)
        ]
    }

    // MARK: - Family Messages (engine-spec.md Step 6c — Claude-proposed messages)

    private var familyMessagesSection: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Family Messages".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Spacer(minLength: Space.s2)
                Text("\(visibleFamilyMessages.count) proposed")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            DashboardCard(verticalPadding: Space.s6, horizontalPadding: Space.s6) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    if visibleFamilyMessages.isEmpty {
                        familyMessagesEmpty
                    } else {
                        ForEach(visibleFamilyMessages) { message in
                            familyMessageRow(message)
                            if message.id != visibleFamilyMessages.last?.id {
                                RowSeparator()
                            }
                        }
                    }
                }
            }
        }
    }

    @State private var resolvedFamilyMessages: [UUID: FamilyMessageResolution] = [:]

    private let familyMessages: [FamilyMessageProposal] = [
        FamilyMessageProposal(
            recipient: "Tiera",
            reasoning: "Tiera has 3 events Thursday and a long run scheduled Sat morning.",
            text: "Heads up — working late tonight on Braxton pass 3, dinner around 7? Want me to grab something?"
        ),
        FamilyMessageProposal(
            recipient: "Tiera",
            reasoning: "Birthday in 12 days; gift errand still unrouted.",
            text: "What's your top wish for the birthday weekend? Trying to plan the day around what'll feel best for you."
        )
    ]

    private var visibleFamilyMessages: [FamilyMessageProposal] {
        familyMessages.filter { resolvedFamilyMessages[$0.id] == nil }
    }

    private var familyMessagesEmpty: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.onSurfaceVariant)
            Text("No proposed messages right now")
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
            Button("Reset") {
                withAnimation(.easeOut(duration: 0.3)) {
                    resolvedFamilyMessages.removeAll()
                }
            }
            .buttonStyle(.plain)
            .font(.labelSM.weight(.medium))
            .foregroundStyle(Color.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
    }

    private func familyMessageRow(_ message: FamilyMessageProposal) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.tertiary)
                Text("Suggest sending to \(message.recipient)".uppercased())
                    .font(.labelSM)
                    .tracking(1.5)
                    .foregroundStyle(Color.tertiary)
            }

            Text(message.text)
                .font(.bodyMD)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                        .fill(Color.surfaceContainer)
                )

            HStack {
                Text(message.reasoning)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Space.s2)

                HStack(spacing: Space.s1) {
                    Button {
                        withAnimation(.easeOut(duration: 0.3)) {
                            resolvedFamilyMessages[message.id] = .skipped
                        }
                    } label: {
                        Text("Skip")
                            .font(.labelMD.weight(.medium))
                            .foregroundStyle(Color.onSurfaceVariant)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s1_5)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeOut(duration: 0.3)) {
                            resolvedFamilyMessages[message.id] = .sent
                        }
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .font(.labelMD.weight(.semibold))
                            .foregroundStyle(Color.onPrimary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s1_5)
                            .background(
                                Capsule()
                                    .fill(Color.primaryFill)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Space.s2)
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

            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s3)
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
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(proposal.title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(proposal.reasoning)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

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

private struct FamilyMessageProposal: Identifiable {
    let id = UUID()
    let recipient: String
    let reasoning: String
    let text: String
}

private enum FamilyMessageResolution {
    case sent
    case skipped
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

            Menu {
                ForEach(DayType.allCases, id: \.self) { type in
                    Button {
                        day.dayType = type
                    } label: {
                        if type == day.dayType {
                            Label(type.label, systemImage: "checkmark")
                        } else {
                            Text(type.label)
                        }
                    }
                }
            } label: {
                DayTypePill(kind: day.dayType)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("Change day type")
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

private struct DayTypePill: View {
    let kind: DayType

    var body: some View {
        Text(kind.label)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(kind.tint)
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
    var dayType: DayType
    let isToday: Bool
    let events: [Event]
    var nowLineOffset: CGFloat? = nil
}

// MARK: - Errand model + row

private struct Errand: Identifiable {
    let id = UUID()
    let title: String
    let location: String?
    let daysPending: Int
    let routedTo: String?
    var isDone: Bool = false
}

private struct ErrandRow: View {
    @Binding var errand: Errand

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

            Spacer(minLength: Space.s2)

            DaysPendingPill(days: errand.daysPending)
                .padding(.top, 2)
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
}

private struct Event: Identifiable {
    let id = UUID()
    let top: CGFloat
    let height: CGFloat
    let time: String?
    let title: String
    let kind: EventKind
}

private enum EventKind {
    case regular, accent, errand
}

private struct TriageEntry {
    let status: StatusKind
    let title: String
    let meta: String
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
