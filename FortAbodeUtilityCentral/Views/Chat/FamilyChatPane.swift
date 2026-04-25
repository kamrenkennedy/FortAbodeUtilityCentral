import SwiftUI
import AlignedDesignSystem

// Family DMs — Kam ↔ Tiera. Day dividers, alternating bubbles, occasional rich
// event/errand cards. Composer offers insert-event / insert-errand / attach
// shortcuts. v4.0.0 ships with mocked data; live sync is a Phase 5 concern.

struct FamilyChatPane: View {
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            messages
            composer
        }
    }

    private var messages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                dayDivider("Yesterday")

                MessageBubble(
                    speaker: .tiera,
                    text: "Heads up — vet rescheduled Margot's checkup."
                )

                MessageBubble(
                    speaker: .user,
                    text: "Got it. New time?"
                )

                RichCardMessage(
                    kicker: "Event moved",
                    kickerSymbol: "calendar.badge.clock",
                    title: "Margot — Annual checkup",
                    meta: "Fri Apr 25, 10:30 AM · Banfield"
                )

                dayDivider("Today")

                MessageBubble(
                    speaker: .tiera,
                    text: "Can you grab a card on the way home? Mom's birthday tomorrow."
                )
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            ChatComposer(
                text: $draft,
                placeholder: "Message Tiera…",
                leadingIcons: [
                    ComposerIconButton(symbol: "calendar", help: "Insert event", action: {}),
                    ComposerIconButton(symbol: "checkmark.circle", help: "Insert errand", action: {}),
                    ComposerIconButton(symbol: "paperclip", help: "Attach", action: {})
                ],
                onSend: { _ in
                    // mocked — no live wiring yet
                }
            )
            .padding(Space.s3)
        }
    }

    private func dayDivider(_ label: String) -> some View {
        HStack(spacing: Space.s2) {
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
            Text(label.uppercased())
                .font(.labelSM)
                .tracking(1.5)
                .foregroundStyle(Color.onSurfaceVariant)
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.5))
                .frame(height: 1)
        }
    }
}
