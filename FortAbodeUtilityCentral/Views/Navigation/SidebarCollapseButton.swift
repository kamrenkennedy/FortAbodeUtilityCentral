import SwiftUI
import AlignedDesignSystem

// Hamburger toggle that expands/collapses the sidebar. Persists the state via
// AppState (which writes to UserDefaults under fa-sidebar-collapsed).

struct SidebarCollapseButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) {
                appState.sidebarCollapsed.toggle()
            }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appState.sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
    }
}
