import SwiftUI
import AlignedDesignSystem

// MARK: - Weekly Rhythm Run Control (Phase 6)
//
// Replaces the bare `RunHealthPill` overlay on `WeeklyRhythmView`'s editorial
// header. Three pieces:
//
//   1. The existing pill — still tappable, still opens `RunHealthDetailSheet`.
//   2. A primary "Run" button — calls `engineStore.runNow()` and reflects the
//      run lifecycle (Running… → done). When the CLI isn't detected the same
//      slot becomes "Install Claude CLI" and opens the install instructions
//      sheet.
//   3. A schedule menu — Off / Friday morning / Saturday morning / Custom…
//      Selecting an option installs (or removes) the engine LaunchAgent via
//      `BackgroundTaskService` and pins the choice to `@AppStorage`.

struct WeeklyRhythmRunControl: View {

    let pillState: RunHealthPill.State
    let onPillTap: () -> Void

    @Environment(WeeklyRhythmEngineStore.self) private var engineStore

    @AppStorage(AppSettingsKey.weeklyRhythmEngineScheduleEnabled)  private var scheduleEnabled: Bool = false
    @AppStorage(AppSettingsKey.weeklyRhythmEngineScheduleHour)     private var scheduleHour: Int = 8
    @AppStorage(AppSettingsKey.weeklyRhythmEngineScheduleWeekday)  private var scheduleWeekday: Int = 5 // launchd convention: 5 = Friday

    @State private var installSheetOpen: Bool = false

    var body: some View {
        HStack(spacing: Space.s2) {
            Button(action: onPillTap) {
                RunHealthPill(state: pillState)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Run Health detail")

            runButton

            if isCLIInstalled {
                scheduleMenu
            }
        }
        .sheet(isPresented: $installSheetOpen) {
            ClaudeCLIInstallSheet(onDismiss: { installSheetOpen = false })
                .frame(minWidth: 480, idealWidth: 540, minHeight: 320, idealHeight: 380)
        }
    }

    // MARK: - Run button

    @ViewBuilder
    private var runButton: some View {
        if !isCLIInstalled {
            Button("Install Claude CLI") {
                installSheetOpen = true
            }
            .buttonStyle(.alignedSecondaryMini)
        } else if isRunning {
            HStack(spacing: Space.s1_5) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
                Text("Running…")
                    .font(.labelMD.weight(.medium))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s1_5)
            .background(
                Capsule().fill(Color.surfaceContainerHigh)
            )
        } else {
            Button("Run") {
                Task { await engineStore.runNow() }
            }
            .buttonStyle(.alignedSecondaryMini)
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

    // MARK: - Schedule menu

    private var scheduleMenu: some View {
        Menu {
            Button {
                applySchedule(.off)
            } label: {
                Label("Off", systemImage: scheduleEnabled ? "" : "checkmark")
            }
            Button {
                applySchedule(.fridayMorning)
            } label: {
                Label("Friday morning (8 AM)", systemImage: isCurrent(.fridayMorning) ? "checkmark" : "")
            }
            Button {
                applySchedule(.saturdayMorning)
            } label: {
                Label("Saturday morning (8 AM)", systemImage: isCurrent(.saturdayMorning) ? "checkmark" : "")
            }
        } label: {
            HStack(spacing: Space.s1) {
                Text(scheduleLabel)
                    .font(.labelMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s1_5)
            .background(
                Capsule().fill(Color.surfaceContainerHigh)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Engine schedule")
    }

    private var scheduleLabel: String {
        guard scheduleEnabled else { return "Schedule: Off" }
        let day = WeeklyRhythmEngineSchedule.label(forLaunchdWeekday: scheduleWeekday)
        return "\(day) \(scheduleHour) AM"
    }

    private func isCurrent(_ option: WeeklyRhythmEngineSchedule) -> Bool {
        guard scheduleEnabled else { return false }
        return option.launchdWeekday == scheduleWeekday && option.hour == scheduleHour
    }

    private func applySchedule(_ option: WeeklyRhythmEngineSchedule) {
        switch option {
        case .off:
            scheduleEnabled = false
            BackgroundTaskService.shared.removeEngineLaunchAgent()
        case .fridayMorning, .saturdayMorning:
            scheduleEnabled = true
            scheduleWeekday = option.launchdWeekday
            scheduleHour = option.hour
            BackgroundTaskService.shared.installEngineLaunchAgent(
                weekday: option.launchdWeekday,
                hour: option.hour
            )
        }
    }
}

// MARK: - Schedule preset
//
// Public so the Settings section can share the same enum. launchd's
// StartCalendarInterval uses 0–7 where 0 and 7 are both Sunday — Friday is 5.
// We do NOT use `Calendar.weekday` (1–7, Sunday=1) because the value goes
// straight into the plist.

public enum WeeklyRhythmEngineSchedule {
    case off
    case fridayMorning
    case saturdayMorning

    var launchdWeekday: Int {
        switch self {
        case .off:              return 0
        case .fridayMorning:    return 5
        case .saturdayMorning:  return 6
        }
    }

    var hour: Int {
        switch self {
        case .off:              return 0
        case .fridayMorning:    return 8
        case .saturdayMorning:  return 8
        }
    }

    static func label(forLaunchdWeekday weekday: Int) -> String {
        switch weekday {
        case 0, 7: return "Sunday"
        case 1: return "Monday"
        case 2: return "Tuesday"
        case 3: return "Wednesday"
        case 4: return "Thursday"
        case 5: return "Friday"
        case 6: return "Saturday"
        default: return "Custom"
        }
    }
}

// MARK: - CLI install sheet
//
// Surfaces when the user taps "Install Claude CLI" because no `claude` binary
// was found. Copy + Open Terminal handoff — Fort Abode never installs the CLI
// itself (per Phase 6 decision: detect-then-install, no bundled binary).

private struct ClaudeCLIInstallSheet: View {
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
            Text("Fort Abode runs the Weekly Rhythm Engine through your local `claude` CLI. Once it's on your PATH the Run button starts working — no app restart needed.")
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

            Text("If you don't have Homebrew, install it first from brew.sh, then re-run the command above. Already installed? Make sure `claude` is on your PATH (run `which claude` in a terminal).")
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
