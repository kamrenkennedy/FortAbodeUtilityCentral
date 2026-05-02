import SwiftUI
import AlignedDesignSystem

// The floating chat panel container. Two states driven by AppState:
// - popover (default): 340×min(560, height-36) at bottom-right, r12 corners
// - expanded: 380 × full-height right rail, no corner radius
// Sizes per UPDATE-2026-04-26-desktop-mac.md desktop scale.
// Esc handling: collapse if expanded, otherwise close the panel.

struct ChatPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ChatPanelHeader()
            Divider().opacity(0.4)
            paneContent
        }
        .frame(width: appState.chatPanelExpanded ? 380 : 340)
        .frame(maxHeight: appState.chatPanelExpanded ? .infinity : 560)
        .background(Color.surfaceContainerLow)
        .clipShape(
            RoundedRectangle(
                cornerRadius: appState.chatPanelExpanded ? 0 : Radius.lg,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: appState.chatPanelExpanded ? 0 : Radius.lg,
                style: .continuous
            )
            .strokeBorder(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        )
        .floatingPanelShadow()
        .padding(.bottom, appState.chatPanelExpanded ? 0 : Space.s4)
        .padding(.trailing, appState.chatPanelExpanded ? 0 : Space.s4)
        .onExitCommand {
            if appState.chatPanelExpanded {
                withAnimation(.easeOut(duration: 0.3)) {
                    appState.chatPanelExpanded = false
                }
            } else {
                appState.closeChat()
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch appState.chatActiveTab {
        case .family:
            FamilyChatPane()
        case .claude:
            ClaudeChatPane()
        }
    }
}
