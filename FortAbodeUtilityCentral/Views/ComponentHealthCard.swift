import SwiftUI
import AlignedDesignSystem

// MARK: - Component Health Card

/// Renders the per-component operational health rows (e.g. installed,
/// configured, Full Disk Access). Sibling to the version status line — this
/// surfaces "can the component actually do its job right now" rather than
/// "what version is installed".
struct ComponentHealthCard: View {

    let checks: [HealthCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                HStack(spacing: 10) {
                    Image(systemName: iconName(for: check.state))
                        .foregroundStyle(iconColor(for: check.state))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18)

                    Text(check.label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    if let url = check.actionDeepLink {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text("Open System Settings")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .medium))
                            }
                        }
                        .buttonStyle(.alignedSecondaryMini)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

                if index < checks.count - 1 {
                    Divider().opacity(0.2)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private func iconName(for state: HealthState) -> String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func iconColor(for state: HealthState) -> Color {
        switch state {
        case .granted: return .green
        case .missing: return .red
        case .unknown: return .secondary
        }
    }
}
