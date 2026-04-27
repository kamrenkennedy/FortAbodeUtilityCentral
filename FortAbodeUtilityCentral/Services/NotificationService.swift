import Foundation
import UserNotifications
import AppKit

// MARK: - Notification Service

final class NotificationService: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {

    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request notification permission. Returns true if granted.
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("[NotificationService] Permission request failed: \(error)")
            return false
        }
    }

    /// Post a notification about an available update
    func postUpdateNotification(componentName: String, installedVersion: String, latestVersion: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Claude Update Available"
        content.body = "\(componentName): v\(latestVersion) is available (you have v\(installedVersion))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "update-\(componentName)",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to post notification: \(error)")
        }
    }

    /// Post a notification about a new component available in the marketplace
    func postNewComponentNotification(componentName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "New in Fort Abode"
        content.body = "\(componentName) is now available in the Marketplace."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "new-\(componentName)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to post new component notification: \(error)")
        }
    }

    /// Post a notification when Full Disk Access has been revoked for a component
    /// that needs it (e.g. iMessage). Identifier dedupes within a notification cycle
    /// so repeated `checkAll()` runs that detect the same revocation don't spam.
    func postFDARevokedNotification(componentName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Full Disk Access revoked"
        content.body = "\(componentName) lost Full Disk Access. Open Fort Abode to re-grant it in System Settings."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fda-revoked-\(componentName)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to post FDA-revoked notification: \(error)")
        }
    }

    /// Post a notification when a Weekly Rhythm Engine run finishes. Tapping
    /// deep-links to the Weekly Rhythm tab via `Notification.Name.engineRunNotificationTapped`,
    /// which the App layer observes to set `appState.selectedDestination`.
    /// Identifier is timestamped so multiple runs in the same launch don't
    /// dedupe each other.
    func postEngineRunNotification(succeeded: Bool, summary: String) async {
        let content = UNMutableNotificationContent()
        content.title = succeeded ? "Weekly Rhythm Engine ran" : "Weekly Rhythm Engine failed"
        content.body = summary
        content.sound = .default

        let stamp = ISO8601DateFormatter().string(from: Date())
        let request = UNNotificationRequest(
            identifier: "weekly-rhythm-run-\(stamp)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to post engine-run notification: \(error)")
        }
    }

    /// Post a summary notification when multiple updates are available
    func postSummaryNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Claude Updates Available"
        content.body = "\(count) components have updates available. Open Fort Abode Utility Central to update."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "update-summary",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to post summary notification: \(error)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    /// Handle notification tap — bring the app to front and (for engine-run
    /// notifications) post `Notification.Name.engineRunNotificationTapped` so
    /// the App layer can deep-link to the Weekly Rhythm tab.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if identifier.hasPrefix("weekly-rhythm-run-") {
                NotificationCenter.default.post(name: .engineRunNotificationTapped, object: nil)
            }
        }
    }
}
