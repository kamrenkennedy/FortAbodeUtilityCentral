import SwiftUI
import Sparkle
import AlignedDesignSystem

// Settings — v4.0.0. Editorial header PREFERENCES / Settings. Sections in
// vertical order: Appearance, Component Checks, App Updates, Account, API
// Keys & Codes, Advanced (with Send Feedback link → FeedbackView sheet).
//
// Theme toggle (System/Dark/Light) wires AppState.theme — persists as
// `fa-theme` in UserDefaults, applied via .preferredColorScheme on RootView.

struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @State private var viewModel = SettingsViewModel()
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorialHeader(eyebrow: "Preferences", title: "Settings")

                VStack(alignment: .leading, spacing: Space.s8) {
                    appearanceSection
                    componentChecksSection
                    appUpdatesSection
                    WeeklyRhythmEngineSection()
                    accountSection
                    apiKeysSection
                    advancedSection
                }
                .padding(.horizontal, Space.s10)
                .padding(.bottom, Space.s16)
            }
            .frame(maxWidth: 1184, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Appearance")

            DashboardCard(verticalPadding: Space.s5, horizontalPadding: Space.s6) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Theme")
                            .font(.headlineSM)
                            .foregroundStyle(Color.onSurface)
                        Text("Default is Dark — Night Gallery. System follows your OS.")
                            .font(.bodySM)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }

                    ThemePicker()
                }
            }
        }
    }

    // MARK: - Component checks

    private var componentChecksSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Component Checks")

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    settingsRow(
                        title: "Check interval",
                        subtitle: "How often Fort Abode polls for updates."
                    ) {
                        Picker("", selection: $viewModel.checkInterval) {
                            ForEach(CheckInterval.allCases) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    RowSeparator()

                    settingsRow(
                        title: "Background checks",
                        subtitle: "Run a quiet check while the window is closed."
                    ) {
                        Toggle("", isOn: $viewModel.backgroundChecksEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    RowSeparator()

                    settingsRow(
                        title: "Launch at login",
                        subtitle: "Open Fort Abode automatically when you sign in."
                    ) {
                        Toggle("", isOn: $viewModel.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
        }
    }

    // MARK: - App updates

    private var appUpdatesSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "App Updates")

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                settingsRow(
                    title: "Automatic update checks",
                    subtitle: "Sparkle polls the appcast and notifies you when a new build is ready."
                ) {
                    Toggle("", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Account")

            DashboardCard(verticalPadding: Space.s5, horizontalPadding: Space.s6) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    HStack(spacing: Space.s4) {
                        Circle()
                            .fill(Color.tertiary)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text("K")
                                    .font(.headlineMD)
                                    .foregroundStyle(Color.onTertiary)
                            )

                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("The Kennedy Family")
                                .font(.headlineSM)
                                .foregroundStyle(Color.onSurface)
                            Text("Kam & Tiera · Shared household")
                                .font(.bodySM)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }

                        Spacer(minLength: Space.s2)

                        HStack(spacing: Space.s1) {
                            StatusDot(.scheduled)
                            Text("Family activated")
                                .font(.labelSM)
                                .foregroundStyle(Color.onSurface)
                        }
                        .padding(.horizontal, Space.s2)
                        .padding(.vertical, Space.s1)
                        .background(
                            Capsule()
                                .fill(Color.surfaceContainerHigh)
                        )
                    }

                    Rectangle()
                        .fill(Color.outlineVariant.opacity(0.18))
                        .frame(height: 1)

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("Activation code")
                                .font(.bodyMD.weight(.medium))
                                .foregroundStyle(Color.onSurface)
                            Text("Stored locally in Keychain. Used to gate first-run setup.")
                                .font(.bodySM)
                                .foregroundStyle(Color.onSurfaceVariant)
                        }

                        Spacer(minLength: Space.s2)

                        SecondaryButton(label: "Manage") {
                            // Phase 5: surface re-activation flow / keychain reset
                        }
                    }
                }
            }
        }
    }

    // MARK: - API keys

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            HStack(alignment: .firstTextBaseline) {
                Text("API Keys & Codes".uppercased())
                    .font(.labelSM)
                    .tracking(2.0)
                    .foregroundStyle(Color.secondaryText)
                Spacer(minLength: Space.s2)
                Text("Shared with the family")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
            }

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    ForEach(apiKeys) { entry in
                        APIKeyRow(entry: entry)
                        if entry.id != apiKeys.last?.id {
                            RowSeparator()
                        }
                    }
                }
            }
        }
    }

    private let apiKeys: [APIKeyEntry] = [
        APIKeyEntry(label: "Anthropic API",            masked: "sk-ant-api03-••••••••••••••••••••••••••••••_a8Xq"),
        APIKeyEntry(label: "Notion integration token", masked: "secret_••••••••••••••••••••••••••••••••LpQ4"),
        APIKeyEntry(label: "Google OAuth client",      masked: "947182••••••.apps.googleusercontent.com"),
        APIKeyEntry(label: "Linear personal API key",  masked: "lin_api_•••••••••••••••••••••••••••••1mZ"),
        APIKeyEntry(label: "Cloudflare API token",     masked: "cf_•••••••••••••••••••••••••••••Tn0p")
    ]

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Advanced")

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    settingsRow(
                        title: "Reset to defaults",
                        subtitle: "Clears local preferences. Family Memory not affected."
                    ) {
                        SecondaryButton(label: "Reset") {
                            // Phase 5: confirmation sheet + UserDefaults reset
                        }
                    }

                    RowSeparator()

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("Version")
                                .font(.bodyMD.weight(.medium))
                                .foregroundStyle(Color.onSurface)
                            HStack(spacing: 4) {
                                Text(versionLine)
                                    .font(.bodySM)
                                    .foregroundStyle(Color.onSurfaceVariant)
                                Text("·")
                                    .font(.bodySM)
                                    .foregroundStyle(Color.onSurfaceVariant)
                                Button("Send feedback") {
                                    appState.feedbackSheetOpen = true
                                }
                                .buttonStyle(.plain)
                                .font(.bodySM)
                                .foregroundStyle(Color.tertiary)
                            }
                        }
                        Spacer(minLength: Space.s2)
                    }
                    .padding(.vertical, Space.s4)
                }
            }
        }
    }

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Fort Abode v\(version) (build \(build))"
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsRow<Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(subtitle)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            trailing()
        }
        .padding(.vertical, Space.s4)
    }
}

// MARK: - Theme picker

private struct ThemePicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let binding = Binding<ThemePref>(
            get: { appState.theme },
            set: { appState.theme = $0 }
        )

        return SegmentedTabBar(
            options: ThemePref.allCases,
            selection: binding,
            label: { $0.label }
        )
        .frame(maxWidth: 320)
    }
}

// MARK: - Secondary button
//
// Maps Settings inline row actions (Reset / Copy / Reveal-counterparts) to the
// AlignedDesignSystem `.alignedSecondaryMini` style so dense-row buttons stay
// visually aligned with marketplace per-card buttons and ComponentDetailView's
// "Validate" / "Retry" sub-actions.
private struct SecondaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.alignedSecondaryMini)
    }
}

// MARK: - API key row

private struct APIKeyEntry: Identifiable {
    let id = UUID()
    let label: String
    let masked: String
}

private struct APIKeyRow: View {
    let entry: APIKeyEntry
    @State private var isRevealed = false

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(entry.label)
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(displayValue)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Space.s1) {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isRevealed ? "Hide" : "Reveal")

                SecondaryButton(label: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.masked, forType: .string)
                }
            }
        }
        .padding(.vertical, Space.s3)
    }

    private var displayValue: String {
        // Phase 5 reads the unmasked secret from Keychain when revealed.
        // For v4.0.0 the masked value is the only stored representation.
        entry.masked
    }
}
