import SwiftUI
import AlignedDesignSystem

// MARK: - Component Detail View

struct ComponentDetailView: View {

    let componentId: String

    @Environment(ComponentListViewModel.self) private var viewModel
    @State private var changelog: [ChangelogEntry] = []
    @State private var isLoadingChangelog = false
    @State private var showWizard = false
    @State private var instances: [String] = []
    @State private var copiedToClipboard = false

    private var component: Component? {
        viewModel.registry.component(withId: componentId)
    }

    private var status: UpdateStatus {
        viewModel.statuses[componentId] ?? .unknown
    }

    private var updateButtonLabel: String {
        if case .updateAvailable(_, let latest) = status {
            return "Install update to \(VersionFormatter.format(latest))"
        }
        return "Install update"
    }

    var body: some View {
        Group {
            if let component {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header: icon + name + description
                        headerSection(component)

                        // Operational health (e.g. Full Disk Access for iMessage).
                        // Only renders when the component declares health checks.
                        if let checks = viewModel.healthChecks[componentId], !checks.isEmpty {
                            Divider().opacity(0.3)
                            sectionHeader("Status")
                            ComponentHealthCard(checks: checks)
                        }

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
                                        .foregroundStyle(Color.statusScheduled)
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

                        // Connected Accounts — between description block and action row
                        // per UPDATE-2026-04-25.md. Renders for any multi-account MCP;
                        // empty state surfaces a primary "Connect account" CTA.
                        if component.multiInstance == true {
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
            Color.surface.ignoresSafeArea()
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
                    .fill(Color.surfaceContainerHigh)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.outlineVariant.opacity(0.4), lineWidth: 1)
                    }

                Image(systemName: component.iconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.onSurfaceVariant)
            }
            .frame(width: 100, height: 100)

            VStack(alignment: .leading, spacing: 6) {
                Text(component.displayName)
                    .font(.title2.bold())

                if let version = status.installedVersion {
                    Text(VersionFormatter.format(version))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Color.statusScheduled)
                }

                Text(component.userDescription ?? component.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    // Action row order per UPDATE-2026-04-25.md (Gmail reference layout):
    //   [primary "Install update to vX"] [secondary "Check for Updates"]
    //   [...spacer...] [secondary destructive "Uninstall"]
    // — Primary appears only when status === .update.
    // — Update button uses standard primary (near-black) — NOT amber.
    //   The amber statusDraft dot still represents "update available" upstream;
    //   the button itself is monochrome by design rule.
    @ViewBuilder
    private func actionsSection(_ component: Component) -> some View {
        HStack(spacing: 12) {
            if status.isUpdateAvailable {
                Button {
                    Task { await viewModel.updateComponent(componentId) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .medium))
                        Text(updateButtonLabel)
                    }
                }
                .buttonStyle(.alignedPrimary)
                .disabled(status == .updating)
                .opacity(status == .updating ? 0.7 : 1)
            }

            Button {
                Task { await viewModel.checkSingleComponent(componentId) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text("Check for Updates")
                }
            }
            .buttonStyle(.alignedSecondary)
            .disabled(status == .checking)
            .opacity(status == .checking ? 0.7 : 1)

            if status == .updating {
                ProgressView()
                    .controlSize(.small)
            }

            if case .error(let message) = status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(2)
            }

            Spacer()

            // v3.7.9: copy setup instructions to clipboard. The user pastes them
            // into a Cowork session, and Cowork's own Claude handles the skill
            // registration by reading engine-spec.md from iCloud and writing
            // SKILL.md to ~/.claude/skills/. This is the only approach that works
            // — Cowork ignores files written by external apps.
            if component.id == "weekly-rhythm", status.installedVersion != nil {
                Button {
                    viewModel.copyWeeklyRhythmSetupInstructions()
                    copiedToClipboard = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.clipboard")
                            .font(.system(size: 11, weight: .medium))
                        Text(copiedToClipboard ? "Copied!" : "Copy Setup Instructions")
                    }
                }
                .buttonStyle(.alignedSecondary)
                .help("Copy skill setup instructions to clipboard. Paste into a Claude session to register the Weekly Rhythm skill.")
            }

            // Uninstall — destructive secondary. Only for installed marketplace components.
            if component.showInMarketplace, status.installedVersion != nil {
                Button {
                    Task { await viewModel.uninstallComponent(componentId) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                        Text("Uninstall")
                    }
                }
                .buttonStyle(.alignedSecondaryDestructive)
            }
        }

        // Inline hint after copying setup instructions.
        if component.id == "weekly-rhythm", copiedToClipboard {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.tertiary)
                Text("Open Claude, start a new task, and paste with ⌘V. Claude will set up the skill for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }

        // Restart hint after install/uninstall
        if viewModel.showRestartHint {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(Color.tertiary)
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
    //
    // Spec (UPDATE-2026-04-25.md §2a):
    //   • 24pt circle avatar in `tertiary` slate, white initial
    //   • body-md weight 500 name, optionally suffixed with " — workspace name"
    //   • Ghost × icon button per row (`onSurfaceVariant`, hover reveals
    //     `surfaceContainerHigh` background)
    //   • 1pt outlineVariant separator between rows
    //   • Hover row: `surfaceContainer` bg with 8pt radius
    //   • Empty state: "No accounts connected" + primary "Connect account" CTA;
    //     the "+ Add Account" header button is still present.

    @ViewBuilder
    private func instancesSection(_ component: Component) -> some View {
        HStack {
            sectionHeader("Connected Accounts")
            Spacer()
            Button {
                showWizard = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("Add Account")
                }
            }
            .buttonStyle(.alignedSecondary)
        }

        if instances.isEmpty {
            instancesEmptyState
        } else {
            VStack(spacing: 0) {
                ForEach(Array(instances.enumerated()), id: \.element) { index, name in
                    InstanceRow(
                        name: name,
                        onRemove: {
                            Task {
                                await viewModel.removeInstance(componentId: componentId, instanceName: name)
                                await loadInstances()
                            }
                        }
                    )

                    if index < instances.count - 1 {
                        Rectangle()
                            .fill(Color.outlineVariant.opacity(0.5))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var instancesEmptyState: some View {
        VStack(spacing: 12) {
            Text("No accounts connected")
                .font(.bodyMD)
                .foregroundStyle(Color.onSurfaceVariant)

            Button {
                showWizard = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("Connect account")
                }
            }
            .buttonStyle(.alignedPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

// MARK: - Connected Account Row
//
// Per UPDATE-2026-04-25.md §2a per-row spec — extracted because we need
// per-row hover state.

private struct InstanceRow: View {
    let name: String
    let onRemove: () -> Void

    @State private var isHoveringRow = false
    @State private var isHoveringRemove = false

    private var initial: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.tertiary)
                Text(initial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.onTertiary)
            }
            .frame(width: 24, height: 24)

            Text(name)
                .font(.bodyMD.weight(.medium))
                .foregroundStyle(Color.onSurface)

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.onSurfaceVariant)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(isHoveringRemove ? Color.surfaceContainerHigh : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringRemove = $0 }
            .help("Disconnect \(name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHoveringRow ? Color.surfaceContainer : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHoveringRow = $0 }
        .animation(.easeOut(duration: 0.15), value: isHoveringRow)
        .animation(.easeOut(duration: 0.15), value: isHoveringRemove)
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
