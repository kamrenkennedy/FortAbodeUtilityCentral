import SwiftUI
import AlignedDesignSystem

// MARK: - Weekly Rhythm Skill Install Sheet (Phase 6.1)
//
// Surfaces when `WeeklyRhythmEngineStore.runNow()` finds the
// `weekly-rhythm-engine` plugin missing on the user's `claude` CLI. Two
// actions: Install & Run (kicks off the bundled-marketplace install flow,
// then runs the engine) or Cancel (returns to idle).
//
// Same chrome as `ClaudeCLIInstallSheet` — `AlignedSheet` with a setup
// eyebrow, terse copy that explains the mechanic, and a copy-paste-friendly
// fallback for users who'd rather drive the install themselves.

struct WeeklyRhythmSkillInstallSheet: View {

    let onInstallAndRun: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        AlignedSheet(
            eyebrow: "Setup",
            title: "Install the Weekly Rhythm Engine skill",
            badge: nil,
            idealWidth: 540,
            onDismiss: onDismiss,
            content: { contentBody },
            footer: { footerActions }
        )
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Fort Abode bundles the Weekly Rhythm Engine as a Claude Code plugin. The first time you run the engine on this Mac, the plugin needs to be registered with your local `claude` CLI.")
                .font(.bodyMD)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("What happens when you click Install & Run")
                    .font(.labelMD.weight(.medium))
                    .foregroundStyle(Color.onSurface)

                stepRow(number: "1", label: "Copy the bundled marketplace from Fort Abode to ~/Library/Application Support/")
                stepRow(number: "2", label: "Register it with `claude plugin marketplace add`")
                stepRow(number: "3", label: "Install with `claude plugin install weekly-rhythm-engine@fort-abode-marketplace`")
                stepRow(number: "4", label: "Run the engine")
            }

            Text("Each step is idempotent — re-running this is safe if anything goes wrong. The full output is logged for diagnostics.")
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepRow(number: String, label: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(number)
                .font(.labelSM.weight(.semibold))
                .foregroundStyle(Color.onSurfaceVariant)
                .frame(width: 16, alignment: .leading)
            Text(label)
                .font(.bodySM)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Spacer()
            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.alignedSecondaryMini)

            Button("Install & Run") {
                onInstallAndRun()
            }
            .buttonStyle(.alignedPrimary)
        }
    }
}
