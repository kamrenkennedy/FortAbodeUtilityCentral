import SwiftUI
import AlignedDesignSystem

// Home — the v4.0.0 landing page. Editorial header, Family Vitals + Triage
// two-column, This Week at a Glance card, Marketplace Pulse. Each row links
// to the destination tab via AppState.selectedDestination. Mocked data for
// v4.0.0; live wiring is a Phase 5 concern.

struct HomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: "Family Dashboard", title: todaysTitle)

                VStack(alignment: .leading, spacing: Space.s16) {
                    twoColumnSection
                    thisWeekSection
                    marketplacePulseSection
                }
                .padding(.horizontal, Space.s16)
                .padding(.bottom, Space.s24)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var todaysTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMMM d"
        return "Today, \(formatter.string(from: Date()))"
    }

    // MARK: - Two-column: Family Vitals + Triage

    private var twoColumnSection: some View {
        HStack(alignment: .top, spacing: Space.s8) {
            VStack(alignment: .leading, spacing: Space.s6) {
                SectionEyebrow(text: "Family Vitals")
                FamilyVitalsCard {
                    appState.selectedDestination = .family
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: Space.s6) {
                SectionEyebrow(text: "Triage", trailing: "3 need attention")
                TriageCard {
                    appState.selectedDestination = .weeklyRhythm
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - This Week

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "This Week at a Glance")

            ThisWeekCard {
                appState.selectedDestination = .weeklyRhythm
            }
        }
    }

    // MARK: - Marketplace Pulse

    private var marketplacePulseSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Marketplace Pulse", trailingLink: "View all →") {
                appState.selectedDestination = .marketplace
            }

            MarketplacePulseCard {
                appState.selectedDestination = .marketplace
            }
        }
    }
}

// MARK: - Family Vitals card

private struct FamilyVitalsCard: View {
    let onTap: () -> Void

    var body: some View {
        DashboardCard(isHoverable: true) {
            VStack(spacing: 0) {
                vitalRow(
                    eyebrow: "Next Family Event",
                    title: "Tiera's birthday",
                    subtitle: "Tuesday May 6",
                    trailingNumber: "12",
                    trailingUnit: "days"
                )
                RowSeparator()
                vitalRow(
                    eyebrow: "Health Alerts",
                    title: "All clear",
                    subtitle: "No prescription refills due",
                    titleDot: .scheduled
                )
                RowSeparator()
                vitalRow(
                    eyebrow: "Shared Docs",
                    title: "Family Memory",
                    subtitle: "Updated 2 days ago by Tiera"
                )
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Family vitals — tap to open Family"))
    }

    @ViewBuilder
    private func vitalRow(
        eyebrow: String,
        title: String,
        subtitle: String,
        titleDot: StatusKind? = nil,
        trailingNumber: String? = nil,
        trailingUnit: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(eyebrow.uppercased())
                    .font(.labelSM)
                    .tracking(1.5)
                    .foregroundStyle(Color.secondaryText)

                HStack(spacing: Space.s2) {
                    if let titleDot {
                        StatusDot(titleDot)
                    }
                    Text(title)
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                }
                .padding(.top, 2)

                Text(subtitle)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            Spacer(minLength: Space.s4)

            if let trailingNumber, let trailingUnit {
                HStack(alignment: .firstTextBaseline, spacing: Space.s1_5) {
                    Text(trailingNumber)
                        .font(.custom("Manrope", size: 32).weight(.light))
                        .foregroundStyle(Color.onSurface)
                    Text(trailingUnit)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
            }
        }
        .padding(.vertical, Space.s4)
    }
}

// MARK: - Triage card

private struct TriageCard: View {
    let onTap: () -> Void

    private let items: [TriageItem] = [
        TriageItem(status: .error, title: "Re: Downtown Gallery — proof timing?", meta: "Marisol · client · 2h ago"),
        TriageItem(status: .draft, title: "Studio site DNS — propagation report", meta: "Cloudflare · 6h ago"),
        TriageItem(status: .draft, title: "Tiera shared a Memory edit — review?", meta: "Family Memory · yesterday")
    ]

    var body: some View {
        DashboardCard(isHoverable: true) {
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    triageRow(items[i])
                    if i < items.count - 1 {
                        RowSeparator()
                    }
                }
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Triage — tap to open Weekly Rhythm"))
    }

    private func triageRow(_ item: TriageItem) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            StatusDot(item.status)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(item.title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)

                Text(item.meta)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            Spacer(minLength: Space.s2)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.top, 5)
        }
        .padding(.vertical, Space.s3)
    }
}

private struct TriageItem {
    let status: StatusKind
    let title: String
    let meta: String
}

// MARK: - This Week card

private struct ThisWeekCard: View {
    let onTap: () -> Void

    var body: some View {
        DashboardCard(isHoverable: true) {
            HStack(alignment: .top, spacing: Space.s8) {
                dayColumn(
                    title: "Today",
                    dayMeta: "Friday · Make",
                    events: [
                        ("10:00 AM", "Braxton edit — pass 3", "Make block · 2h"),
                        ("3:00 PM", "Braxton sync", "Recurring · video call"),
                        ("7:00 PM", "Call Mom", "Reminder")
                    ]
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Rectangle()
                    .fill(Color.outlineVariant.opacity(0.20))
                    .frame(width: 1)

                dayColumn(
                    title: "Tomorrow",
                    dayMeta: "Saturday · Recover",
                    events: [
                        ("9:30 AM", "Long run with Tiera", "Riverside loop"),
                        ("12:00 PM", "Downtown Gallery delivery", "Drop-off · 30 min"),
                        ("3:00 PM", "Rae reels — review cuts", "Solo · 1h")
                    ]
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.vertical, Space.s2)
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("This week at a glance — tap to open Weekly Rhythm"))
    }

    @ViewBuilder
    private func dayColumn(title: String, dayMeta: String, events: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headlineMD)
                    .foregroundStyle(Color.onSurface)
                Spacer(minLength: Space.s2)
                Text(dayMeta)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(events.indices, id: \.self) { i in
                    let (time, title, meta) = events[i]
                    eventRow(time: time, title: title, meta: meta)
                }
            }
        }
    }

    private func eventRow(time: String, title: String, meta: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(time)
                .font(.custom("Inter-Regular", size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.secondaryText)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(meta)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
    }
}

// MARK: - Marketplace Pulse card

private struct MarketplacePulseCard: View {
    let onTap: () -> Void

    private let items: [PulseItem] = [
        PulseItem(kind: .update, title: "2 updates ready", meta: "Gmail v1.9.0 · GitHub v2.2.0", date: "Today"),
        PulseItem(kind: .new, title: "Figma added to Marketplace", meta: "New · design files, comments, prototypes", date: "Yesterday"),
        PulseItem(kind: .installed, title: "Linear installed", meta: "By Kam · connected to Kam Studios workspace", date: "2d ago")
    ]

    var body: some View {
        DashboardCard(isHoverable: true) {
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    pulseRow(items[i])
                    if i < items.count - 1 {
                        RowSeparator()
                    }
                }
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Marketplace pulse — tap to open Marketplace"))
    }

    private func pulseRow(_ item: PulseItem) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            pulseDot(item.kind)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(item.title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(item.meta)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            Spacer(minLength: Space.s3)

            Text(item.date)
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.top, 2)
        }
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private func pulseDot(_ kind: PulseKind) -> some View {
        switch kind {
        case .update:
            Circle().fill(Color.statusDraft).frame(width: 8, height: 8)
        case .new:
            Circle().fill(Color.brandRust).frame(width: 8, height: 8)
        case .installed:
            Circle().fill(Color.statusScheduled).frame(width: 8, height: 8)
        }
    }
}

private enum PulseKind {
    case update
    case new
    case installed
}

private struct PulseItem {
    let kind: PulseKind
    let title: String
    let meta: String
    let date: String
}
