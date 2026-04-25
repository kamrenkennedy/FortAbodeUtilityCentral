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
    @State private var checkedProposals: Set<UUID> = []
    @State private var weekOffset: Int = 0
    @State private var range: WeeklyRhythmRange = .week
    @State private var selectedProjectId: UUID?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EditorialHeader(eyebrow: "Week 17", title: "April 21 — 27")

                    VStack(alignment: .leading, spacing: Space.s12) {
                        projectPulseSection
                        weekGridSection
                        triageAndProposalsSection
                    }
                    .padding(.horizontal, Space.s16)
                    .padding(.bottom, checkedProposals.isEmpty ? Space.s24 : 96)
                }
                .frame(maxWidth: 1184, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if !checkedProposals.isEmpty {
                ConfirmBar(count: checkedProposals.count) {
                    checkedProposals.removeAll()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.3), value: checkedProposals.isEmpty)
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
                    dayHeaderRow
                    gridBody
                }
            }
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
            ForEach(weekDays.indices, id: \.self) { i in
                DayHeader(day: weekDays[i])
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

    private var weekDays: [WeekDay] {
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
                    Text("\(proposals.count) new")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }

                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(proposals) { proposal in
                        proposalRow(proposal)
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

    private func proposalRow(_ proposal: Proposal) -> some View {
        let isChecked = checkedProposals.contains(proposal.id)
        return HStack(alignment: .top, spacing: Space.s3_5) {
            Button {
                if isChecked {
                    checkedProposals.remove(proposal.id)
                } else {
                    checkedProposals.insert(proposal.id)
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(isChecked ? Color.tertiary : Color.outlineVariant, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(isChecked ? Color.tertiary : Color.clear)
                        )
                        .frame(width: 18, height: 18)

                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.onTertiary)
                    }
                }
                .padding(.top, 2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(proposal.title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(proposal.reasoning)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// Workaround: Space doesn't define s3_5 (14pt). Use s4 (16) where 14 was specced.
// Kept as a private alias to flag the spec drift if it bites later.
private extension Space {
    static let s3_5: CGFloat = Space.s4
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
    let day: WeekDay

    var body: some View {
        VStack(alignment: .center, spacing: Space.s1) {
            Text(day.name)
                .font(.bodySM.weight(.medium))
                .foregroundStyle(day.isToday ? Color.tertiary : Color.onSurfaceVariant)
            Text(day.num)
                .font(.headlineMD)
                .foregroundStyle(day.isToday ? Color.tertiary : Color.onSurface)
            DayTypePill(kind: day.dayType)
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

private struct WeekDay {
    let name: String
    let num: String
    let dayType: DayType
    let isToday: Bool
    let events: [Event]
    var nowLineOffset: CGFloat? = nil
}

private enum DayType {
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

// MARK: - Confirm bar

private struct ConfirmBar: View {
    let count: Int
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: Space.s4) {
            Text("\(count) selected")
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)

            Spacer()

            Button("Cancel") {
                onApply()
            }
            .buttonStyle(.plain)
            .font(.labelLG)
            .foregroundStyle(Color.onSurfaceVariant)

            Button {
                onApply()
            } label: {
                Text("Apply \(count) proposal\(count == 1 ? "" : "s")")
                    .font(.labelLG.weight(.semibold))
                    .foregroundStyle(Color.onPrimary)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2_5)
                    .background(
                        Capsule()
                            .fill(Color.primaryFill)
                    )
            }
            .buttonStyle(.plain)
            .ctaShadow()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(
            Color.surfaceContainerLowest
                .overlay(Rectangle().fill(Color.outlineVariant.opacity(0.18)).frame(height: 1), alignment: .top)
        )
    }
}
