import SwiftUI
import AlignedDesignSystem

// MARK: - EditTriageSheet
//
// 2-column edit modal for triage entries. Replaces the prior read-only
// `TriageDetailSheet` with a write-back-enabled editor. Surface 2 (Triage
// variant) from the parity-pass design package.
//
// Layout:
//   • Width 760pt
//   • Header: eyebrow "EDIT TRIAGE" + entry title + status-mapped badge
//   • Body splits 280pt left rail (read-only "Why this") + flex right column
//     with: Subject (read-only) · From (read-only) · Follow-up · Dismiss
//     reason · Disposition (chip group)
//   • Footer leading: hint text "Original thread will not be modified"
//   • Footer trailing: Cancel + Save changes
//
// Save flows through `WeeklyRhythmMutation.triageEdit(triageID:patch:)`.

struct EditTriageSheet: View {
    let entry: TriageEntry
    let reasoning: String
    let onSave: (TriagePatch) -> Void
    let onDismiss: () -> Void

    @State private var followUp: String
    @State private var dismissReason: String
    @State private var disposition: String

    init(
        entry: TriageEntry,
        reasoning: String,
        onSave: @escaping (TriagePatch) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.entry = entry
        self.reasoning = reasoning
        self.onSave = onSave
        self.onDismiss = onDismiss
        _followUp = State(initialValue: "")
        _dismissReason = State(initialValue: "")
        _disposition = State(initialValue: "")
    }

    var body: some View {
        AlignedSheet(
            eyebrow: "Edit triage",
            title: entry.title,
            badge: AnyView(statusBadge),
            idealWidth: 760,
            onDismiss: onDismiss,
            content: { editBody },
            footer: { editFooter }
        )
    }

    // MARK: - Header badge

    private var statusBadge: some View {
        let isUrgent = entry.status == .error
        return Text(isUrgent ? "URGENT" : entry.kind.label.uppercased())
            .font(.labelSM)
            .tracking(0.4)
            .foregroundStyle(isUrgent ? Color.brandRust : Color.onSurfaceVariant)
            .padding(.horizontal, Space.s2_5)
            .frame(height: 22)
            .background(
                Capsule().fill(
                    isUrgent ? Color.brandRust.opacity(0.18) : Color.surfaceContainerHigh
                )
            )
    }

    // MARK: - Body — 2 columns

    private var editBody: some View {
        HStack(alignment: .top, spacing: 0) {
            whyThisColumn
                .frame(width: 280, alignment: .topLeading)
                .padding(.horizontal, Space.s6)
                .padding(.vertical, Space.s6)
                .background(Color.surfaceContainerLow)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.outlineVariant).frame(width: 1)
                }

            VStack(alignment: .leading, spacing: Space.s4) {
                readonlyField(label: "Subject", value: entry.title)
                readonlyField(label: "From", value: entry.meta)

                GhostBorderFieldDropdown(
                    label: "Follow-up",
                    value: $followUp,
                    options: ["Tomorrow", "Tomorrow morning", "This week", "Next week", "No follow-up"]
                )

                GhostBorderField(
                    label: "Dismiss reason",
                    text: $dismissReason,
                    axis: .vertical,
                    placeholder: "Why this can be set aside",
                    lineLimit: 3...6
                )

                dispositionChips
            }
            .padding(.horizontal, Space.s7)
            .padding(.vertical, Space.s6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, -Space.s8)
        .padding(.vertical, -Space.s6)
    }

    private var whyThisColumn: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Why this".uppercased())
                .font(.labelSM)
                .tracking(2.0)
                .foregroundStyle(Color.secondaryText)

            HStack(spacing: Space.s2) {
                StatusDot(entry.status.styleKind)
                Text(entry.kind.label)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            Text(reasoning)
                .font(.bodyMD)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readonlyField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label.uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(Color.onSurfaceVariant)
            Text(value)
                .font(.bodyLG)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.4))
                .frame(height: 1)
                .padding(.top, Space.s1)
        }
    }

    private var dispositionChips: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Disposition".uppercased())
                .font(.labelSM)
                .tracking(1.0)
                .foregroundStyle(Color.onSurfaceVariant)

            HStack(spacing: Space.s2) {
                dispositionChip("reply", label: "Reply")
                dispositionChip("snooze", label: "Snooze")
                dispositionChip("dismiss", label: "Dismiss")
            }
        }
    }

    private func dispositionChip(_ value: String, label: String) -> some View {
        let isActive = (disposition == value)
        return Button {
            disposition = isActive ? "" : value
        } label: {
            Text(label)
                .font(.labelSM.weight(.medium))
                .foregroundStyle(isActive ? Color.onTertiary : Color.onSurface)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isActive ? Color.tertiary : Color.surfaceContainerHigh)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var editFooter: some View {
        Group {
            Text("Original thread will not be modified.")
                .font(.bodySM)
                .foregroundStyle(Color.secondaryText)

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

    private func buildPatch() -> TriagePatch {
        TriagePatch(
            followUp: followUp.isEmpty ? nil : followUp,
            dismissReason: dismissReason.isEmpty ? nil : dismissReason,
            disposition: disposition.isEmpty ? nil : disposition
        )
    }
}

// MARK: - TriageKind label helper

private extension TriageKind {
    var label: String {
        switch self {
        case .overdueTask:    return "Overdue task"
        case .pendingInvite:  return "Pending invite"
        case .needsTimeBlock: return "Needs time block"
        case .other:          return "Triage"
        }
    }
}
