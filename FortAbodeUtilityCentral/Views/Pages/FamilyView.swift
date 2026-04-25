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

                VStack(alignment: .leading, spacing: Space.s12) {
                    membersSection
                    healthSection
                    sharedDocsSection
                }
                .padding(.horizontal, Space.s16)
                .padding(.bottom, Space.s24)
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

    // MARK: - Shared Documents

    private var sharedDocsSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Shared Documents")

            DashboardCard(verticalPadding: Space.s6, horizontalPadding: Space.s6) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Family Memory")
                            .font(.headlineSM)
                            .foregroundStyle(Color.onSurface)

                        Text("~/iCloud/Family/Memory.md · last 5 changes")
                            .font(.bodySM)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                    .padding(.bottom, Space.s5)

                    let changes: [(date: String, summary: String, author: String)] = [
                        ("Apr 22", "Added \"Margot summer camp — Heron Lake\" with packing checklist", "Tiera"),
                        ("Apr 19", "Updated spring travel notes — Portland trip pushed to June", "Kam"),
                        ("Apr 14", "Reorganized Health section — split by member", "Tiera"),
                        ("Apr 11", "Added Aunt Mira's new address (moved March)", "Kam"),
                        ("Apr 7",  "Cleared old Q1 reminders", "Kam")
                    ]

                    ForEach(changes.indices, id: \.self) { i in
                        changelogRow(changes[i])
                        if i < changes.count - 1 {
                            RowSeparator()
                        }
                    }
                }
            }
        }
    }

    private func changelogRow(_ entry: (date: String, summary: String, author: String)) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(entry.date)
                .font(.custom("Inter-Regular", size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.secondaryText)
                .frame(width: 96, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(entry.summary)
                    .font(.bodyMD)
                    .foregroundStyle(Color.onSurface)
                Text(entry.author)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
        .padding(.vertical, Space.s4)
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

                    ForEach(recent.indices, id: \.self) { i in
                        Text(recent[i])
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
                ForEach(rows.indices, id: \.self) { i in
                    rows[i]
                    if i < rows.count - 1 {
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
                ForEach(items.indices, id: \.self) { i in
                    actionItemRow(items[i])
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

private struct ActionItem {
    let text: String
    let isDone: Bool
}
