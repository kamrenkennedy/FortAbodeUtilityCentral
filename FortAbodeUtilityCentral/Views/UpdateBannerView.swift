import SwiftUI

// MARK: - Update Banner
//
// Inline banner shown above the footer when Sparkle has staged an app update and
// is waiting to install. "Install Now" calls Sparkle's immediate-install block
// (relaunch into the new version). "Later" dismisses the banner for this session;
// it re-appears on next launch as long as the update is still pending.

struct UpdateBannerView: View {

    let pendingVersion: String?
    let onInstall: () -> Void
    let onLater: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("Install now to apply this update.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Later", action: onLater)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Button(action: onInstall) {
                Text("Install Now")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.green)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.green.opacity(0.12))
    }

    private var headline: String {
        if let pendingVersion {
            "Fort Abode \(pendingVersion) is ready"
        } else {
            "Fort Abode update is ready"
        }
    }
}
