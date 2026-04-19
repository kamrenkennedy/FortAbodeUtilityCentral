import Foundation
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

    /// Called by the banner's "Install Now" button.
    func installAndRelaunch() {
        guard let block = immediateInstallationBlock else { return }
        block()
    }

    /// Called by the banner's "Later" button.
    func dismissForSession() {
        dismissedForSession = true
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
