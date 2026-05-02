import SwiftUI
import AlignedDesignSystem

// MARK: - Missing MCPs Sheet (Phase 6.1)
//
// Surfaces when `MCPProbe` reports that the engine's required capabilities
// (Gmail / Calendar / Reminders / Memory / Notion) aren't covered by any of
// the user's connected MCPs. Two actions: Run anyway (the engine might
// partial-succeed) or Open Marketplace (route the user to set things up).
//
// Heuristic-driven, not authoritative — Phase 6.1's MCPProbe maps each
// requirement to a set of plausible MCP names, and we only warn when the
// union is empty. The user can always run anyway.

struct MissingMCPsSheet: View {

    let missing: [MCPProbe.Requirement]
    let onRunAnyway: () -> Void
    let onOpenMarketplace: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        AlignedSheet(
            eyebrow: "Heads up",
            title: "Some MCPs aren't connected",
            badge: nil,
            idealWidth: 540,
            onDismiss: onDismiss,
            content: { contentBody },
            footer: { footerActions }
        )
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("The Weekly Rhythm Engine usually pulls from a handful of MCPs to plan your week. Fort Abode couldn't find one for:")
                .font(.bodyMD)
                .foregroundStyle(Color.onSurface)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(missing) { requirement in
                    HStack(alignment: .center, spacing: Space.s2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.statusDraft)
                        Text(requirement.displayName)
                            .font(.bodyMD)
                            .foregroundStyle(Color.onSurface)
                    }
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color.surfaceContainerHigh)
            )

            Text("This is a heuristic — Fort Abode looks for MCPs by name. If you've configured a different MCP that provides these capabilities, you can run anyway. The engine itself will tell you if a tool is actually missing.")
                .font(.bodySM)
                .foregroundStyle(Color.onSurfaceVariant)
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

            Button("Open Marketplace") {
                onOpenMarketplace()
            }
            .buttonStyle(.alignedSecondaryMini)

            Button("Run anyway") {
                onRunAnyway()
            }
            .buttonStyle(.alignedPrimary)
        }
    }
}
