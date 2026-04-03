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
                    Text("v\(version)")
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
