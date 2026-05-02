import SwiftUI
import AlignedDesignSystem

// MARK: - EditEventSheet
//
// 2-column edit modal for events on the week grid. Surface 2 from the
// parity-pass design package (.claude/design/v4-parity-pass/README.md §2).
//
// Layout:
//   • Width 760pt
//   • Header: eyebrow "EDIT EVENT" + event title + day-type badge + close X
//   • Body splits 280pt left rail (read-only "Why this") + flex right column
//     (form fields)
//   • Footer leading: "Delete event" (appError text button)
//   • Footer trailing: Cancel + Save changes
//
// Save flows through `WeeklyRhythmMutation.eventEdit(eventID:patch:)`.
// The patch carries only fields that actually changed.
//
// Reasoning text on the left rail comes from the parent — engine emits it
// via a future field; for now the parent passes a placeholder.

struct EditEventSheet: View {
    let event: WREvent
    let reasoning: String
    let onSave: (EventPatch) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var dayOfWeek: String
    @State private var typeTag: String
    @State private var startTime: String
    @State private var duration: String
    @State private var notes: String

    init(
        event: WREvent,
        reasoning: String,
        onSave: @escaping (EventPatch) -> Void,
        onDelete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.event = event
        self.reasoning = reasoning
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        _title = State(initialValue: event.title)
        _dayOfWeek = State(initialValue: "")
        _typeTag = State(initialValue: "Make")
        _startTime = State(initialValue: Self.formatHour(event.startHour))
        _duration = State(initialValue: Self.formatDuration(event.endHour - event.startHour))
        _notes = State(initialValue: "")
    }

    var body: some View {
        AlignedSheet(
            eyebrow: "Edit event",
            title: title.isEmpty ? "Untitled event" : title,
            badge: AnyView(typeBadge),
            idealWidth: 760,
            onDismiss: onDismiss,
            content: { editBody },
            footer: { editFooter }
        )
    }

    // MARK: - Header badge

    private var typeBadge: some View {
        Text(typeTag.uppercased())
            .font(.labelSM)
            .tracking(0.4)
            .foregroundStyle(Color.statusScheduled)
            .padding(.horizontal, Space.s2_5)
            .frame(height: 22)
            .background(
                Capsule().fill(Color.statusScheduled.opacity(0.18))
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
                GhostBorderField(label: "Title", text: $title)

                HStack(alignment: .top, spacing: Space.s3) {
                    GhostBorderFieldDropdown(
                        label: "Day",
                        value: $dayOfWeek,
                        options: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
                        placeholder: "Select day"
                    )
                    GhostBorderFieldDropdown(
                        label: "Type",
                        value: $typeTag,
                        options: ["Make", "Move", "Recover", "Admin"]
                    )
                }

                HStack(alignment: .top, spacing: Space.s3) {
                    GhostBorderFieldDropdown(
                        label: "Start",
                        value: $startTime,
                        options: Self.startTimeOptions
                    )
                    GhostBorderFieldDropdown(
                        label: "Duration",
                        value: $duration,
                        options: Self.durationOptions
                    )
                }

                GhostBorderField(
                    label: "Notes",
                    text: $notes,
                    axis: .vertical,
                    placeholder: "Optional context",
                    lineLimit: 3...6
                )
            }
            .padding(.horizontal, Space.s7)
            .padding(.vertical, Space.s6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, -Space.s8)   // cancel AlignedSheet's body padding
        .padding(.vertical, -Space.s6)
    }

    private var whyThisColumn: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Why this".uppercased())
                .font(.labelSM)
                .tracking(2.0)
                .foregroundStyle(Color.secondaryText)

            Text(reasoning)
                .font(.bodyMD)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Color.outlineVariant).frame(height: 1)
                .padding(.vertical, Space.s1)

            Text("Engine confidence — derived from recent week patterns")
                .font(.bodySM)
                .foregroundStyle(Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var editFooter: some View {
        Group {
            Button("Delete event") {
                onDelete()
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appError)
            .font(.labelLG)

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

    private func buildPatch() -> EventPatch {
        EventPatch(
            title: title != event.title ? title : nil,
            dayOfWeek: dayOfWeek.isEmpty ? nil : dayOfWeek,
            typeTag: typeTag,
            startTime: startTime != Self.formatHour(event.startHour) ? startTime : nil,
            duration: duration != Self.formatDuration(event.endHour - event.startHour) ? duration : nil,
            notes: notes.isEmpty ? nil : notes
        )
    }

    // MARK: - Formatting helpers

    private static func formatHour(_ hour: Double) -> String {
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        let suffix = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return m == 0 ? "\(display):00 \(suffix)" : "\(display):\(String(format: "%02d", m)) \(suffix)"
    }

    private static func formatDuration(_ hours: Double) -> String {
        if hours < 1 { return "\(Int(hours * 60)) min" }
        if hours == floor(hours) {
            let h = Int(hours)
            return h == 1 ? "1 hour" : "\(h) hours"
        }
        return String(format: "%.1f hours", hours)
    }

    private static let startTimeOptions: [String] = [
        "6:00 AM", "7:00 AM", "8:00 AM", "9:00 AM", "10:00 AM", "11:00 AM",
        "12:00 PM", "1:00 PM", "2:00 PM", "3:00 PM", "4:00 PM", "5:00 PM",
        "6:00 PM", "7:00 PM", "8:00 PM", "9:00 PM"
    ]

    private static let durationOptions: [String] = [
        "15 min", "30 min", "45 min", "1 hour", "1.5 hours", "2 hours",
        "2.5 hours", "3 hours", "4 hours", "5 hours"
    ]
}
