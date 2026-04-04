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

    private let registry: ComponentRegistry
    private let gitHubService = GitHubService()
    private let versionDetectionService = VersionDetectionService()
    private let updateExecutionService = UpdateExecutionService()

    var components: [Component] {
        registry.components
    }

    init(registry: ComponentRegistry) {
        self.registry = registry
        // Initialize all statuses to unknown
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

        // Set all to checking
        for component in components {
            statuses[component.id] = .checking
        }

        // Check each component concurrently
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

    /// Update a component (routes to parent if needed)
    func updateComponent(_ id: String) async {
        guard let component = registry.component(withId: id) else { return }

        // If this is a child component, update the parent instead
        let targetComponent: Component
        if let parentId = component.parentId,
           let parent = registry.component(withId: parentId) {
            targetComponent = parent
        } else {
            targetComponent = component
        }

        statuses[targetComponent.id] = .updating

        // Also mark children as updating
        for child in registry.children(of: targetComponent.id) {
            statuses[child.id] = .updating
        }

        let result = await updateExecutionService.executeUpdate(for: targetComponent)

        if result.success {
            // Re-check versions after successful update
            statuses[targetComponent.id] = .checking
            for child in registry.children(of: targetComponent.id) {
                statuses[child.id] = .checking
            }

            // Brief pause to let filesystem settle
            try? await Task.sleep(for: .seconds(1))

            // Re-check the target and its children
            statuses[targetComponent.id] = await checkComponent(targetComponent)
            for child in registry.children(of: targetComponent.id) {
                statuses[child.id] = await checkComponent(child)
            }
        } else {
            let message = result.errorOutput.isEmpty ? "Update failed" : result.errorOutput.prefix(80).description
            statuses[targetComponent.id] = .error(message: message)
        }
    }

    /// Update all components that have available updates
    func updateAll() async {
        let updatableIds = statuses
            .filter { $0.value.isUpdateAvailable }
            .map { $0.key }

        var rootIdsToUpdate = Set<String>()
        for id in updatableIds {
            if let component = registry.component(withId: id) {
                rootIdsToUpdate.insert(component.parentId ?? component.id)
            }
        }

        for id in rootIdsToUpdate {
            await updateComponent(id)
        }
    }

    // MARK: - Private

    private func checkComponent(_ component: Component) async -> UpdateStatus {
        let installed = await versionDetectionService.detectInstalledVersion(for: component.versionSource)

        guard let installed else {
            return .notInstalled
        }

        // Local-only components (Reminders, iMessage) — no remote to check
        if installed == "installed" || installed == "configured" {
            // If there's no update source, it's a local-only component
            if case .none = component.updateSource {
                return .upToDate(version: installed)
            }
        }

        // For components with a remote update source, fetch the latest version
        if case .none = component.updateSource {
            return .upToDate(version: installed)
        }

        let latest = await gitHubService.fetchLatestVersion(for: component.updateSource)

        guard let latest else {
            // Couldn't reach remote — show that we couldn't check, not "up to date"
            return .checkFailed(version: installed)
        }

        if SemverComparison.isNewer(latest, than: installed) {
            return .updateAvailable(installed: installed, latest: latest)
        } else {
            return .upToDate(version: installed)
        }
    }
}
