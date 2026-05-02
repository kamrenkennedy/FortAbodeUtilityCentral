import SwiftUI
import AlignedDesignSystem

// Inline sidebar notification surfaced when Sparkle has staged an update for
// install-on-quit. Replaces both Sparkle's modal "update available" dialog
// (suppressed via SPUStandardUserDriverDelegate.supportsGentleScheduledUpdateReminders)
// and the floating-toast direction from prior specs. Modeled on Claude
// Desktop's update-available row at the bottom of its left rail.
//
// Renders nothing when no update is staged. When updateIsReady flips true,
// the row appears between the main nav and the Settings footer item; when
// the user clicks it, AppUpdaterService.installAndRelaunch() is invoked and
// Sparkle relaunches the app at the new version.
//
// Two visual variants keyed off AppState.sidebarCollapsed: a two-line tinted
// card in the 240pt expanded rail, and a single icon button in the 64pt
// collapsed rail.

struct SidebarUpdateRow: View {

    @Environment(AppUpdaterService.self) private var updaterService
    @Environment(AppState.self) private var appState

    var body: some View {
        if updaterService.updateIsReady && !updaterService.dismissedForSession {
            if appState.sidebarCollapsed {
                collapsed
            } else {
                expanded
            }
        }
    }

    // MARK: - Expanded (240pt rail)

    @State private var isHovering = false

    private var expanded: some View {
        Button(action: { updaterService.installAndRelaunch() }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.brandRust)
                        .frame(width: 16, height: 16)

                    Text("Update available")
                        .font(.bodySM.weight(.medium))
                        .foregroundStyle(Color.onSurface)

                    Spacer(minLength: 0)
                }

                Text("Relaunch to apply")
                    .font(.bodySM)
                    .foregroundStyle(Color.brandRust)
                    .padding(.leading, 16 + Space.s2)
            }
            .padding(.horizontal, Space.s2_5)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.brandRust.opacity(isHovering ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.brandRust.opacity(0.20), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help(tooltipText)
    }

    // MARK: - Collapsed (64pt rail)

    private var collapsed: some View {
        Button(action: { updaterService.installAndRelaunch() }) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.brandRust)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.brandRust.opacity(isHovering ? 0.12 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Color.brandRust.opacity(0.20), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help(tooltipText)
    }

    // MARK: - Tooltip

    private var tooltipText: String {
        if let version = updaterService.pendingVersion, !version.isEmpty {
            return "Restart Fort Abode to install version \(version)"
        }
        return "Restart Fort Abode to install the new version"
    }
}
