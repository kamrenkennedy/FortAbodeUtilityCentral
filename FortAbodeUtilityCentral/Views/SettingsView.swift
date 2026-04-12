import SwiftUI
import Sparkle

// MARK: - Settings View

struct SettingsView: View {

    @State private var viewModel = SettingsViewModel()
    @State private var feedbackConfigured = false
    @State private var showFeedbackSetup = false
    @State private var feedbackToken = ""
    @State private var feedbackDatabaseId = ""
    @State private var feedbackSaveError: String?
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        Form {
            Section("Component Checks") {
                Picker("Check interval", selection: $viewModel.checkInterval) {
                    ForEach(CheckInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }

                Toggle("Enable background checks", isOn: $viewModel.backgroundChecksEnabled)

                Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
            }

            Section("App Updates") {
                Toggle(
                    "Automatically check for app updates",
                    isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    )
                )
            }

            Section("Feedback") {
                if feedbackConfigured {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Feedback is configured")
                    }

                    Button("Reconfigure") {
                        showFeedbackSetup = true
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                        Text("Not configured")
                            .foregroundStyle(.secondary)
                    }

                    Button("Set Up Feedback") {
                        showFeedbackSetup = true
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")

                Link("View on GitHub", destination: URL(string: "https://github.com/kamrenkennedy/FortAbodeUtilityCentral")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 380)
        .task {
            feedbackConfigured = await FeedbackService.shared.isConfigured()
        }
        .sheet(isPresented: $showFeedbackSetup) {
            FeedbackConfigSheet(
                token: $feedbackToken,
                databaseId: $feedbackDatabaseId,
                errorMessage: $feedbackSaveError
            ) {
                Task {
                    do {
                        try await FeedbackService.shared.saveConfig(
                            token: feedbackToken,
                            databaseId: feedbackDatabaseId
                        )
                        feedbackConfigured = true
                        feedbackSaveError = nil
                        showFeedbackSetup = false
                    } catch {
                        feedbackSaveError = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - Feedback Config Sheet

private struct FeedbackConfigSheet: View {
    @Binding var token: String
    @Binding var databaseId: String
    @Binding var errorMessage: String?
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.blue)

            Text("Set Up Feedback")
                .font(.headline)

            Text("Enter your Notion integration token and the database ID where feedback should be sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notion Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("ntn_...", text: $token)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Database ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("abc123...", text: $databaseId)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Save") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty ||
                      databaseId.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(32)
        .frame(width: 380)
    }
}
