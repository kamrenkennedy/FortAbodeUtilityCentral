import SwiftUI
import Sparkle
import AlignedDesignSystem

// Top-level shell for v4.0.0 — sidebar (collapsible) + canvas. The previous
// icon-gallery ContentView is replaced; its functionality moves to the
// MarketplaceView tab. ChatFAB + ChatPanel overlays are added in Phase 2c.

struct RootView: View {
    let updater: SPUUpdater

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: appState.sidebarCollapsed ? 64 : 240)
                .animation(.easeOut(duration: 0.3), value: appState.sidebarCollapsed)

            destinationContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surface)
        }
        .overlay(alignment: .bottomTrailing) {
            chatOverlay
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: appState.chatPanelOpen)
                .animation(.easeOut(duration: 0.3), value: appState.chatPanelExpanded)
        }
        .preferredColorScheme(appState.theme.preferredColorScheme)
        .sheet(isPresented: feedbackSheetBinding) {
            NavigationStack {
                FeedbackView()
            }
            .frame(minWidth: 480, minHeight: 520)
        }
    }

    @ViewBuilder
    private var chatOverlay: some View {
        if appState.chatPanelOpen {
            ChatPanel()
                .transition(.scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity))
        } else {
            ChatPanelFAB(unreadCount: appState.unreadFamilyCount) {
                appState.openChat(.family)
            }
            .padding(28)
            .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottomTrailing)))
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch appState.selectedDestination {
        case .home:
            HomeView()
        case .family:
            FamilyView()
        case .weeklyRhythm:
            WeeklyRhythmView()
        case .marketplace:
            NavigationStack {
                MarketplaceView()
                    .navigationDestination(for: AppDestination.self) { destination in
                        switch destination {
                        case .componentDetail(let id):
                            ComponentDetailView(componentId: id)
                        }
                    }
            }
        case .settings:
            NavigationStack {
                SettingsView(updater: updater)
            }
        }
    }

    private var feedbackSheetBinding: Binding<Bool> {
        Binding(
            get: { appState.feedbackSheetOpen },
            set: { appState.feedbackSheetOpen = $0 }
        )
    }
}
