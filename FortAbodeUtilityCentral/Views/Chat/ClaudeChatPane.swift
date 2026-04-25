import SwiftUI
import AlignedDesignSystem

// Claude AI assistant pane. First-open: greeting + 4 starter chips. After the
// first send: chips collapse and a thread renders. Page-aware context pill
// reads `appState.selectedDestination`. Live Claude CLI integration is Phase 5
// (deferred); v4.0.0 ships with a hard-coded sample reply.

struct ClaudeChatPane: View {
    @Environment(AppState.self) private var appState

    @State private var draft: String = ""
    @State private var hasSent: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            content
            composer
        }
    }

    @ViewBuilder
    private var content: some View {
        if hasSent {
            sampleThread
        } else {
            greeting
        }
    }

    private var greeting: some View {
        VStack(spacing: Space.s5) {
            Spacer()

            VStack(spacing: Space.s3) {
                Image(systemName: "asterisk")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.onSurfaceVariant)

                Text("How can I help you today?")
                    .font(.headlineSM)
                    .foregroundStyle(Color.onSurface)
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(suggestionChips, id: \.title) { chip in
                    SuggestionChip(chip.title) {
                        chip.action()
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.s4)
    }

    private var sampleThread: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                MessageBubble(speaker: .user, text: draftPreview)

                MessageBubble(
                    speaker: .claude,
                    text: "Done — your 3 PM with Braxton is now on Friday at 3 PM.",
                    actionChips: ["Moved to Fri Apr 25, 3:00 PM"]
                )
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: Space.s2) {
                ChatComposer(
                    text: $draft,
                    placeholder: "Ask Claude anything…",
                    leadingIcons: [
                        ComposerIconButton(symbol: "paperclip", help: "Attach", action: {})
                    ],
                    trailingIcons: [],
                    trailingTrailing: AnyView(modelBadge),
                    onSend: { sent in
                        // mocked — Phase 5 wires real Claude CLI
                        draftPreview = sent
                        hasSent = true
                    }
                )

                pageContextPill
            }
            .padding(Space.s3)
        }
    }

    private var modelBadge: some View {
        Text("Sonnet 4.5")
            .font(.labelSM)
            .foregroundStyle(Color.onSurfaceVariant)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .strokeBorder(Color.outlineVariant.opacity(0.5), lineWidth: 1)
            )
    }

    private var pageContextPill: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color.tertiary)
            Text("Fort Abode · \(appState.selectedDestination.label)")
                .font(.labelSM)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .padding(.horizontal, Space.s2)
    }

    @State private var draftPreview: String = ""

    // Suggestion chip definitions.
    // The "Report a bug" chip dispatches to the FeedbackView sheet — bug
    // reports go through FeedbackService's structured iCloud submission, not
    // through the Claude CLI (zero API tokens for what is fundamentally a
    // form post). Other chips populate the composer as starter text.
    private var suggestionChips: [SuggestionChipModel] {
        [
            SuggestionChipModel(title: "Move my 3pm to Friday") { draft = "Move my 3pm to Friday" },
            SuggestionChipModel(title: "Status on Braxton edit") { draft = "Status on Braxton edit" },
            SuggestionChipModel(title: "Report a bug") { appState.feedbackSheetOpen = true }
        ]
    }
}

private struct SuggestionChipModel {
    let title: String
    let action: () -> Void
}
