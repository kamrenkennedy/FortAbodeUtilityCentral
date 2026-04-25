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
        .preferredColorScheme(appState.theme.preferredColorScheme)
        .sheet(isPresented: feedbackSheetBinding) {
            NavigationStack {
                FeedbackView()
            }
            .frame(minWidth: 480, minHeight: 520)
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
                        case .familyMemory:
                            FamilyMemoryView()
                        case .feedback:
                            FeedbackView()
                        case .marketplace:
                            MarketplaceView()
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
