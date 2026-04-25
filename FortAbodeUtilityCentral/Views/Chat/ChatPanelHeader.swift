import SwiftUI
import AlignedDesignSystem

// Top of the chat panel. Pill segmented Family|Claude tabs on the left, four
// icon buttons on the right (new chat, history, expand toggle, minimize).
// Family tab carries an unread dot when AppState.unreadFamilyCount > 0.

struct ChatPanelHeader: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Space.s2) {
            tabBar
            Spacer(minLength: Space.s2)
            iconButton(symbol: "square.and.pencil", help: "New chat", action: {})
            iconButton(symbol: "clock.arrow.circlepath", help: "History", action: {})
            iconButton(
                symbol: appState.chatPanelExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                help: appState.chatPanelExpanded ? "Collapse" : "Expand",
                action: {
                    withAnimation(.easeOut(duration: 0.3)) {
                        appState.chatPanelExpanded.toggle()
                    }
                }
            )
            iconButton(symbol: "minus", help: "Minimize", action: {
                appState.closeChat()
            })
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(Color.surfaceContainerLow)
    }

    private var tabBar: some View {
        let binding = Binding<ChatTab>(
            get: { appState.chatActiveTab },
            set: { appState.chatActiveTab = $0 }
        )

        return SegmentedTabBar(
            options: ChatTab.allCases,
            selection: binding,
            label: { $0.label },
            trailingAccessory: { tab in
                if tab == .family && appState.unreadFamilyCount > 0 {
                    AnyView(unreadDot)
                } else {
                    AnyView(EmptyView())
                }
            }
        )
    }

    private var unreadDot: some View {
        Circle()
            .fill(Color.brandRust)
            .frame(width: 6, height: 6)
    }

    private func iconButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
