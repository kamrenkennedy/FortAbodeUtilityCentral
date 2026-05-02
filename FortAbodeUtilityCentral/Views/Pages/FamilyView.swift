import SwiftUI
import AlignedDesignSystem

// Family — the Kennedy Family hub. Members directory (Kam + Tiera only;
// Margot + Theo from the redesign were design-tool inventions, reverted to
// brief), Health Dashboard, Shared Documents (Family Memory changelog).
// Mocked content for v4.0.0; live wiring against FamilyMemoryService is a
// Phase 5 polish concern.

struct FamilyView: View {

    @State private var healthPlan: HealthInsurancePlan?
    @State private var hasLoadedFacts = false

    private let familyMemoryService = FamilyMemoryService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: "Kennedy Family", title: "Family")

                VStack(alignment: .leading, spacing: Space.s8) {
                    membersSection
                    healthSection
                    familyMemorySection
                }
                .padding(.horizontal, Space.s10)
                .padding(.bottom, Space.s16)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            let facts = await familyMemoryService.loadFacts()
            healthPlan = facts?.insurance?.health?.first
            hasLoadedFacts = true
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Members")

            HStack(alignment: .top, spacing: Space.s4) {
                FamilyMemberCard(
                    initial: "K",
                    name: "Kam",
                    recent: [
                        "Pushed Braxton edit pass 2 to client · 4h ago",
                        "Updated Family Memory · \"Spring travel notes\" · Tue"
                    ]
                )
                .frame(maxWidth: .infinity)

                FamilyMemberCard(
                    initial: "T",
                    name: "Tiera",
                    recent: [
                        "Edited Family Memory · \"Margot summer camp\" · 2 days ago",
                        "RSVP'd to Saturday long run · Wed"
                    ]
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Health Dashboard

    @ViewBuilder
    private var healthSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Health Dashboard")

            if let plan = healthPlan {
                FamilyHealthSections(plan: plan)
            } else if hasLoadedFacts {
                DashboardCard(verticalPadding: Space.s6, horizontalPadding: Space.s6) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("No health plan in Family Memory yet")
                            .font(.bodyMD.weight(.medium))
                            .foregroundStyle(Color.onSurface)
                        Text("Add an insurance plan via a Claude family-memory session — the dashboard reads from facts.json#insurance.health.")
                            .font(.bodySM)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Family Memory (sections grid)

    private var familyMemorySection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Family Memory".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Spacer(minLength: Space.s2)
                Text("~/iCloud/Family/Memory.md")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: Space.s4)],
                spacing: Space.s4
            ) {
                ForEach(memorySections) { section in
                    FamilyMemoryCard(section: section)
                }
            }
        }
    }

    private let memorySections: [MemorySection] = [
        MemorySection(symbol: "house.fill",          title: "Household",            subtitle: "Address, mortgage, utilities, maintenance", lastUpdated: "Updated Apr 19 · Kam"),
        MemorySection(symbol: "car.fill",            title: "Vehicles",             subtitle: "Registrations, services, insurance",        lastUpdated: "Updated Apr 11 · Kam"),
        MemorySection(symbol: "dollarsign.circle.fill", title: "Finance",           subtitle: "Joint accounts, recurring bills, budgets",  lastUpdated: "No facts yet"),
        MemorySection(symbol: "person.2.fill",       title: "Contacts",             subtitle: "Family, emergency, services",                lastUpdated: "Updated Apr 11 · Kam"),
        MemorySection(symbol: "airplane",            title: "Travel",               subtitle: "Trips, passports, packing notes",            lastUpdated: "Updated Apr 19 · Kam"),
        MemorySection(symbol: "calendar",            title: "Calendar",             subtitle: "Recurring family events, anniversaries",     lastUpdated: "No facts yet"),
        MemorySection(symbol: "heart.square.fill",   title: "Wedding & Anniversary",subtitle: "Vendors, traditions, photos",                lastUpdated: "No facts yet"),
        MemorySection(symbol: "questionmark.bubble", title: "Open Questions",       subtitle: "To discuss together",                        lastUpdated: "No facts yet")
    ]
}

private struct MemorySection: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let subtitle: String
    let lastUpdated: String
}

private struct FamilyMemoryCard: View {
    let section: MemorySection

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: section.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Color.surfaceContainerHigh)
                    )

                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.surfaceContainerHigh)
                    )
                    .opacity(isHovering ? 1 : 0)
                    .help("Add a fact (manual or via chat)")
            }

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(section.title)
                    .font(.headlineSM)
                    .foregroundStyle(Color.onSurface)

                Text(section.subtitle)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            Text(section.lastUpdated)
                .font(.labelSM)
                .foregroundStyle(Color.secondaryText)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color.cardBackground)
        )
        .offset(y: isHovering ? -2 : 0)
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .whisperShadow()
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Family Member card

private struct FamilyMemberCard: View {
    let initial: String
    let name: String
    let recent: [String]

    var body: some View {
        DashboardCard(verticalPadding: Space.s5, horizontalPadding: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s5) {
                HStack(spacing: Space.s4) {
                    Circle()
                        .fill(Color.tertiary)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(initial)
                                .font(.headlineMD)
                                .foregroundStyle(Color.onTertiary)
                        )

                    Text(name)
                        .font(.headlineMD)
                        .foregroundStyle(Color.onSurface)

                    Spacer(minLength: Space.s2)
                }

                Rectangle()
                    .fill(Color.outlineVariant.opacity(0.18))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: Space.s1_5) {
                    Text("Recent".uppercased())
                        .font(.labelSM)
                        .tracking(1.5)
                        .foregroundStyle(Color.secondaryText)

                    ForEach(Array(recent.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.bodyMD)
                            .foregroundStyle(Color.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

