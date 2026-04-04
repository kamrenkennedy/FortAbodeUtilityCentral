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
                // Glass card background
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

                // SF Symbol
                Image(systemName: component.iconName)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(iconForeground)
                    .symbolEffect(.pulse, isActive: status == .checking || status == .updating)

                // Update badge
                if status.isUpdateAvailable {
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
            }
            .frame(width: 80, height: 80)
            .scaleEffect(isHovering ? 1.06 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }

            // Name
            Text(component.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Version or status
            Text(versionLabel)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(versionColor)
                .lineLimit(1)
        }
        .frame(width: 110)
        .onTapGesture {
            handleTap()
        }
        .contextMenu {
            Button("Check for Updates") {
                Task { await viewModel.checkSingleComponent(component.id) }
            }

            if status.isUpdateAvailable {
                Button("Update") {
                    Task { await viewModel.updateComponent(component.id) }
                }
            }

            Divider()

            Text(component.description)
        }
    }

    // MARK: - Styling

    private var iconBackgroundGradient: some ShapeStyle {
        switch status {
        case .updateAvailable:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.orange.opacity(0.12), .orange.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .upToDate, .updateComplete:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.green.opacity(0.08), .green.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .error:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.red.opacity(0.1), .red.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .checkFailed:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.yellow.opacity(0.08), .yellow.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        default:
            return AnyShapeStyle(Color.clear)
        }
    }

    private var iconForeground: some ShapeStyle {
        switch status {
        case .upToDate, .updateComplete:
            return AnyShapeStyle(.white.opacity(0.9))
        case .updateAvailable:
            return AnyShapeStyle(.orange)
        case .error:
            return AnyShapeStyle(.red.opacity(0.8))
        case .checkFailed:
            return AnyShapeStyle(.yellow.opacity(0.7))
        case .checking, .updating:
            return AnyShapeStyle(.white.opacity(0.5))
        default:
            return AnyShapeStyle(.white.opacity(0.6))
        }
    }

    private var shadowColor: Color {
        switch status {
        case .updateAvailable: return .orange.opacity(0.2)
        case .upToDate, .updateComplete: return .green.opacity(0.1)
        case .checkFailed: return .yellow.opacity(0.1)
        case .error: return .red.opacity(0.15)
        default: return .black.opacity(0.15)
        }
    }

    private var versionLabel: String {
        switch status {
        case .upToDate(let version), .updateComplete(let version):
            return Self.formatVersion(version)
        case .updateAvailable(let installed, let latest):
            return "\(Self.formatVersion(installed)) \u{2192} \(Self.formatVersion(latest))"
        case .checkFailed(let version):
            return "\(Self.formatVersion(version)) \u{2022} offline"
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

    /// Format a version string — prepend "v" only for semver strings, not words like "configured"
    private static func formatVersion(_ version: String) -> String {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        if let first = cleaned.first, first.isNumber {
            return "v\(cleaned)"
        }
        return cleaned
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

    // MARK: - Actions

    private func handleTap() {
        if status.isUpdateAvailable {
            Task { await viewModel.updateComponent(component.id) }
        } else {
            Task { await viewModel.checkSingleComponent(component.id) }
        }
    }
}
