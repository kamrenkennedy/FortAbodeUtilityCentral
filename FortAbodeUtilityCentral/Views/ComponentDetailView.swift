import SwiftUI

// MARK: - Component Detail View

struct ComponentDetailView: View {

    let componentId: String

    @Environment(ComponentListViewModel.self) private var viewModel
    @State private var changelog: [ChangelogEntry] = []
    @State private var isLoadingChangelog = false

    private var component: Component? {
        viewModel.registry.component(withId: componentId)
    }

    private var status: UpdateStatus {
        viewModel.statuses[componentId] ?? .unknown
    }

    var body: some View {
        Group {
            if let component {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header: icon + name + description
                        headerSection(component)

                        Divider().opacity(0.3)

                        // How to Use
                        if let instructions = component.usageInstructions, !instructions.isEmpty {
                            sectionHeader("How to Use")
                            Text(instructions)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Included Servers (for multi-server packages)
                        if let servers = component.includedServers, !servers.isEmpty {
                            Divider().opacity(0.3)
                            sectionHeader("Included Servers")
                            ForEach(servers, id: \.name) { server in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "server.rack")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.subheadline.bold())
                                        Text(server.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        // Actions
                        Divider().opacity(0.3)
                        actionsSection(component)

                        // Changelog
                        Divider().opacity(0.3)
                        changelogSection

                        Spacer(minLength: 20)
                    }
                    .padding(28)
                }
            } else {
                Text("Component not found")
                    .foregroundStyle(.secondary)
            }
        }
        .background {
            VisualEffectBackground().ignoresSafeArea()
        }
        .navigationTitle(component?.displayName ?? "Detail")
        .task {
            // Clear the "Updated" badge when user views detail
            viewModel.badgeTracker.clearBadge(componentId: componentId)
            // Fetch changelog
            await loadChangelog()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ component: Component) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Large icon
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.08), .green.opacity(0.02)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    }

                Image(systemName: component.iconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 6) {
                Text(component.displayName)
                    .font(.title2.bold())

                if let version = status.installedVersion {
                    Text(VersionFormatter.format(version))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.green)
                }

                Text(component.userDescription ?? component.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionsSection(_ component: Component) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.checkSingleComponent(componentId) }
            } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(status == .checking)

            if status.isUpdateAvailable {
                Button {
                    Task { await viewModel.updateComponent(componentId) }
                } label: {
                    Label("Update", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.orange)
            }

            if status == .updating {
                ProgressView()
                    .controlSize(.small)
            }

            if case .error(let message) = status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Changelog

    @ViewBuilder
    private var changelogSection: some View {
        sectionHeader("What's New")

        if isLoadingChangelog {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading changelog...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if changelog.isEmpty {
            Text("No changelog available.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(changelog) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("v\(entry.version)")
                                .font(.subheadline.bold().monospaced())
                            if let date = entry.date {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(markdownBody(entry.body))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .tracking(1)
    }

    private func markdownBody(_ body: String) -> AttributedString {
        (try? AttributedString(markdown: body)) ?? AttributedString(body)
    }

    private func loadChangelog() async {
        guard let component else { return }
        isLoadingChangelog = true
        changelog = await viewModel.gitHubService.fetchChangelog(
            for: component.updateSource,
            componentId: componentId
        )
        isLoadingChangelog = false
    }
}

// MARK: - Version Formatting Utility

enum VersionFormatter {
    static func format(_ version: String) -> String {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        if let first = cleaned.first, first.isNumber {
            return "v\(cleaned)"
        }
        return cleaned
    }
}
