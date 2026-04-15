import Foundation
import SwiftUI

// MARK: - Feedback ViewModel

@MainActor
@Observable
final class FeedbackViewModel {

    var feedbackType: FeedbackType = .bug
    var selectedComponentId: String?
    var subject = ""
    var descriptionText = ""
    var isSubmitting = false
    var submitResult: SubmitResult?
    /// v3.7.5: `FeedbackService.isConfigured()` now always returns true because the file-write
    /// path has no preconditions. Kept as state for backwards compat with FeedbackView's
    /// (now unreachable) notConfiguredView branch.
    var isConfigured = false

    private let feedbackService = FeedbackService.shared

    enum SubmitResult: Equatable {
        /// v3.7.5: carries the saved file path so the success banner can show the user
        /// exactly where the report was written. File lives under `Claude Memory/Fort Abode Logs/feedback/`
        /// on iCloud, or `~/Library/Logs/FortAbodeUtilityCentral/feedback/` if iCloud is
        /// unavailable.
        case success(savedPath: String)
        case error(String)
    }

    func checkConfiguration() async {
        isConfigured = await feedbackService.isConfigured()
    }

    func submit(statuses: [String: UpdateStatus], components: [Component]) async {
        guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else {
            submitResult = .error("Please enter a subject.")
            return
        }

        isSubmitting = true
        submitResult = nil

        do {
            var debugReport: String?
            if feedbackType == .bug {
                debugReport = await feedbackService.generateDebugReport(
                    statuses: statuses,
                    components: components
                )
            }

            let componentName: String? = if let selectedComponentId {
                components.first(where: { $0.id == selectedComponentId })?.displayName
            } else {
                nil
            }

            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let submittedBy = UserDefaults.standard.string(forKey: "feedbackDisplayName") ?? NSFullUserName()

            let savedURL = try await feedbackService.saveFeedbackReport(
                type: feedbackType,
                component: componentName,
                subject: subject,
                description: descriptionText,
                debugReport: debugReport,
                submittedBy: submittedBy,
                appVersion: appVersion,
                buildNumber: buildNumber
            )

            submitResult = .success(savedPath: savedURL.path)
            subject = ""
            descriptionText = ""
            selectedComponentId = nil
        } catch {
            submitResult = .error(error.localizedDescription)
        }

        isSubmitting = false
    }
}
