import SwiftUI

// MARK: - Component Card View (Icon Gallery Item)

struct ComponentCardView: View {

    let component: Component
    let status: UpdateStatus

    @Environment(ComponentListViewModel.self) private var viewModel
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(iconBackgroundGradient)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    }
                    .shadow(color: shadowColor, radius: isHovering ? 12 : 6, y: isHovering ? 4 : 2)

                Image(systemName: component.iconName)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(iconForeground)
                    .symbolEffect(.pulse, isActive: status == .checking || status == .updating)

                // Health-failure badge (red exclamation) takes precedence over
                // update-available — a missing permission is a hard block.
                if hasHealthFailure {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white, .red)
                        .shadow(color: .red.opacity(0.5), radius: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                } else if status.isUpdateAvailable {
                    // Update available badge (orange dot)
                    Circle()
                        .fill(.orange)
                        .frame(width: 12, height: 12)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
                        }
                        .shadow(color: .orange.opacity(0.5), radius: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }

                // "Updated" badge (blue capsule) — shown after a successful update until user views detail
                if viewModel.badgeTracker.hasBadge(component.id) && !status.isUpdateAvailable {
                    Text("Updated")
                        .font(.system(size: 7, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(4)
                }
            }
            .frame(width: 80, height: 80)
            .scaleEffect(isHovering ? 1.06 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }

            Text(component.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(versionLabel)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(versionColor)
                .lineLimit(1)
        }
        .frame(width: 110)
    }

    // MARK: - Health

    private var hasHealthFailure: Bool {
        viewModel.healthChecks[component.id]?.contains(where: { $0.state == .missing }) == true
    }

    // MARK: - Styling

    private var iconBackgroundGradient: some ShapeStyle {
        if isHovering {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.green.opacity(0.10), .green.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.clear)
    }

    private var iconForeground: some ShapeStyle {
        switch status {
        case .checking, .updating:
            return AnyShapeStyle(.white.opacity(0.5))
        default:
            return AnyShapeStyle(isHovering ? .white.opacity(0.95) : .white.opacity(0.7))
        }
    }

    private var shadowColor: Color {
        if isHovering {
            return .green.opacity(0.15)
        }
        return .black.opacity(0.15)
    }

    private var versionLabel: String {
        switch status {
        case .upToDate(let version), .updateComplete(let version):
            return VersionFormatter.format(version)
        case .updateAvailable(let installed, let latest):
            return "\(VersionFormatter.format(installed)) \u{2192} \(VersionFormatter.format(latest))"
        case .checkFailed(let version):
            return "\(VersionFormatter.format(version)) \u{2022} offline"
        case .checking:
            return "checking..."
        case .updating:
            return "updating..."
        case .notInstalled:
            return "not installed"
        case .error:
            return "error"
        case .unknown:
            return "\u{2014}"
        }
    }

    private var versionColor: Color {
        switch status {
        case .upToDate, .updateComplete: return .green.opacity(0.8)
        case .updateAvailable: return .orange
        case .checkFailed: return .yellow.opacity(0.7)
        case .error: return .red.opacity(0.8)
        default: return .secondary
        }
    }
}
