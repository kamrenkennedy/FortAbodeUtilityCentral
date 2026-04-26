import SwiftUI
import Sparkle
import AlignedDesignSystem

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

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
        // If launched by LaunchAgent for a background check, start as .accessory so
        // the Dock icon doesn't flash while we run through the component check loop.
        // Normal launches stay .regular (default) so the Dock icon appears as expected.
        if BackgroundTaskService.isBackgroundCheck {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Drop the Dock icon and menu bar. Called when the main window closes so the
    /// process stays alive for background Sparkle updates without a user-visible
    /// quit target.
    static func hideApp() {
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
    private nonisolated(unsafe) var keyObservation: NSObjectProtocol?
    private nonisolated(unsafe) var closeObservation: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()

        // Re-apply whenever the window becomes key (SwiftUI can reset properties)
        if let obs = keyObservation {
            NotificationCenter.default.removeObserver(obs)
            keyObservation = nil
        }
        if let obs = closeObservation {
            NotificationCenter.default.removeObserver(obs)
            closeObservation = nil
        }
        if let window {
            keyObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyStyle()
                }
            }

            // When the user closes the main window, drop the Dock icon so the process
            // stays alive for background Sparkle checks but has no visible quit target.
            // applicationShouldHandleReopen restores the Dock icon via AppDelegate.showApp().
            closeObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    AppDelegate.hideApp()
                }
            }
        }
    }

    private func applyStyle() {
        // Title bar is hidden entirely via .windowStyle(.hiddenTitleBar) on the
        // Window scene. WindowAppearanceModifier exists only to attach the close
        // observer below (drops the Dock icon when the main window closes so the
        // process keeps running for background Sparkle checks).
    }

    deinit {
        if let keyObservation { NotificationCenter.default.removeObserver(keyObservation) }
        if let closeObservation { NotificationCenter.default.removeObserver(closeObservation) }
    }
}

@main
struct FortAbodeUtilityCentralApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var registry = ComponentRegistry()
    @State private var viewModel: ComponentListViewModel?
    @State private var isActivated = KeychainService.isActivated
    @State private var whatsNewReleases: [WhatsNewRelease]?
    @State private var updaterService: AppUpdaterService
    @State private var appState = AppState()

    // Weekly Rhythm data source — Phase 5a wire. Default impl is FileBacked
    // with a mock fallback, so the moment the engine starts emitting JSON to
    // `~/.../Weekly Flow/{user}/dashboards/dashboard-{date}.json` the app picks
    // it up automatically. Until then, mock data keeps the UI populated.
    @State private var weeklyRhythmStore = WeeklyRhythmStore(impl: FileBackedWeeklyRhythmDataSource())

    // Sparkle updater controller — starts checking for updates automatically
    private let updaterController: SPUStandardUpdaterController

    init() {
        FontRegistration.registerBundledFonts()
        // Defensive: clear any Sparkle-staged installers whose build is at or below
        // ours BEFORE starting the updater. Otherwise a stale queue (observed on Kam's
        // Mac after the 3.10.0 → 3.11.0 update) makes Sparkle re-prompt forever.
        AppUpdaterService.clearStaleStagedInstallers()

        let service = AppUpdaterService()
        _updaterService = State(initialValue: service)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: service,
            userDriverDelegate: nil
        )
        // Hand the service a reference to the live updater so its bring-to-front
        // observer can ask Sparkle to poll the appcast on demand. Combined with
        // SUEnableAutomaticChecks (~24h) this gives "fresh updates the moment you
        // open the window" without spamming the network.
        service.updater = updaterController.updater
        service.startObservingActivation()
    }

    var body: some Scene {
        Window("Fort Abode Utility Central", id: "main") {
            Group {
                if !isActivated {
                    ActivationView {
                        isActivated = true
                    }
                } else if let viewModel {
                    RootView(updater: updaterController.updater)
                        .environment(viewModel)
                        .environment(updaterService)
                        .environment(appState)
                        .environment(weeklyRhythmStore)
                } else {
                    ProgressView("Loading...")
                        .frame(minWidth: 900, minHeight: 600)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
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
                logLauncherHeartbeat()
                pinICloudFoldersInBackground()
            }
            .onChange(of: isActivated) { _, activated in
                guard activated else { return }
                if viewModel == nil {
                    viewModel = ComponentListViewModel(registry: registry)
                }
                handleLaunchMode()
                pinICloudFoldersInBackground()
            }
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
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

    /// Pin iCloud folders (Claude Memory + Kennedy Family Docs/Claude) at every launch.
    /// Runs non-blocking so startup isn't delayed. Silent on success; errors go to ErrorLogger.
    /// This undoes any macOS cache eviction that happened while Fort Abode was closed.
    private func pinICloudFoldersInBackground() {
        guard let viewModel else { return }
        Task.detached(priority: .background) {
            await viewModel.pinICloudFolders()
        }
    }

    /// Write a single heartbeat line to the error log on every app launch so we can tell
    /// from a debug report whether the logger itself is functional on a given machine.
    /// If this line appears in the log, the logger works — every downstream failure will
    /// be visible. If it does NOT appear, the logger itself is broken and needs fixing
    /// before we trust any other debug output.
    private func logLauncherHeartbeat() {
        Task.detached(priority: .background) {
            await ErrorLogger.shared.logHeartbeat()
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
