import SwiftUI
import Sparkle

// MARK: - Settings View

struct SettingsView: View {

    @State private var viewModel = SettingsViewModel()
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

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")

                Link("View on GitHub", destination: URL(string: "https://github.com/kamrenkennedy/FortAbodeUtilityCentral")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
