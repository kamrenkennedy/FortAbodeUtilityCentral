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

    /// NotificationCenter observer token for the bring-to-front check. Held for
    /// the app's lifetime; explicit removal isn't required because the observer
    /// is torn down with the app process.
    private var activationObserver: NSObjectProtocol?

    /// First activation after launch is skipped because Sparkle's startup check
    /// has already fired by then; this tracks whether we've passed it.
    private var seenFirstActivation: Bool = false

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
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees the closure runs on the main thread,
            // so MainActor.assumeIsolated is safe under Swift 6 strict
            // concurrency. Same pattern as willInstallUpdateOnQuit above.
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.seenFirstActivation {
                    self.seenFirstActivation = true
                    return
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

    // MARK: - Stale staged-installer cleanup

    /// Delete any Sparkle-staged installers in the cache whose CFBundleVersion is
    /// less-than-or-equal to the currently-running app's. Called BEFORE
    /// `SPUStandardUpdaterController` is created so Sparkle's first scan sees a
    /// clean state.
    ///
    /// Why this exists: on Kam's Mac (2026-04-25), Sparkle had a queued v3.11.0
    /// installer that kept re-prompting "ready to install" on every launch even
    /// though the running app was already v3.11.0 (38). The install had partially
    /// completed at some prior point but Sparkle didn't clear its Installation
    /// cache, so it kept offering a no-op upgrade. This wipes the queue when
    /// there's nothing to actually upgrade to.
    static func clearStaleStagedInstallers() {
        let fm = FileManager.default
        guard let bundleID = Bundle.main.bundleIdentifier,
              let runningBuildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              let runningBuild = Int(runningBuildString) else {
            return
        }

        let installationDir = fm
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleID)
            .appendingPathComponent("org.sparkle-project.Sparkle")
            .appendingPathComponent("Installation")

        guard let installationDir,
              fm.fileExists(atPath: installationDir.path),
              let stagedDirs = try? fm.contentsOfDirectory(at: installationDir, includingPropertiesForKeys: nil) else {
            return
        }

        var removedCount = 0
        for stagedDir in stagedDirs {
            // Each staged dir contains the downloaded .zip + a subdirectory with the unpacked .app.
            // Walk one level down to find the unpacked .app's Info.plist.
            guard let children = try? fm.contentsOfDirectory(at: stagedDir, includingPropertiesForKeys: nil) else {
                continue
            }
            for child in children {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }

                // Look for any *.app sibling in this child dir — Sparkle unpacks to a uuid
                // dir then puts the .app inside it.
                guard let unpackedApp = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil))?
                        .first(where: { $0.pathExtension == "app" }) else { continue }

                let plistURL = unpackedApp.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plistURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let stagedBuildString = plist["CFBundleVersion"] as? String,
                      let stagedBuild = Int(stagedBuildString) else { continue }

                if stagedBuild <= runningBuild {
                    try? fm.removeItem(at: stagedDir)
                    removedCount += 1
                    break
                }
            }
        }

        if removedCount > 0 {
            Task.detached(priority: .background) {
                await ErrorLogger.shared.log(
                    area: "AppUpdaterService.clearStaleStagedInstallers",
                    message: "Removed \(removedCount) stale Sparkle staged installer(s) at or below running build \(runningBuild)",
                    context: ["runningBuild": "\(runningBuild)"]
                )
            }
        }
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
