import SwiftUI
import AlignedDesignSystem

// MARK: - Weekly Rhythm Engine — Settings section (Phase 6)
//
// Sits between the App Updates and Account sections in `SettingsView`.
// Mirrors the controls on the Weekly Rhythm tab's run pill (CLI status, run
// now, schedule dropdown, surface-on-completion toggle) plus a last-run row
// for cross-reference.

struct WeeklyRhythmEngineSection: View {

    @Environment(WeeklyRhythmEngineStore.self) private var engineStore

    @AppStorage(AppSettingsKey.weeklyRhythmEngineScheduleEnabled)   private var scheduleEnabled: Bool = false
    @AppStorage(AppSettingsKey.weeklyRhythmEngineScheduleHour)      private var scheduleHour: Int = 8
    @AppStorage(AppSettingsKey.weeklyRhythmEngineScheduleWeekday)   private var scheduleWeekday: Int = 5
    @AppStorage(AppSettingsKey.weeklyRhythmEngineSurfaceOnCompletion) private var surfaceOnCompletion: Bool = true
    @AppStorage(AppSettingsKey.weeklyRhythmEngineLastRunAt)         private var lastRunAtTimestamp: Double = 0
    @AppStorage(AppSettingsKey.weeklyRhythmEngineLastRunSucceeded)  private var lastRunSucceeded: Bool = false
    @AppStorage(AppSettingsKey.weeklyRhythmEngineLastRunSummary)    private var lastRunSummary: String = ""

    @State private var installSheetOpen: Bool = false
    @State private var detecting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            SectionEyebrow(text: "Weekly Rhythm Engine")

            DashboardCard(verticalPadding: Space.s2, horizontalPadding: Space.s6) {
                VStack(spacing: 0) {
                    cliStatusRow
                    RowSeparator()
                    runNowRow
                    RowSeparator()
                    scheduleRow
                    RowSeparator()
                    surfaceOnCompletionRow
                    RowSeparator()
                    lastRunRow
                }
            }
        }
        .sheet(isPresented: $installSheetOpen) {
            ClaudeCLIInstallInstructionsSheet(onDismiss: { installSheetOpen = false })
                .frame(minWidth: 480, idealWidth: 540, minHeight: 320, idealHeight: 380)
        }
    }

    // MARK: - Rows

    private var cliStatusRow: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Claude CLI")
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(cliStatusSubtitle)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            HStack(spacing: Space.s2) {
                Button(detecting ? "Detecting…" : "Re-detect") {
                    Task {
                        detecting = true
                        await engineStore.detectCLI()
                        detecting = false
                    }
                }
                .buttonStyle(.alignedSecondaryMini)
                .disabled(detecting)

                if !isCLIInstalled {
                    Button("Install") {
                        installSheetOpen = true
                    }
                    .buttonStyle(.alignedSecondaryMini)
                }
            }
        }
        .padding(.vertical, Space.s4)
    }

    private var runNowRow: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Run engine now")
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text("Spawns the embedded Claude CLI and runs the Weekly Rhythm Engine in the background.")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            if isRunning {
                HStack(spacing: Space.s2) {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                    Text("Running…")
                        .font(.labelMD)
                        .foregroundStyle(Color.onSurfaceVariant)
                }
            } else {
                Button("Run") {
                    Task { await engineStore.runNow() }
                }
                .buttonStyle(.alignedSecondaryMini)
                .disabled(!isCLIInstalled)
            }
        }
        .padding(.vertical, Space.s4)
    }

    private var scheduleRow: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Schedule")
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text("Run automatically at a fixed time each week. Fires even when Fort Abode is closed.")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            Picker("", selection: scheduleSelectionBinding) {
                Text("Off").tag(SchedulePreset.off)
                Text("Friday 8 AM").tag(SchedulePreset.fridayMorning)
                Text("Saturday 8 AM").tag(SchedulePreset.saturdayMorning)
            }
            .labelsHidden()
            .frame(width: 160)
            .disabled(!isCLIInstalled)
        }
        .padding(.vertical, Space.s4)
    }

    private var surfaceOnCompletionRow: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Notify when run finishes")
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text("Posts a macOS notification on completion. Tap it to deep-link to the Weekly Rhythm tab.")
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)

            Toggle("", isOn: $surfaceOnCompletion)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, Space.s4)
    }

    private var lastRunRow: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Last run")
                    .font(.bodyMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Text(lastRunSubtitle)
                    .font(.bodySM)
                    .foregroundStyle(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.s2)
        }
        .padding(.vertical, Space.s4)
    }

    // MARK: - Computed state

    private var cliStatusSubtitle: String {
        switch engineStore.cliDetection {
        case .found(let path, let version):
            return "Detected at \(path) (\(version))"
        case .notFound:
            return "Not found on PATH or in common install locations. Install to enable scheduled runs."
        }
    }

    private var isCLIInstalled: Bool {
        if case .found = engineStore.cliDetection { return true }
        return false
    }

    private var isRunning: Bool {
        if case .running = engineStore.runState { return true }
        return false
    }

    private var lastRunSubtitle: String {
        guard lastRunAtTimestamp > 0 else {
            return "Never run from Fort Abode."
        }
        let date = Date(timeIntervalSince1970: lastRunAtTimestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        let outcome = lastRunSucceeded ? "succeeded" : "failed"
        let trimmedSummary = lastRunSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = trimmedSummary.isEmpty ? "" : " · \(trimmedSummary)"
        return "\(relative) — \(outcome)\(summary)"
    }

    // MARK: - Schedule preset binding

    private enum SchedulePreset: Hashable {
        case off
        case fridayMorning
        case saturdayMorning
    }

    private var scheduleSelectionBinding: Binding<SchedulePreset> {
        Binding(
            get: {
                guard scheduleEnabled else { return .off }
                if scheduleWeekday == 5 && scheduleHour == 8 { return .fridayMorning }
                if scheduleWeekday == 6 && scheduleHour == 8 { return .saturdayMorning }
                return .off
            },
            set: { newValue in
                switch newValue {
                case .off:
                    scheduleEnabled = false
                    BackgroundTaskService.shared.removeEngineLaunchAgent()
                case .fridayMorning:
                    scheduleEnabled = true
                    scheduleWeekday = 5
                    scheduleHour = 8
                    BackgroundTaskService.shared.installEngineLaunchAgent(weekday: 5, hour: 8)
                case .saturdayMorning:
                    scheduleEnabled = true
                    scheduleWeekday = 6
                    scheduleHour = 8
                    BackgroundTaskService.shared.installEngineLaunchAgent(weekday: 6, hour: 8)
                }
            }
        )
    }
}

// MARK: - Install sheet
//
// Same content as the Weekly Rhythm tab's install sheet — keeps both surfaces
// pointing at the same instructions so the user gets the same answer no matter
// which entry point they hit.

private struct ClaudeCLIInstallInstructionsSheet: View {
    let onDismiss: () -> Void

    private let installCommand = "brew install claude-code"

    var body: some View {
        AlignedSheet(
            eyebrow: "Setup",
            title: "Install the Claude CLI",
            badge: nil,
            idealWidth: 540,
            onDismiss: onDismiss,
            content: { contentBody },
            footer: { footerActions }
        )
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Fort Abode runs the Weekly Rhythm Engine through your local `claude` CLI. Once it's on your PATH the Run controls start working — no app restart needed.")
                .font(.bodyMD)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Install with Homebrew")
                    .font(.labelMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)

                HStack(spacing: Space.s2) {
                    Text(installCommand)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, Space.s2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.surfaceContainerHigh)
                        )

                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                    }
                    .buttonStyle(.alignedSecondaryMini)
                }
            }

            Text("If you don't have Homebrew, install it from brew.sh first. Already installed? Run `which claude` in a terminal and confirm the path is on your shell's PATH.")
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Spacer()
            Button("Open Terminal") {
                if let terminal = URL(string: "file:///System/Applications/Utilities/Terminal.app") {
                    NSWorkspace.shared.open(terminal)
                }
            }
            .buttonStyle(.alignedSecondaryMini)

            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.alignedPrimary)
        }
    }
}
