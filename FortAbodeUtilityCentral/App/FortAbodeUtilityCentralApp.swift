import SwiftUI
import Sparkle

@main
struct FortAbodeUtilityCentralApp: App {

    @State private var registry = ComponentRegistry()
    @State private var viewModel: ComponentListViewModel?

    // Sparkle updater controller — starts checking for updates automatically
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel {
                    NavigationStack {
                        ContentView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                switch destination {
                                case .componentDetail(let id):
                                    ComponentDetailView(componentId: id)
                                case .marketplace:
                                    MarketplaceView()
                                }
                            }
                    }
                    .environment(viewModel)
                } else {
                    ProgressView("Loading...")
                        .frame(minWidth: 500, minHeight: 400)
                }
            }
            .frame(minWidth: 500, minHeight: 400)
            .onAppear {
                if viewModel == nil {
                    viewModel = ComponentListViewModel(registry: registry)
                }
                handleLaunchMode()
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 600, height: 500)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
        }
    }

    // MARK: - Launch Mode Handling

    private func handleLaunchMode() {
        if BackgroundTaskService.isBackgroundCheck {
            Task {
                guard let viewModel else { return }
                await viewModel.checkAll()

                if viewModel.hasAvailableUpdates {
                    for component in viewModel.components {
                        if case .updateAvailable(let installed, let latest) = viewModel.statuses[component.id] {
                            await NotificationService.shared.postUpdateNotification(
                                componentName: component.displayName,
                                installedVersion: installed,
                                latestVersion: latest
                            )
                            break
                        }
                    }

                    if viewModel.availableUpdateCount > 1 {
                        await NotificationService.shared.postSummaryNotification(
                            count: viewModel.availableUpdateCount
                        )
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    NSApp.terminate(nil)
                }
            }
        } else {
            Task {
                _ = await NotificationService.shared.requestPermission()
            }
        }
    }
}
