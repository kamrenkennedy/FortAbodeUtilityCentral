import SwiftUI
import AlignedDesignSystem

// MARK: - TriageRsvpControl
//
// Inline Accept / Tentative / Decline buttons rendered on triage rows whose
// `kind == .pendingInvite`. Three 24pt mini buttons in a tight HStack.
//
// Active state when a button is selected (e.g. user picked Accept). Tapping
// the same active button clears the selection (returns to all-idle). Tapping
// a different button switches selection without going through idle first.
//
// Spec: .claude/design/v4-parity-pass/README.md §3 (Triage RSVP buttons)
//
// State / colors per spec:
//   Idle         — surfaceContainerHigh bg, onSurfaceVariant fg
//   Accept       — Color.tertiary bg, Color.onTertiary fg
//   Tentative    — Color.warmAmberDim bg, Color.warmAmber fg
//   Decline      — Color.brandRust @ 18% bg, Color.brandRust fg
//
// Sizing: height 24pt, padding 0×Space.s2_5 (10pt), Radius.md (6pt),
// font labelSM (10pt). Don't expand the row's vertical rhythm.

struct TriageRsvpControl: View {
    /// Currently-selected response, or nil for idle.
    let selected: RsvpResponse?
    /// Called with the new selection. The same value as `selected` means
    /// "user is clearing their prior choice" — caller fires `.cleared`.
    let onSelect: (RsvpResponse) -> Void

    var body: some View {
        HStack(spacing: Space.s1_5) {
            rsvpButton(.accept)
            rsvpButton(.tentative)
            rsvpButton(.decline)
        }
    }

    private func rsvpButton(_ kind: RsvpResponse) -> some View {
        let isActive = (selected == kind)
        return Button {
            // Toggling: tap-same-active sends `.cleared`; otherwise sends `kind`.
            onSelect(isActive ? .cleared : kind)
        } label: {
            Text(label(for: kind))
                .font(.labelSM)
                .foregroundStyle(isActive ? activeForeground(for: kind) : Color.onSurfaceVariant)
                .padding(.horizontal, Space.s2_5)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(isActive ? activeBackground(for: kind) : Color.surfaceContainerHigh)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label(for: kind))
    }

    private func label(for kind: RsvpResponse) -> String {
        switch kind {
        case .accept:    return "Accept"
        case .tentative: return "Tentative"
        case .decline:   return "Decline"
        case .cleared:   return ""  // never rendered
        }
    }

    private func activeBackground(for kind: RsvpResponse) -> Color {
        switch kind {
        case .accept:    return Color.tertiary
        case .tentative: return Color.warmAmberDim
        case .decline:   return Color.brandRust.opacity(0.18)
        case .cleared:   return Color.surfaceContainerHigh
        }
    }

    private func activeForeground(for kind: RsvpResponse) -> Color {
        switch kind {
        case .accept:    return Color.onTertiary
        case .tentative: return Color.warmAmber
        case .decline:   return Color.brandRust
        case .cleared:   return Color.onSurfaceVariant
        }
    }
}
