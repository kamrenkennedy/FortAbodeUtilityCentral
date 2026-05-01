import SwiftUI
import AlignedDesignSystem

// Inline banner that surfaces engine `RunHealth.warning` / `.error` messages
// inline with the page content. Renders nothing when health is `.allGood` or
// when the user has dismissed the current message during this session.
//
// Dismissal is per-session: the dismissed-message-hash is stored in
// UserDefaults but cleared on app launch (see AppDelegate). Within one
// session, dismissing a warning hides it until either:
//   • the engine emits a NEW message (different hash → bypasses dismiss)
//   • the app relaunches (UserDefault cleared → all messages re-show)
//
// Placement is intentional: above the alerts section on Weekly Rhythm and
// below the editorial header on Home, so degradation is visible from both
// surfaces a user might land on after launch.

struct EngineAttentionBanner: View {
    let runHealth: RunHealth

    @State private var dismissedHash: String?

    static let userDefaultKey = "engineAttentionBanner.dismissedMessageHash"

    /// Clear any persisted dismissal on app launch so the banner re-shows
    /// even for the same message string. Called from
    /// `AppDelegate.applicationDidFinishLaunching` so window-close-then-open
    /// preserves dismissal but a real relaunch surfaces the warning again.
    static func clearDismissalOnLaunch() {
        UserDefaults.standard.removeObject(forKey: userDefaultKey)
    }

    var body: some View {
        if let display = displayContent {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: display.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(display.iconColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(display.title)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.onSurface)
                    Text(display.message)
                        .font(.bodySM)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.s3)

                Button {
                    let hash = currentMessageHash
                    UserDefaults.standard.set(hash, forKey: Self.userDefaultKey)
                    dismissedHash = hash
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.onSurfaceVariant)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(display.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(display.border, lineWidth: 1)
            )
            .onAppear {
                dismissedHash = UserDefaults.standard.string(forKey: Self.userDefaultKey)
            }
        }
    }

    // MARK: - Display computation

    private struct DisplayContent {
        let title: String
        let message: String
        let symbol: String
        let iconColor: Color
        let background: Color
        let border: Color
    }

    private var displayContent: DisplayContent? {
        switch runHealth {
        case .allGood:
            return nil
        case .warning(let msg):
            guard !isDismissed, !msg.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return DisplayContent(
                title: "Engine running with reduced data",
                message: msg,
                symbol: "exclamationmark.triangle.fill",
                iconColor: Color.statusDraft,
                background: Color.statusDraft.opacity(0.08),
                border: Color.statusDraft.opacity(0.30)
            )
        case .error(let msg):
            guard !isDismissed, !msg.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return DisplayContent(
                title: "Engine attention needed",
                message: msg,
                symbol: "xmark.octagon.fill",
                iconColor: Color.statusError,
                background: Color.statusError.opacity(0.08),
                border: Color.statusError.opacity(0.30)
            )
        }
    }

    private var isDismissed: Bool {
        guard let dismissedHash, !currentMessageHash.isEmpty else { return false }
        return dismissedHash == currentMessageHash
    }

    private var currentMessageHash: String {
        switch runHealth {
        case .allGood:           return ""
        case .warning(let msg):  return "warn:\(msg)"
        case .error(let msg):    return "err:\(msg)"
        }
    }
}
