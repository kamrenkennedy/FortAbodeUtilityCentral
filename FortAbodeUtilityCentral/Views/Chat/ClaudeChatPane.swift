import SwiftUI
import AlignedDesignSystem

// Claude AI assistant pane. Y6: live wired to ClaudeChatStore. Composer's
// onSend dispatches to the store, which spawns a fresh `claude --print`
// per turn, streams text deltas back into the placeholder bubble, and
// persists the thread to ~/Library/Application Support after each turn.
//
// Greeting + 4 starter chips remain on first open (when messages.isEmpty).
// Once the user sends a message the chips collapse and the thread takes over.
// Tools toggle in the below-pill row picks --permission-mode at spawn time.

struct ClaudeChatPane: View {
    @Environment(AppState.self) private var appState
    @Environment(ClaudeChatStore.self) private var store

    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            content
            composer
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.messages.isEmpty {
            greeting
        } else {
            thread
        }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(store.messages) { turn in
                        MessageBubble(
                            speaker: turn.role == .user ? .user : .claude,
                            text: bubbleText(for: turn),
                            actionChips: breadcrumbChips(for: turn)
                        )
                        .id(turn.id)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s4)
            }
            .onChange(of: store.messages.last?.id) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newID, anchor: .bottom)
                }
            }
            .onChange(of: store.messages.last?.content) { _, _ in
                // Keep the bottom pinned while the assistant is mid-stream so
                // text deltas don't visually scroll out from under the user.
                guard let lastID = store.messages.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func bubbleText(for turn: ChatTurn) -> String {
        if let reason = turn.failureReason { return "⚠️ " + reason }
        if turn.isStreaming && turn.content.isEmpty { return "…" }
        if turn.isStreaming { return turn.content + "▌" }
        return turn.content
    }

    private func breadcrumbChips(for turn: ChatTurn) -> [String] {
        turn.toolBreadcrumbs.map { breadcrumb in
            "\(breadcrumb.toolName) \(breadcrumb.succeeded ? "✓" : "✗")"
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
                        Task { await store.sendUserMessage(sent) }
                    }
                )

                belowPillRow
            }
            .padding(Space.s3)
        }
    }

    private var belowPillRow: some View {
        HStack(spacing: Space.s2) {
            pageContextPill
            Spacer(minLength: Space.s2)
            toolsTogglePill
        }
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

    private var toolsTogglePill: some View {
        Button {
            store.toolsEnabled.toggle()
        } label: {
            HStack(spacing: Space.s1) {
                Image(systemName: store.toolsEnabled
                      ? "wrench.and.screwdriver.fill"
                      : "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .semibold))
                Text("Tools: \(store.toolsEnabled ? "on" : "off")")
                    .font(.labelSM.weight(.medium))
            }
            .foregroundStyle(store.toolsEnabled ? Color.brandRust : Color.onSurfaceVariant)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .overlay(
                Capsule().stroke(
                    store.toolsEnabled
                        ? Color.brandRust.opacity(0.5)
                        : Color.outlineVariant,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .help(store.toolsEnabled
              ? "Tools on — Claude can read files, run commands, and use MCPs."
              : "Tools off — Claude will respond conversationally without using tools.")
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

    // The "Report a bug" chip dispatches to FeedbackView's iCloud submission
    // path — bug reports go through FeedbackService, NOT the Claude CLI (zero
    // API tokens for what is fundamentally a form post). Other chips just
    // populate the composer as starter text.
    private var suggestionChips: [SuggestionChipModel] {
        [
            SuggestionChipModel(title: "What's on my plate this week?") {
                draft = "What's on my plate this week?"
            },
            SuggestionChipModel(title: "Summarize my last engine run") {
                draft = "Summarize my last Weekly Rhythm engine run."
            },
            SuggestionChipModel(title: "Report a bug") {
                appState.feedbackSheetOpen = true
            }
        ]
    }
}

private struct SuggestionChipModel {
    let title: String
    let action: () -> Void
}
