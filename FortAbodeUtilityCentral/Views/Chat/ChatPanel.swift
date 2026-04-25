import SwiftUI
import AlignedDesignSystem

// The floating chat panel container. Two states driven by AppState:
// - popover (default): 380×min(640, height-48) at bottom-right, 16pt corners
// - expanded: 420 × full-height right rail, no corner radius
// Esc handling: collapse if expanded, otherwise close the panel.

struct ChatPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ChatPanelHeader()
            Divider().opacity(0.4)
            paneContent
        }
        .frame(width: appState.chatPanelExpanded ? 420 : 380)
        .frame(maxHeight: appState.chatPanelExpanded ? .infinity : 640)
        .background(Color.surfaceContainerLow)
        .clipShape(
            RoundedRectangle(
                cornerRadius: appState.chatPanelExpanded ? 0 : Radius.xl,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: appState.chatPanelExpanded ? 0 : Radius.xl,
                style: .continuous
            )
            .strokeBorder(Color.outlineVariant.opacity(0.4), lineWidth: 1)
        )
        .floatingPanelShadow()
        .padding(.bottom, appState.chatPanelExpanded ? 0 : Space.s6)
        .padding(.trailing, appState.chatPanelExpanded ? 0 : Space.s6)
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
