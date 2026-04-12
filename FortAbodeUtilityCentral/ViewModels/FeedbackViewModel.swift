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
    var isConfigured = false

    private let feedbackService = FeedbackService.shared

    enum SubmitResult: Equatable {
        case success
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
            let submittedBy = UserDefaults.standard.string(forKey: "feedbackDisplayName") ?? NSFullUserName()

            try await feedbackService.submitFeedback(
                type: feedbackType,
                component: componentName,
                subject: subject,
                description: descriptionText,
                debugReport: debugReport,
                submittedBy: submittedBy,
                appVersion: appVersion
            )

            submitResult = .success
            subject = ""
            descriptionText = ""
            selectedComponentId = nil
        } catch {
            submitResult = .error(error.localizedDescription)
        }

        isSubmitting = false
    }
}
