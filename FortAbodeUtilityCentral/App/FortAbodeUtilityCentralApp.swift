import SwiftUI
import Sparkle

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    /// Keep the app alive when the last window closes
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopen the main window when the dock icon is clicked or Spotlight-launched
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Self.showApp()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Window configuration moved to SwiftUI onAppear (configureMainWindow)
        // to guarantee the window exists — Release builds may not have it yet here.
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Show the app: restore dock icon and bring window forward
    static func showApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.className != "NSStatusBarWindow" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

}

// MARK: - Window Appearance

/// NSViewRepresentable that configures the hosting NSWindow's title bar.
/// Uses viewDidMoveToWindow() for guaranteed window access — no timing race.
struct WindowAppearanceModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfigView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class WindowConfigView: NSView {
    private nonisolated(unsafe) var observation: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()

        // Re-apply whenever the window becomes key (SwiftUI can reset properties)
        if let obs = observation {
            NotificationCenter.default.removeObserver(obs)
            observation = nil
        }
        if let window {
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyStyle()
                }
            }
        }
    }

    private func applyStyle() {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
    }

    nonisolated deinit {
        if let observation { NotificationCenter.default.removeObserver(observation) }
    }
}

@main
struct FortAbodeUtilityCentralApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var registry = ComponentRegistry()
    @State private var viewModel: ComponentListViewModel?
    @State private var isActivated = KeychainService.isActivated
    @State private var whatsNewReleases: [WhatsNewRelease]?

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
        Window("Fort Abode Utility Central", id: "main") {
            Group {
                if !isActivated {
                    ActivationView {
                        isActivated = true
                    }
                } else if let viewModel {
                    NavigationStack {
                        ContentView()
                            .navigationDestination(for: AppDestination.self) { destination in
                                switch destination {
                                case .componentDetail(let id):
                                    ComponentDetailView(componentId: id)
                                case .marketplace:
                                    MarketplaceView()
                                case .feedback:
                                    FeedbackView()
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
            .background(WindowAppearanceModifier())
            .sheet(isPresented: Binding(
                get: { whatsNewReleases != nil },
                set: { if !$0 { whatsNewReleases = nil } }
            )) {
                if let releases = whatsNewReleases {
                    WhatsNewView(releases: releases) {
                        whatsNewReleases = nil
                    }
                }
            }
            .onAppear {
                guard isActivated else { return }
                if viewModel == nil {
                    viewModel = ComponentListViewModel(registry: registry)
                }
                handleLaunchMode()
                checkWhatsNew()
            }
            .onChange(of: isActivated) { _, activated in
                guard activated else { return }
                if viewModel == nil {
                    viewModel = ComponentListViewModel(registry: registry)
                }
                handleLaunchMode()
            }
        }
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
                    // Post notifications for updates
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

                    // Open the app window so the user can see and act on updates
                    AppDelegate.showApp()
                }

                // Detect new marketplace items
                let knownIds = Set(UserDefaults.standard.stringArray(forKey: "knownMarketplaceIds") ?? [])
                let currentIds = Set(viewModel.components.filter(\.showInMarketplace).map(\.id))
                let newItems = currentIds.subtracting(knownIds)

                if !newItems.isEmpty {
                    for id in newItems {
                        if let component = viewModel.components.first(where: { $0.id == id }) {
                            await NotificationService.shared.postNewComponentNotification(
                                componentName: component.displayName
                            )
                        }
                    }
                    // Open the app so user can see the new marketplace item
                    AppDelegate.showApp()
                }

                // Save current marketplace IDs so we only notify once per new item
                UserDefaults.standard.set(Array(currentIds), forKey: "knownMarketplaceIds")

                // If nothing to show, stay in background (don't terminate — app persists)
                if !viewModel.hasAvailableUpdates && newItems.isEmpty {
                    // Just stay quiet in background
                }
            }
        } else {
            Task {
                _ = await NotificationService.shared.requestPermission()

                // Seed known marketplace IDs on first normal launch
                if UserDefaults.standard.stringArray(forKey: "knownMarketplaceIds") == nil {
                    guard let viewModel else { return }
                    await viewModel.checkAll()
                    let ids = viewModel.components.filter(\.showInMarketplace).map(\.id)
                    UserDefaults.standard.set(ids, forKey: "knownMarketplaceIds")
                }

                // Prompt for launch at login on first launch
                promptLaunchAtLoginIfNeeded()
            }
        }
    }

    private func checkWhatsNew() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let lastSeenKey = "lastSeenAppVersion"
        let lastSeen = UserDefaults.standard.string(forKey: lastSeenKey)

        guard lastSeen != currentVersion else { return }
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)

        if let lastSeen, let releases = WhatsNewLoader.loadSince(lastSeen: lastSeen, current: currentVersion) {
            // Only show if upgrading (not first install) and notes exist
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                whatsNewReleases = releases
            }
        }
    }

    private func promptLaunchAtLoginIfNeeded() {
        let key = "hasPromptedLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let alert = NSAlert()
            alert.messageText = "Start at Login?"
            alert.informativeText = "Fort Abode can start automatically when you log in so it stays up to date in the background."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Not Now")
            alert.alertStyle = .informational

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                BackgroundTaskService.shared.setLaunchAtLogin(true)
                UserDefaults.standard.set(true, forKey: AppSettingsKey.launchAtLogin)
            }
        }
    }
}
