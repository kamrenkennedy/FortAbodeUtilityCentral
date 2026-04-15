import SwiftUI

// MARK: - Component Row View (kept for potential list mode toggle)

struct ComponentRowView: View {

    let component: Component
    let status: UpdateStatus

    @Environment(ComponentListViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.sfSymbolName)
                .font(.title2)
                .foregroundStyle(status.indicatorColor)
                .frame(width: 28)
                .symbolEffect(.pulse, isActive: status == .checking || status == .updating)

            VStack(alignment: .leading, spacing: 2) {
                Text(component.displayName)
                    .font(.headline)
                Text(component.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let version = status.installedVersion {
                    // Keychain-backed components (Travel Itinerary, etc.) return the
                    // literal "configured" / "installed" as their "version". Prefixing
                    // "v" would render as "vconfigured" — skip the prefix for those.
                    let displayText: String = {
                        if version == "configured" || version == "installed" {
                            return version.capitalized
                        }
                        return "v\(version)"
                    }()
                    Text(displayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                Text(status.statusText)
                    .font(.caption)
                    .foregroundStyle(status.indicatorColor)
            }

            if status.isUpdateAvailable {
                Button("Update") {
                    Task { await viewModel.updateComponent(component.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if status == .updating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 6)
    }
}
