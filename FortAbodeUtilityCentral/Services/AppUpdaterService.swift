import Foundation
import AppKit
import Sparkle

// MARK: - App Updater Service
//
// Bridges Sparkle's delegate callbacks to an @Observable state the SwiftUI banner
// can subscribe to. When Sparkle has a staged update ready and is about to schedule
// install-on-quit, it hands us an `immediateInstallationBlock` — we store it so the
// banner's "Install Now" button can invoke an immediate relaunch. We return `true`
// from the delegate so Sparkle hands install timing off to us entirely: the user
// controls when to install, via the banner.

@MainActor
@Observable
final class AppUpdaterService: NSObject, SPUUpdaterDelegate {

    /// True once Sparkle has downloaded + extracted an update and is holding it pending install.
    var updateIsReady: Bool = false

    /// Version string of the pending update (e.g. "3.8.1"). Nil until an update is ready.
    var pendingVersion: String?

    /// Set to true when the user clicks "Later" — suppresses the banner for the rest of this
    /// session. On next launch, if the update is still pending, Sparkle calls the delegate
    /// again and the banner re-appears.
    var dismissedForSession: Bool = false

    /// Sparkle's immediate-install closure, captured from `willInstallUpdateOnQuit`.
    /// Calling this relaunches the app with the new version applied.
    private var immediateInstallationBlock: (() -> Void)?

    /// Reference to Sparkle's updater, set by the App after the controller is created.
    /// Used by the bring-to-front check to ask Sparkle to poll the appcast on demand.
    weak var updater: SPUUpdater?

    /// Tracks the last on-demand background check so opening + closing the window
    /// repeatedly within a few minutes doesn't hammer the appcast endpoint.
    private var lastForegroundCheck: Date?

    /// Cooldown between consecutive bring-to-front checks. 10 min strikes a balance:
    /// long enough that alt-tabbing or quick window cycling doesn't fire repeated
    /// network calls, short enough that opening Fort Abode after a meeting picks up
    /// fresh updates without waiting for the daily Sparkle schedule.
    private let foregroundCheckCooldown: TimeInterval = 600

    /// Long-lived Task that bridges the AppKit notification stream into MainActor
    /// context. Lives for the app's lifetime; cancellation isn't required.
    private var activationObserverTask: Task<Void, Never>?

    /// Called by the banner's "Install Now" button.
    func installAndRelaunch() {
        guard let block = immediateInstallationBlock else { return }
        block()
    }

    /// Called by the banner's "Later" button.
    func dismissForSession() {
        dismissedForSession = true
    }

    /// Start watching for the app being brought to the foreground. The first
    /// activation after launch is skipped because Sparkle's own startup check
    /// has already run by then; subsequent activations trigger a debounced
    /// background check so the window opening picks up fresh updates fast.
    func startObservingActivation() {
        guard activationObserverTask == nil else { return }
        activationObserverTask = Task { @MainActor [weak self] in
            var seenFirstActivation = false
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                guard let self else { return }
                if !seenFirstActivation {
                    seenFirstActivation = true
                    continue
                }
                self.checkForUpdatesIfDebouncePassed()
            }
        }
    }

    private func checkForUpdatesIfDebouncePassed() {
        // Don't re-check if we already have a staged update waiting on the banner.
        guard !updateIsReady else { return }
        if let last = lastForegroundCheck, Date().timeIntervalSince(last) < foregroundCheckCooldown {
            return
        }
        lastForegroundCheck = Date()
        updater?.checkForUpdatesInBackground()
    }

    // MARK: - SPUUpdaterDelegate

    /// Sparkle calls this on the main thread when it has a staged update ready to install.
    /// Returning `true` means "I'll handle install timing via `immediateInstallationBlock`";
    /// returning `false` would let Sparkle schedule its own silent install-on-quit.
    /// We always return `true` so the banner is the single source of truth for install.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        // Box the ObjC block so Swift 6 concurrency lets us hop to MainActor.
        // Sparkle guarantees delegate methods fire on main; the box is a formality.
        struct UncheckedBlock: @unchecked Sendable { let run: () -> Void }
        let boxed = UncheckedBlock(run: immediateInstallationBlock)
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            self.immediateInstallationBlock = boxed.run
            self.pendingVersion = version
            self.updateIsReady = true
            self.dismissedForSession = false
        }
        Task.detached(priority: .background) {
            await ErrorLogger.shared.log(
                area: "AppUpdaterService.willInstallUpdateOnQuit",
                message: "Update staged and ready for install",
                context: ["pendingVersion": version]
            )
        }
        return true
    }
}
