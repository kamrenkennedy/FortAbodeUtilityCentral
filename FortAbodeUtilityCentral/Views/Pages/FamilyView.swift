import SwiftUI
import AlignedDesignSystem

// Family — the Kennedy Family hub. Members directory (Kam + Tiera only;
// Margot + Theo from the redesign were design-tool inventions, reverted to
// brief), Health Dashboard, Shared Documents (Family Memory changelog).
// Mocked content for v4.0.0; live wiring against FamilyMemoryService is a
// Phase 5 polish concern.

struct FamilyView: View {
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

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Health Dashboard")

            DashboardCard(verticalPadding: Space.s6, horizontalPadding: Space.s6) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    HealthGroup(
                        title: "Doctors",
                        rows: [
                            HealthRow(
                                title: "Dr. Mendoza",
                                meta: "Primary care · Kam",
                                trailing: "Last visit: Mar 12"
                            ),
                            HealthRow(
                                title: "Dr. Han",
                                meta: "Dermatology · Tiera",
                                trailing: "Next: May 9"
                            ),
                            HealthRow(
                                title: "Dr. Vargas",
                                meta: "Dental · Both",
                                trailing: "Due Q3"
                            )
                        ]
                    )

                    HealthGroup(
                        title: "Prescriptions",
                        rows: [
                            HealthRow(
                                status: .scheduled,
                                title: "Lisinopril 10mg",
                                meta: "Kam · 30-day",
                                trailing: "Refilled Apr 18"
                            ),
                            HealthRow(
                                status: .scheduled,
                                title: "Vitamin D 5000 IU",
                                meta: "Tiera · daily",
                                trailing: "In stock"
                            )
                        ]
                    )

                    ActionItemsGroup(
                        items: [
                            ActionItem(text: "Schedule Tiera's annual derm follow-up", isDone: true),
                            ActionItem(text: "Confirm dental cleaning Q3 · both", isDone: false),
                            ActionItem(text: "Update emergency contacts in Family Memory", isDone: false)
                        ]
                    )
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

// MARK: - Health subsections

private struct HealthGroup: View {
    let title: String
    let rows: [HealthRow]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title)
                .font(.headlineSM)
                .foregroundStyle(Color.onSurface)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                    row
                    if offset < rows.count - 1 {
                        RowSeparator()
                    }
                }
            }
        }
    }
}

private struct HealthRow: View {
    var status: StatusKind? = nil
    let title: String
    let meta: String
    let trailing: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            if let status {
                StatusDot(status)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(meta)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            Spacer(minLength: Space.s3)

            Text(trailing)
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
                .padding(.top, 2)
        }
        .padding(.vertical, Space.s3)
    }
}

private struct ActionItemsGroup: View {
    let items: [ActionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Action items")
                .font(.headlineSM)
                .foregroundStyle(Color.onSurface)

            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(items) { item in
                    actionItemRow(item)
                }
            }
        }
    }

    private func actionItemRow(_ item: ActionItem) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                .font(.system(size: 18))
                .foregroundStyle(item.isDone ? Color.tertiary : Color.outlineVariant)

            Text(item.text)
                .font(.bodyMD)
                .foregroundStyle(item.isDone ? Color.onSurfaceVariant : Color.onSurface)
                .strikethrough(item.isDone, color: Color.onSurfaceVariant)
        }
    }
}

private struct ActionItem: Identifiable {
    let id = UUID()
    let text: String
    let isDone: Bool
}
