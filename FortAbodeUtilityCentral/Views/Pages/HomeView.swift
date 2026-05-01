import SwiftUI
import AlignedDesignSystem

// Home — the v4.0.0 landing page. Editorial header, Family Vitals + Triage
// two-column, This Week at a Glance card, Marketplace Updates. Each row links
// to the destination tab via AppState.selectedDestination.

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(WeeklyRhythmStore.self) private var weeklyRhythmStore
    @Environment(ComponentListViewModel.self) private var componentList

    @State private var facts: FamilyFacts?
    @State private var lastModified: String?

    private let familyMemoryService = FamilyMemoryService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: "Dashboard", title: todaysTitle)

                VStack(alignment: .leading, spacing: Space.s10) {
                    twoColumnSection
                    thisWeekSection
                    marketplaceUpdatesSection
                }
                .padding(.horizontal, Space.s10)
                .padding(.bottom, Space.s16)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            // Load Weekly Rhythm snapshot if it hasn't been loaded yet (e.g.
            // user opened Home before Weekly Rhythm tab). The store is shared
            // across tabs so this is a no-op once any tab loads it.
            if weeklyRhythmStore.snapshot == nil {
                await weeklyRhythmStore.load(weekOffset: 0)
            }
            facts = await familyMemoryService.loadFacts()
            lastModified = await familyMemoryService.loadLastModified()
        }
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
                FamilyVitalsCard(facts: facts, lastModified: lastModified) {
                    appState.selectedDestination = .family
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: Space.s6) {
                SectionEyebrow(text: "Triage", trailing: triageTrailingLabel)
                TriageCard(items: triageItems) {
                    appState.selectedDestination = .weeklyRhythm
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var triageItems: [TriageEntry] {
        Array((weeklyRhythmStore.snapshot?.triage ?? []).prefix(3))
    }

    private var triageTrailingLabel: String? {
        let count = weeklyRhythmStore.snapshot?.triage.count ?? 0
        guard count > 0 else { return nil }
        return "\(count) need\(count == 1 ? "s" : "") attention"
    }

    // MARK: - This Week

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "This Week at a Glance")

            ThisWeekCard(
                todaysBrief: weeklyRhythmStore.snapshot?.todaysBrief,
                today: todayWeekDay,
                tomorrow: tomorrowWeekDay
            ) {
                appState.selectedDestination = .weeklyRhythm
            }
        }
    }

    private var todayWeekDay: WeekDay? {
        weeklyRhythmStore.snapshot?.weekDays.first { $0.isToday }
    }

    /// Best-effort tomorrow lookup: pick the WeekDay one position after today
    /// in the snapshot's weekDays array. nil if today isn't in the array.
    private var tomorrowWeekDay: WeekDay? {
        guard let days = weeklyRhythmStore.snapshot?.weekDays,
              let i = days.firstIndex(where: { $0.isToday }),
              i + 1 < days.count else {
            return nil
        }
        return days[i + 1]
    }

    // MARK: - Marketplace Updates

    private var marketplaceUpdatesSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Marketplace Updates", trailingLink: "View all →") {
                appState.selectedDestination = .marketplace
            }

            MarketplaceUpdatesCard(items: marketplaceUpdateItems) {
                appState.selectedDestination = .marketplace
            }
        }
    }

    private var marketplaceUpdateItems: [MarketplaceUpdateItem] {
        let updatable: [(Component, String, String)] = componentList.components.compactMap { component in
            guard case .updateAvailable(let installed, let latest) = componentList.statuses[component.id] else {
                return nil
            }
            return (component, installed, latest)
        }
        return Array(updatable.prefix(3)).map { (component, installed, latest) in
            MarketplaceUpdateItem(
                id: component.id,
                title: component.displayName,
                meta: "v\(installed) → v\(latest)"
            )
        }
    }
}

// MARK: - Family Vitals card

private struct FamilyVitalsCard: View {
    let facts: FamilyFacts?
    let lastModified: String?
    let onTap: () -> Void

    var body: some View {
        DashboardCard(isHoverable: true) {
            if let rows = vitalRows, !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        vitalRow(
                            eyebrow: row.eyebrow,
                            title: row.title,
                            subtitle: row.subtitle,
                            titleDot: row.titleDot
                        )
                        if idx < rows.count - 1 {
                            RowSeparator()
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Family vitals — tap to open Family"))
    }

    private struct VitalRow {
        let eyebrow: String
        let title: String
        let subtitle: String
        let titleDot: StatusKind?
    }

    private var vitalRows: [VitalRow]? {
        guard let facts else { return nil }
        var rows: [VitalRow] = []

        if let healthPlans = facts.insurance?.health, !healthPlans.isEmpty {
            let summary: String
            if healthPlans.count == 1, let name = healthPlans.first?.planName {
                summary = name
            } else {
                summary = "\(healthPlans.count) plan\(healthPlans.count == 1 ? "" : "s")"
            }
            let subtitle: String
            if let monthly = healthPlans.first?.monthlyPremium {
                subtitle = "\(monthly)/mo"
            } else if let carrier = healthPlans.first?.carrier {
                subtitle = carrier
            } else {
                subtitle = "Plan details on file"
            }
            rows.append(VitalRow(
                eyebrow: "Health Insurance",
                title: summary,
                subtitle: subtitle,
                titleDot: .scheduled
            ))
        }

        if let members = facts.household?.members, !members.isEmpty {
            let subtitle: String
            if let pets = facts.household?.pets, !pets.isEmpty {
                subtitle = "\(members.count) people · \(pets.count) pet\(pets.count == 1 ? "" : "s")"
            } else {
                subtitle = "\(members.count) member\(members.count == 1 ? "" : "s")"
            }
            rows.append(VitalRow(
                eyebrow: "Household",
                title: members.joined(separator: " · "),
                subtitle: subtitle,
                titleDot: nil
            ))
        }

        if let lastModified {
            rows.append(VitalRow(
                eyebrow: "Shared Docs",
                title: "Family Memory",
                subtitle: "Updated \(lastModified)",
                titleDot: nil
            ))
        }

        return rows
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Family Memory")
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)
            Text("Not set up yet — tap to open Family.")
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .padding(.vertical, Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func vitalRow(
        eyebrow: String,
        title: String,
        subtitle: String,
        titleDot: StatusKind? = nil
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
        }
        .padding(.vertical, Space.s4)
    }
}

// MARK: - Triage card

private struct TriageCard: View {
    let items: [TriageEntry]
    let onTap: () -> Void

    var body: some View {
        DashboardCard(isHoverable: true) {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("No triage items this week")
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text("Tap to open Weekly Rhythm")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(.vertical, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        triageRow(item)
                        if item.id != items.last?.id {
                            RowSeparator()
                        }
                    }
                }
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Triage — tap to open Weekly Rhythm"))
    }

    private func triageRow(_ item: TriageEntry) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            StatusDot(item.status.styleKind)
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

// MARK: - This Week card

private struct ThisWeekCard: View {
    let todaysBrief: TodaysBrief?
    let today: WeekDay?
    let tomorrow: WeekDay?
    let onTap: () -> Void

    var body: some View {
        DashboardCard(isHoverable: true) {
            if todaysBrief == nil && today == nil {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Run the engine to generate your brief")
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text("Tap to open Weekly Rhythm")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(.vertical, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: Space.s5) {
                    if let todaysBrief {
                        briefHeader(todaysBrief)
                    }

                    HStack(alignment: .top, spacing: Space.s8) {
                        if let today {
                            dayColumn(title: "Today", day: today, narrative: todaysBrief?.narrative)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        if today != nil && tomorrow != nil {
                            Rectangle()
                                .fill(Color.outlineVariant.opacity(0.20))
                                .frame(width: 1)
                        }

                        if let tomorrow {
                            dayColumn(title: "Tomorrow", day: tomorrow, narrative: nil)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .padding(.vertical, Space.s2)
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("This week at a glance — tap to open Weekly Rhythm"))
    }

    @ViewBuilder
    private func briefHeader(_ brief: TodaysBrief) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            dayTypePill(brief.dayType)
            Text(brief.label)
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
            Spacer(minLength: Space.s2)
            if brief.weekGoalsTotal > 0 {
                Text("Goals \(brief.weekGoalsComplete)/\(brief.weekGoalsTotal)")
                    .font(.bodySM)
                    .monospacedDigit()
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
    }

    private func dayTypePill(_ type: WRDayType) -> some View {
        Text(type.label)
            .font(.labelSM.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Color.onSurface)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s1)
            .background(
                Capsule().fill(Color.surfaceContainer)
            )
            .overlay(
                Capsule().stroke(Color.outlineVariant, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func dayColumn(title: String, day: WeekDay, narrative: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headlineMD)
                    .foregroundStyle(Color.onSurface)
                Spacer(minLength: Space.s2)
                Text(day.dayMeta)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            if let narrative, !narrative.isEmpty {
                Text(narrative)
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if day.events.isEmpty {
                Text("No events")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            } else {
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(day.events.prefix(3)) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: WREvent) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(event.time ?? "")
                .font(.custom("Inter-Regular", size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.secondaryText)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(event.title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
            }
        }
    }
}

private extension WeekDay {
    /// "Friday · Make" style label — uses the day's first/primary day type.
    var dayMeta: String {
        let typeLabel = primaryDayType.label
        // `name` is the short form ("Mon"). Try to expand to full weekday name.
        let full = WeekDay.fullWeekdayName(from: name) ?? name
        return "\(full) · \(typeLabel)"
    }

    private static func fullWeekdayName(from short: String) -> String? {
        switch short.lowercased().prefix(3) {
        case "mon": return "Monday"
        case "tue": return "Tuesday"
        case "wed": return "Wednesday"
        case "thu": return "Thursday"
        case "fri": return "Friday"
        case "sat": return "Saturday"
        case "sun": return "Sunday"
        default:    return nil
        }
    }
}

// MARK: - Marketplace Updates card

private struct MarketplaceUpdateItem: Identifiable {
    let id: String
    let title: String
    let meta: String
}

private struct MarketplaceUpdatesCard: View {
    let items: [MarketplaceUpdateItem]
    let onTap: () -> Void

    var body: some View {
        DashboardCard(isHoverable: true) {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("All components up to date")
                        .font(.bodyMD.weight(.medium))
                        .foregroundStyle(Color.onSurface)
                    Text("No updates pending")
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
                .padding(.vertical, Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        updateRow(item)
                        if item.id != items.last?.id {
                            RowSeparator()
                        }
                    }
                }
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Marketplace updates — tap to open Marketplace"))
    }

    private func updateRow(_ item: MarketplaceUpdateItem) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Circle()
                .fill(Color.statusDraft)
                .frame(width: 8, height: 8)
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

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.top, 5)
        }
        .padding(.vertical, Space.s3)
    }
}
