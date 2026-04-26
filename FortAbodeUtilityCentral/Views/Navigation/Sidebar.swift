import SwiftUI
import AlignedDesignSystem

// Left rail of the v4.0.0 shell. Header (logo + collapse button) → nav items
// → spacer → Kennedy Family identity card. Collapses to 64pt icon-only when
// AppState.sidebarCollapsed is true; full width is 240pt.

struct Sidebar: View {
    @Environment(AppState.self) private var appState

    private let mainNavDestinations: [Destination] = [.home, .family, .weeklyRhythm, .marketplace]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Padding per UPDATE-2026-04-26-desktop-mac.md desktop sidebar values:
            // 24×20pt expanded, 24×10pt collapsed. Logo bottom margin 32pt.
            header
                .padding(.horizontal, appState.sidebarCollapsed ? Space.s2_5 : Space.s5)
                .padding(.top, Space.s6)
                .padding(.bottom, Space.s8)

            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(mainNavDestinations) { destination in
                    SidebarNavItem(destination: destination)
                }
            }
            .padding(.horizontal, appState.sidebarCollapsed ? Space.s1 : Space.s2)

            Spacer()

            // Settings sits at the bottom — separate from the main nav, lower
            // visual weight (smaller padding) so it reads as a footer item.
            SidebarNavItem(destination: .settings, compact: true)
                .padding(.horizontal, appState.sidebarCollapsed ? Space.s1 : Space.s2)
                .padding(.bottom, Space.s3)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.sidebarBackground)
    }

    @ViewBuilder
    private var header: some View {
        if appState.sidebarCollapsed {
            HStack {
                Spacer(minLength: 0)
                SidebarCollapseButton()
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: Space.s2) {
                Text("FORT ABODE")
                    .font(.logo)
                    .tracking(3)
                    .foregroundStyle(Color.onSurface)
                Spacer(minLength: 0)
                SidebarCollapseButton()
            }
        }
    }
}

private struct SidebarNavItem: View {
    let destination: Destination
    var compact: Bool = false
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    private var isActive: Bool {
        appState.selectedDestination == destination
    }

    private var hasAlert: Bool {
        appState.alertCount(for: destination) > 0
    }

    var body: some View {
        Button {
            appState.selectedDestination = destination
        } label: {
            HStack(spacing: Space.s2_5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: destination.symbol)
                        .font(.system(size: compact ? 13 : 15, weight: .regular))
                        .frame(width: 16, height: 16)

                    if hasAlert && appState.sidebarCollapsed {
                        Circle()
                            .fill(Color.brandRust)
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: -2)
                    }
                }

                if !appState.sidebarCollapsed {
                    Text(destination.label)
                        .font(compact ? .labelLG : .navItem)
                }

                Spacer(minLength: 0)

                if hasAlert && !appState.sidebarCollapsed {
                    Circle()
                        .fill(Color.brandRust)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(isActive ? Color.onSurface : Color.navInactive)
            .padding(.horizontal, Space.s2_5)
            .padding(.vertical, compact ? Space.s1_5 : Space.s2)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isActive ? Color.surfaceContainerLow : Color.clear)
            )
            .offset(x: isHovering && !isActive ? 2 : 0)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.3), value: isHovering)
            .animation(.easeOut(duration: 0.2), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(appState.sidebarCollapsed ? destination.label : "")
    }
}
