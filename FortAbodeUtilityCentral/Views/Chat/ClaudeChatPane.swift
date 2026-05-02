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
                        turnView(for: turn)
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

    @ViewBuilder
    private func turnView(for turn: ChatTurn) -> some View {
        if let plan = turn.pendingPlan {
            PlanCardMessage(
                plan: plan,
                onExecute: { Task { await store.executePlan(turnID: turn.id) } },
                onCancel: { Task { await store.cancelPlan(turnID: turn.id) } }
            )
        } else {
            MessageBubble(
                speaker: turn.role == .user ? .user : .claude,
                text: bubbleText(for: turn),
                actionChips: breadcrumbChips(for: turn)
            )
        }
    }

    private func bubbleText(for turn: ChatTurn) -> String {
        if let reason = turn.failureReason { return "⚠️ " + reason }
        if turn.isStreaming && turn.content.isEmpty { return "…" }
        if turn.isStreaming { return turn.content + "▌" }
        return turn.content
    }

    private func breadcrumbChips(for turn: ChatTurn) -> [ChatActionChip] {
        turn.toolBreadcrumbs.map { breadcrumb in
            breadcrumb.succeeded
                ? .success(breadcrumb.toolName)
                : .failure(breadcrumb.toolName)
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
                    trailingTrailing: nil,
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
            modelAndContextPill
            Spacer(minLength: Space.s2)
            permissionModePill
        }
    }

    /// Replaces the prior static "Fort Abode · Home" page-context pill with
    /// a clickable Claude model picker followed by the current page label.
    /// The Menu cascades upward (composer sits at the bottom of the window
    /// so SwiftUI naturally opens the menu above the trigger).
    private var modelAndContextPill: some View {
        HStack(spacing: Space.s1) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color.tertiary)

            Menu {
                Section("Model") {
                    ForEach(ClaudeChatTurnRunner.ClaudeModel.allCases, id: \.self) { model in
                        Button {
                            store.selectedModel = model
                        } label: {
                            Label(
                                modelLabel(for: model),
                                systemImage: store.selectedModel == model ? "checkmark" : ""
                            )
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(modelLabel(for: store.selectedModel))
                        .font(.labelSM.weight(.medium))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(Color.onSurface)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(modelHelp(for: store.selectedModel))

            Text("· \(appState.selectedDestination.label)")
                .font(.labelSM)
                .foregroundStyle(Color.onSurfaceVariant)
        }
        .padding(.horizontal, Space.s2)
    }

    private func modelLabel(for model: ClaudeChatTurnRunner.ClaudeModel) -> String {
        switch model {
        case .sonnet: return "Sonnet"
        case .opus:   return "Opus"
        case .haiku:  return "Haiku"
        }
    }

    private func modelHelp(for model: ClaudeChatTurnRunner.ClaudeModel) -> String {
        switch model {
        case .sonnet: return "Sonnet — balanced quality and speed (default)."
        case .opus:   return "Opus — deepest reasoning, slower and pricier."
        case .haiku:  return "Haiku — fastest and lightest."
        }
    }

    private var permissionModePill: some View {
        Menu {
            Section("Tools") {
                ForEach(ClaudeChatTurnRunner.PermissionMode.allCases, id: \.self) { mode in
                    Button {
                        store.permissionMode = mode
                    } label: {
                        Label(label(for: mode), systemImage: store.permissionMode == mode ? "checkmark" : "")
                    }
                }
            }
        } label: {
            HStack(spacing: Space.s1) {
                Image(systemName: icon(for: store.permissionMode))
                    .font(.system(size: 10, weight: .semibold))
                Text("Tools: \(label(for: store.permissionMode))")
                    .font(.labelSM.weight(.medium))
            }
            .foregroundStyle(foreground(for: store.permissionMode))
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .overlay(
                Capsule().stroke(
                    stroke(for: store.permissionMode),
                    lineWidth: 1
                )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help(for: store.permissionMode))
    }

    private func label(for mode: ClaudeChatTurnRunner.PermissionMode) -> String {
        switch mode {
        case .off:       return "Off"
        case .allowlist: return "Allowlist"
        case .preview:   return "Preview"
        case .all:       return "All"
        }
    }

    private func icon(for mode: ClaudeChatTurnRunner.PermissionMode) -> String {
        switch mode {
        case .off:       return "wrench.and.screwdriver"
        case .allowlist: return "checklist"
        case .preview:   return "eye"
        case .all:       return "wrench.and.screwdriver.fill"
        }
    }

    private func foreground(for mode: ClaudeChatTurnRunner.PermissionMode) -> Color {
        switch mode {
        case .off:       return Color.onSurfaceVariant
        case .allowlist: return Color.brandRust
        case .preview:   return Color.tertiary
        case .all:       return Color.brandRust
        }
    }

    private func stroke(for mode: ClaudeChatTurnRunner.PermissionMode) -> Color {
        switch mode {
        case .off:       return Color.outlineVariant
        case .allowlist: return Color.brandRust.opacity(0.5)
        case .preview:   return Color.tertiary.opacity(0.5)
        case .all:       return Color.brandRust.opacity(0.7)
        }
    }

    private func help(for mode: ClaudeChatTurnRunner.PermissionMode) -> String {
        switch mode {
        case .off:
            return "Tools off — Claude will respond conversationally without using tools."
        case .allowlist:
            return "Allowlist — Claude can use the tools you've pre-approved in Settings."
        case .preview:
            return "Preview — Claude drafts a plan first; you click Execute to actually run it."
        case .all:
            return "All tools — Claude can use any tool, including Bash. Use with care."
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
