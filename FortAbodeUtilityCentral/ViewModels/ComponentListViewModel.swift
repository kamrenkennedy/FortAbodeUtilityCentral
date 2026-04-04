import Foundation
import SwiftUI

// MARK: - Component List ViewModel

@MainActor
@Observable
final class ComponentListViewModel {

    // MARK: - State

    var statuses: [String: UpdateStatus] = [:]
    var isCheckingAll = false
    var lastChecked: Date?

    // MARK: - Dependencies

    let registry: ComponentRegistry
    let badgeTracker: BadgeTracker
    let gitHubService = GitHubService()
    private let versionDetectionService = VersionDetectionService()
    private let updateExecutionService = UpdateExecutionService()

    var components: [Component] {
        registry.components
    }

    /// Only components that are installed (for the main grid)
    var installedComponents: [Component] {
        registry.installedComponents(statuses: statuses)
    }

    /// Components available in the marketplace (not installed)
    var marketplaceItems: [Component] {
        registry.marketplaceComponents(statuses: statuses)
    }

    init(registry: ComponentRegistry, badgeTracker: BadgeTracker = BadgeTracker()) {
        self.registry = registry
        self.badgeTracker = badgeTracker
        for component in registry.components {
            statuses[component.id] = .unknown
        }
    }

    // MARK: - Computed

    var hasAvailableUpdates: Bool {
        statuses.values.contains { $0.isUpdateAvailable }
    }

    var availableUpdateCount: Int {
        statuses.values.filter { $0.isUpdateAvailable }.count
    }

    var lastCheckedText: String {
        guard let lastChecked else { return "Never checked" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: lastChecked, relativeTo: Date()))"
    }

    // MARK: - Actions

    /// Check all components for updates
    func checkAll() async {
        isCheckingAll = true

        for component in components {
            statuses[component.id] = .checking
        }

        await withTaskGroup(of: (String, UpdateStatus).self) { group in
            for component in components {
                group.addTask { [self] in
                    let status = await self.checkComponent(component)
                    return (component.id, status)
                }
            }

            for await (id, status) in group {
                statuses[id] = status
            }
        }

        lastChecked = Date()
        UserDefaults.standard.set(lastChecked, forKey: AppSettingsKey.lastCheckDate)
        isCheckingAll = false
    }

    /// Check a single component
    func checkSingleComponent(_ id: String) async {
        guard let component = registry.component(withId: id) else { return }
        statuses[id] = .checking
        statuses[id] = await checkComponent(component)
    }

    /// Update a component
    func updateComponent(_ id: String) async {
        guard let component = registry.component(withId: id) else { return }

        statuses[id] = .updating

        let result = await updateExecutionService.executeUpdate(for: component)

        if result.success {
            statuses[id] = .checking
            try? await Task.sleep(for: .seconds(1))

            let newStatus = await checkComponent(component)
            statuses[id] = newStatus

            // Mark as updated if version changed — triggers the badge
            if let version = newStatus.installedVersion {
                badgeTracker.markUpdated(componentId: id, version: version)
            }
        } else {
            let message = result.errorOutput.isEmpty ? "Update failed" : String(result.errorOutput.prefix(80))
            statuses[id] = .error(message: message)

            await ErrorLogger.shared.log(
                componentId: id,
                displayName: component.displayName,
                error: result.errorOutput,
                installedVersion: statuses[id]?.installedVersion
            )
        }
    }

    /// Install a component from the marketplace
    func installComponent(_ id: String) async {
        await updateComponent(id)
    }

    /// Update all components that have available updates
    func updateAll() async {
        let updatableIds = statuses
            .filter { $0.value.isUpdateAvailable }
            .map { $0.key }

        for id in updatableIds {
            await updateComponent(id)
        }
    }

    // MARK: - Private

    private func checkComponent(_ component: Component) async -> UpdateStatus {
        let installed = await versionDetectionService.detectInstalledVersion(for: component.versionSource)

        guard let installed else {
            return .notInstalled
        }

        // For components with no remote update source, just show installed status
        if case .none = component.updateSource {
            return .upToDate(version: installed)
        }

        let latest = await gitHubService.fetchLatestVersion(for: component.updateSource)

        guard let latest else {
            return .checkFailed(version: installed)
        }

        if SemverComparison.isNewer(latest, than: installed) {
            return .updateAvailable(installed: installed, latest: latest)
        } else {
            return .upToDate(version: installed)
        }
    }
}
