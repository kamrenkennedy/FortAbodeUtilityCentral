import SwiftUI

// MARK: - Component Detail View

struct ComponentDetailView: View {

    let componentId: String

    @Environment(ComponentListViewModel.self) private var viewModel
    @State private var changelog: [ChangelogEntry] = []
    @State private var isLoadingChangelog = false
    @State private var showWizard = false
    @State private var instances: [String] = []
    @State private var manualInstallResult: PluginInstallResult = .notYetAttempted
    @State private var isManuallyInstalling = false
    @State private var showInstallOutput = false

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

                        // Connected Accounts (multi-instance)
                        if component.multiInstance == true, !instances.isEmpty {
                            Divider().opacity(0.3)
                            instancesSection(component)
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
            // Load instances and changelog in parallel
            async let changelogTask: () = loadChangelog()
            async let instancesTask: () = loadInstances()
            _ = await (changelogTask, instancesTask)
        }
        .sheet(isPresented: $showWizard) {
            if let component {
                SetupWizardView(
                    viewModel: SetupWizardViewModel(component: component),
                    onComplete: { inputs in
                        Task {
                            await viewModel.installComponentWithInputs(component.id, inputs: inputs)
                            await loadInstances()
                        }
                    }
                )
            }
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

            Spacer()

            // v3.7.6 "Install Plugin in Claude Code" button — replaces the broken
            // "Register in Claude" path. Instead of writing to Cowork's manifest.json
            // (which Cowork clobbers), this shells out to `claude plugin install` via
            // the Claude Code CLI with a bundled plugin marketplace shipped inside
            // Fort Abode's app bundle. Cowork then picks up the plugin through its
            // own plugin-discovery mechanism on next restart.
            if component.id == "weekly-rhythm", status.installedVersion != nil {
                Button {
                    Task {
                        isManuallyInstalling = true
                        manualInstallResult = await viewModel.installWeeklyRhythmPluginManually()
                        isManuallyInstalling = false
                    }
                } label: {
                    if isManuallyInstalling {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Installing…")
                        }
                    } else {
                        Label("Install Plugin in Claude Code", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isManuallyInstalling)
                .help("Install the Weekly Rhythm Engine as a Claude Code plugin. You'll need to quit and relaunch Claude Code after this completes.")
            }

            // Uninstall button — only for marketplace components that are installed
            if component.showInMarketplace, status.installedVersion != nil {
                Button(role: .destructive) {
                    Task { await viewModel.uninstallComponent(componentId) }
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }

        // Inline result of the manual plugin install button.
        // Shows a status line and a disclosure triangle with the raw CLI stdout/stderr
        // so Kam (or anyone debugging) can see exactly what `claude plugin install`
        // printed. The disclosure keeps the UI compact by default.
        if component.id == "weekly-rhythm", case .notYetAttempted = manualInstallResult {
            EmptyView()
        } else if component.id == "weekly-rhythm" {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: manualInstallResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(manualInstallResult.isSuccess ? .green : .orange)
                    Text(manualInstallResult.displayMessage)
                        .font(.caption)
                        .foregroundStyle(manualInstallResult.isSuccess ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let rawOutput = manualInstallResult.rawOutput {
                    DisclosureGroup(isExpanded: $showInstallOutput) {
                        ScrollView {
                            Text(rawOutput)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 200)
                        .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    } label: {
                        Text("Show CLI output")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.top, 4)
        }

        // Restart hint after install/uninstall
        if viewModel.showRestartHint {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.blue)
                Text("Restart Claude Desktop to activate changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
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

    // MARK: - Connected Accounts

    @ViewBuilder
    private func instancesSection(_ component: Component) -> some View {
        HStack {
            sectionHeader("Connected Accounts")
            Spacer()
            Button {
                showWizard = true
            } label: {
                Label("Add Account", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        VStack(spacing: 0) {
            ForEach(instances, id: \.self) { name in
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)

                    Text(name)
                        .font(.body)

                    Spacer()

                    Button(role: .destructive) {
                        Task {
                            await viewModel.removeInstance(componentId: componentId, instanceName: name)
                            await loadInstances()
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(name)")
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

                if name != instances.last {
                    Divider().opacity(0.2)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
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

    private func loadInstances() async {
        guard let component, component.multiInstance == true else { return }
        instances = await viewModel.installedInstances(for: component)
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
