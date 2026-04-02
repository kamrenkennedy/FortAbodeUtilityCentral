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

    /// Handle notification tap — bring the app to front
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
