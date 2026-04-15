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
    private let claudeConfigService = ClaudeDesktopConfigService()
    private let filePinningService = FilePinningService()
    private let weeklyRhythmService = WeeklyRhythmService()
    private let coworkSkillService = CoworkSkillService()

    /// Set after install/uninstall to prompt user to restart Claude
    var showRestartHint = false

    /// Set when a legacy Memory install is detected (hardcoded keys, no stored DISPLAY_NAME).
    /// The UI should present a name prompt and call `migrateMemoryKeys(displayName:)`.
    var memoryNeedsMigration = false

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

    /// Check all components for updates (also refreshes the marketplace from GitHub)
    func checkAll() async {
        isCheckingAll = true

        // Refresh registry from GitHub — picks up new marketplace items
        await registry.refresh()

        // Initialize statuses for any new components that appeared from the remote registry
        for component in components where statuses[component.id] == nil {
            statuses[component.id] = .unknown
        }

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

        // Check for legacy Memory installs that need migration
        await detectMemoryMigration()

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
            // Re-apply config entries (idempotent — ensures config stays in sync)
            if let configEntries = component.claudeConfig, !configEntries.isEmpty {
                let entriesToWrite: [ClaudeConfigEntry]
                if hasPlaceholderKeys(configEntries), let stored = persistedInputs(for: id) {
                    entriesToWrite = configEntries.map { entry in
                        ClaudeConfigEntry(
                            key: resolveUserInputPlaceholders(in: entry.key, inputs: stored),
                            command: entry.command,
                            args: entry.args.map { resolveUserInputPlaceholders(in: $0, inputs: stored) },
                            env: entry.env?.mapValues { resolveUserInputPlaceholders(in: $0, inputs: stored) }
                        )
                    }
                } else {
                    entriesToWrite = configEntries
                }
                let memoryPath = resolveMemoryPath()
                try? await claudeConfigService.addServerEntries(entriesToWrite, memoryPath: memoryPath)
            }

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

    /// Install a component from the marketplace — runs npm install + writes claude_desktop_config.json
    func installComponent(_ id: String) async {
        guard let component = registry.component(withId: id) else { return }

        statuses[id] = .updating

        // Step 1: Run npm install (cache the package)
        let result = await updateExecutionService.executeUpdate(for: component)

        guard result.success else {
            let message = result.errorOutput.isEmpty ? "Install failed" : String(result.errorOutput.prefix(80))
            statuses[id] = .error(message: message)
            await ErrorLogger.shared.log(
                componentId: id,
                displayName: component.displayName,
                error: result.errorOutput,
                installedVersion: nil
            )
            return
        }

        // Step 2: Write config entries to claude_desktop_config.json
        if let configEntries = component.claudeConfig, !configEntries.isEmpty {
            do {
                let memoryPath = resolveMemoryPath()
                try await claudeConfigService.addServerEntries(configEntries, memoryPath: memoryPath)
                showRestartHint = true
            } catch {
                statuses[id] = .error(message: "Installed but failed to configure Claude: \(error.localizedDescription)")
                await ErrorLogger.shared.log(
                    componentId: id,
                    displayName: component.displayName,
                    error: "Config write failed: \(error.localizedDescription)",
                    installedVersion: nil
                )
                return
            }
        }

        // Step 3: Verify — re-check the version
        try? await Task.sleep(for: .seconds(1))
        let newStatus = await checkComponent(component)
        statuses[id] = newStatus

        if let version = newStatus.installedVersion {
            badgeTracker.markUpdated(componentId: id, version: version)
        }
    }

    /// Install a component with user-provided inputs from the setup wizard.
    /// Resolves {{user_input:*}} placeholders in claude_config entries before writing.
    func installComponentWithInputs(_ id: String, inputs: [String: String]) async {
        guard let component = registry.component(withId: id) else { return }

        statuses[id] = .updating

        // Step 1: Run npm install (cache the package) — skip for components with no update command
        // (e.g., Google Workspace is installed globally during the wizard's run_command steps)
        if case .none = component.updateCommand {
            // No npm install needed — CLI was installed during wizard
        } else {
            let result = await updateExecutionService.executeUpdate(for: component)

            guard result.success else {
                let message = result.errorOutput.isEmpty ? "Install failed" : String(result.errorOutput.prefix(80))
                statuses[id] = .error(message: message)
                await ErrorLogger.shared.log(
                    componentId: id,
                    displayName: component.displayName,
                    error: result.errorOutput,
                    installedVersion: nil
                )
                return
            }
        }

        // Step 2: Resolve placeholders and write config entries
        if let configEntries = component.claudeConfig, !configEntries.isEmpty {
            do {
                let resolvedEntries = configEntries.map { entry in
                    ClaudeConfigEntry(
                        key: resolveUserInputPlaceholders(in: entry.key, inputs: inputs),
                        command: entry.command,
                        args: entry.args.map { resolveUserInputPlaceholders(in: $0, inputs: inputs) },
                        env: entry.env?.mapValues { resolveUserInputPlaceholders(in: $0, inputs: inputs) }
                    )
                }

                let memoryPath = resolveMemoryPath()
                try await claudeConfigService.addServerEntries(resolvedEntries, memoryPath: memoryPath)
                showRestartHint = true
            } catch {
                statuses[id] = .error(message: "Installed but failed to configure Claude: \(error.localizedDescription)")
                await ErrorLogger.shared.log(
                    componentId: id,
                    displayName: component.displayName,
                    error: "Config write failed: \(error.localizedDescription)",
                    installedVersion: nil
                )
                return
            }
        }

        // Step 2.5: Pin iCloud folders and set up CLAUDE.md if this is the memory component
        if component.id == "setup-claude-memory" {
            await performMemoryPostInstall(component: component, inputs: inputs)
        }

        // Step 2.6: Deploy Weekly Rhythm Engine files to iCloud
        if component.id == "weekly-rhythm" {
            await performWeeklyRhythmPostInstall(userName: inputs["DISPLAY_NAME"] ?? "")
        }

        // Step 3: Persist user inputs for future updates/self-heal
        storeInputs(inputs, for: id)

        // Step 3.5: Store secrets in Keychain
        for (key, value) in inputs {
            if key.contains("TOKEN") || key.contains("SECRET") || key.contains("KEY") {
                SecureInputStorage.save(componentId: id, fieldName: key, value: value)
            }
        }

        // Step 4: Verify — re-check the version
        try? await Task.sleep(for: .seconds(1))
        let newStatus = await checkComponent(component)
        statuses[id] = newStatus

        if let version = newStatus.installedVersion {
            badgeTracker.markUpdated(componentId: id, version: version)
        }
    }

    /// Uninstall a component — removes config entries from claude_desktop_config.json
    func uninstallComponent(_ id: String) async {
        guard let component = registry.component(withId: id) else { return }

        // Skills manage their own files instead of claude_desktop_config.json.
        // v3.7.6: the old `coworkSkillService.unregisterSkill` path wrote directly
        // to Cowork's manifest.json (which Cowork owns and rewrites), so we now
        // use the proper `claude plugin uninstall` CLI path instead.
        if component.id == "weekly-rhythm" {
            try? await weeklyRhythmService.uninstall()
            await coworkSkillService.uninstallWeeklyRhythmPlugin()
            // Clear the install flag so a future reinstall triggers the auto-install path
            UserDefaults.standard.removeObject(forKey: "weeklyRhythmPluginInstalled_v1")
            clearPersistedInputs(for: id)
            statuses[id] = .notInstalled
            return
        }

        // Keychain-only components: wipe stored secrets, no config to remove
        if case .keychainSecret = component.versionSource {
            SecureInputStorage.deleteAll(componentId: id)
            clearPersistedInputs(for: id)
            statuses[id] = .notInstalled
            return
        }

        guard let configEntries = component.claudeConfig, !configEntries.isEmpty else { return }

        let keys: [String]
        if hasPlaceholderKeys(configEntries), component.multiInstance != true {
            // Resolve actual keys by suffix matching (e.g. find "Tiera-Memory" from template "-Memory")
            keys = await resolveActualKeys(for: configEntries)
        } else {
            keys = configEntries.map(\.key)
        }

        guard !keys.isEmpty else {
            statuses[id] = .notInstalled
            return
        }

        do {
            try await claudeConfigService.removeServerEntries(keys: keys)
            clearPersistedInputs(for: id)
            statuses[id] = .notInstalled
            showRestartHint = true
        } catch {
            statuses[id] = .error(message: "Uninstall failed: \(error.localizedDescription)")
        }
    }

    /// List installed instances for a multi-instance component.
    /// For a component with config key "notion-{{user_input:WORKSPACE_NAME}}",
    /// finds all matching keys like "notion-Tiera", "notion-Work" and returns the display names.
    func installedInstances(for component: Component) async -> [String] {
        guard component.multiInstance == true,
              let configEntries = component.claudeConfig,
              let firstEntry = configEntries.first else { return [] }

        // Extract the prefix before the placeholder (e.g. "notion-")
        let key = firstEntry.key
        guard let range = key.range(of: "{{user_input:") else { return [] }
        let prefix = String(key[key.startIndex..<range.lowerBound])

        let matchingKeys = await claudeConfigService.entriesMatching(prefix: prefix)
        return matchingKeys.map { String($0.dropFirst(prefix.count)) }
    }

    /// Remove a single instance of a multi-instance component by workspace name.
    func removeInstance(componentId: String, instanceName: String) async {
        guard let component = registry.component(withId: componentId),
              let configEntries = component.claudeConfig,
              let firstEntry = configEntries.first else { return }

        let key = firstEntry.key
        guard let range = key.range(of: "{{user_input:") else { return }
        let prefix = String(key[key.startIndex..<range.lowerBound])
        let configKey = "\(prefix)\(instanceName)"

        do {
            try await claudeConfigService.removeServerEntries(keys: [configKey])
            SecureInputStorage.deleteAll(componentId: "\(componentId).\(instanceName)")
            showRestartHint = true

            // If no instances remain, mark as not installed
            let remaining = await claudeConfigService.entriesMatching(prefix: prefix)
            if remaining.isEmpty {
                statuses[componentId] = .notInstalled
            }
        } catch {
            statuses[componentId] = .error(message: "Failed to remove \(instanceName): \(error.localizedDescription)")
        }
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

        // Self-heal: if package is installed (npx cache hit) but config entries are missing, auto-add them
        // Skip for multi-instance components and components with placeholder keys — can't resolve without user input
        if installed != nil, component.multiInstance != true,
           let configEntries = component.claudeConfig, !configEntries.isEmpty {

            if hasPlaceholderKeys(configEntries) {
                // Placeholder keys: self-heal using stored inputs (if available)
                if let stored = persistedInputs(for: component.id) {
                    let resolvedEntries = configEntries.map { entry in
                        ClaudeConfigEntry(
                            key: resolveUserInputPlaceholders(in: entry.key, inputs: stored),
                            command: entry.command,
                            args: entry.args.map { resolveUserInputPlaceholders(in: $0, inputs: stored) },
                            env: entry.env?.mapValues { resolveUserInputPlaceholders(in: $0, inputs: stored) }
                        )
                    }
                    let allPresent = await claudeConfigService.hasEntries(keys: resolvedEntries.map(\.key))
                    if !allPresent {
                        let memoryPath = resolveMemoryPath()
                        try? await claudeConfigService.addServerEntries(resolvedEntries, memoryPath: memoryPath)
                        showRestartHint = true
                    }
                }
                // No stored inputs → can't self-heal config keys, but migration will handle it
            } else {
                // Static keys: self-heal as before
                let keys = configEntries.map(\.key)
                let allPresent = await claudeConfigService.hasEntries(keys: keys)
                if !allPresent {
                    let memoryPath = resolveMemoryPath()
                    try? await claudeConfigService.addServerEntries(configEntries, memoryPath: memoryPath)
                    showRestartHint = true
                }
            }

            // Memory-specific: pin iCloud folders + CLAUDE.md sync (not key-dependent).
            // Pass empty inputs so family setup does NOT re-run on every self-heal poll —
            // family memory is an install-time opt-in, not a maintenance task.
            if component.id == "setup-claude-memory" {
                await performMemoryPostInstall(component: component, inputs: [:])
            }
        }

        // Weekly Rhythm launch-time self-heal.
        // v3.7.6: rewritten around the proper Claude Code plugin system. Previous
        // versions wrote directly to `manifest.json` and `skills/<name>/SKILL.md`,
        // but Cowork owns those files authoritatively and periodically rewrites
        // them from its own internal state — our writes were noise. The correct
        // path is `claude plugin install weekly-rhythm-engine@fort-abode-marketplace`
        // via the Claude Code CLI, which installs a bundled plugin that ships
        // inside Fort Abode's app bundle. Cowork then registers the skill through
        // its own plugin-discovery mechanism.
        //
        // We guard on `installed != nil` (iCloud engine-spec.md detection) so
        // fresh installs aren't auto-enrolled, AND on a UserDefaults flag so the
        // CLI invocation only runs once per machine per install. Subsequent
        // launches skip unless the user manually triggers reinstall via the
        // "Install Plugin in Claude Code" button.
        if component.id == "weekly-rhythm" {
            await ErrorLogger.shared.log(
                area: "checkComponent.weeklyRhythmSelfHeal",
                message: "Reached weekly-rhythm block",
                context: ["installed": installed ?? "nil"]
            )
            if installed != nil {
                // Redeploy any managed files that might have been clobbered
                // between launches. This path still writes only to the iCloud
                // Weekly Flow folder (Fort Abode's own territory) — not to
                // Cowork-managed paths.
                do {
                    try await weeklyRhythmService.updateManagedFiles()
                } catch {
                    await ErrorLogger.shared.log(
                        area: "checkComponent.weeklyRhythmSelfHeal",
                        message: "updateManagedFiles FAILED: \(error.localizedDescription)",
                        context: ["error": String(describing: error)]
                    )
                }

                // Install the plugin exactly once per machine. The UserDefaults
                // flag tracks whether we've successfully run `claude plugin install`
                // on this machine. If the user manually reinstalls via the UI,
                // nothing clears this flag but `claude plugin install` is idempotent
                // anyway so re-running is harmless.
                let installedKey = "weeklyRhythmPluginInstalled_v1"
                if UserDefaults.standard.bool(forKey: installedKey) {
                    await ErrorLogger.shared.log(
                        area: "checkComponent.weeklyRhythmSelfHeal",
                        message: "Plugin already marked installed on this machine — skipping CLI install"
                    )
                } else {
                    await ErrorLogger.shared.log(
                        area: "checkComponent.weeklyRhythmSelfHeal",
                        message: "Plugin not yet installed on this machine — running claude plugin install"
                    )
                    let result = await coworkSkillService.installWeeklyRhythmPlugin()
                    if case .succeeded = result {
                        UserDefaults.standard.set(true, forKey: installedKey)
                        // Surface the success via the restart hint so the user
                        // knows to quit and relaunch Claude Code.
                        showRestartHint = true
                    }
                }
            } else {
                await ErrorLogger.shared.log(
                    area: "checkComponent.weeklyRhythmSelfHeal",
                    message: "installed == nil — skipping self-heal (component not installed on this machine)"
                )
            }
        }

        // Dual detection: also check if config entries exist (manual installs)
        // For multi-instance components, check if any instance exists (prefix match)
        // For placeholder-key components, check by suffix match
        let configPresent: Bool
        if let configEntries = component.claudeConfig, !configEntries.isEmpty,
           configEntries.first?.key.contains("{{user_input:") == true {
            if component.multiInstance == true,
               let firstEntry = configEntries.first,
               let range = firstEntry.key.range(of: "{{user_input:") {
                // Multi-instance: prefix match (e.g. Notion)
                let prefix = String(firstEntry.key[firstEntry.key.startIndex..<range.lowerBound])
                let matches = await claudeConfigService.entriesMatching(prefix: prefix)
                configPresent = !matches.isEmpty
            } else {
                // Single-instance with personalized keys (e.g. Memory): suffix match
                let suffixes = configKeySuffixes(from: configEntries)
                var allFound = true
                for suffix in suffixes {
                    let matches = await claudeConfigService.entriesMatching(suffix: suffix)
                    if matches.isEmpty { allFound = false; break }
                }
                configPresent = allFound
            }
        } else if let configEntries = component.claudeConfig, !configEntries.isEmpty {
            configPresent = await claudeConfigService.hasEntries(keys: configEntries.map(\.key))
        } else {
            configPresent = false
        }

        // If no npx cache version but config IS present, treat as "configured"
        guard let installed else {
            if configPresent {
                return .upToDate(version: "configured")
            }
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

    // MARK: - Helpers

    private func resolveMemoryPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Claude Memory"
    }

    private func resolveUserInputPlaceholders(in text: String, inputs: [String: String]) -> String {
        var resolved = text
        for (key, value) in inputs {
            resolved = resolved.replacingOccurrences(of: "{{user_input:\(key)}}", with: value)
        }
        // Resolve {{resolved:CONFIG_DIR}} for Google Workspace
        if let accountName = inputs["ACCOUNT_NAME"] {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let configDir = "\(home)/.config/gws-\(accountName)"
            resolved = resolved.replacingOccurrences(of: "{{resolved:CONFIG_DIR}}", with: configDir)
        }
        return resolved
    }

    // MARK: - Persisted Inputs (UserDefaults)

    private static let inputsKeyPrefix = "component.inputs."

    func storeInputs(_ inputs: [String: String], for componentId: String) {
        UserDefaults.standard.set(inputs, forKey: Self.inputsKeyPrefix + componentId)
    }

    func persistedInputs(for componentId: String) -> [String: String]? {
        UserDefaults.standard.dictionary(forKey: Self.inputsKeyPrefix + componentId) as? [String: String]
    }

    private func clearPersistedInputs(for componentId: String) {
        UserDefaults.standard.removeObject(forKey: Self.inputsKeyPrefix + componentId)
    }

    /// Check whether config entries contain unresolved `{{user_input:*}}` placeholders.
    private func hasPlaceholderKeys(_ entries: [ClaudeConfigEntry]) -> Bool {
        entries.contains { $0.key.contains("{{user_input:") }
    }

    /// Extract the suffix after the `}}` placeholder closing for each config entry key.
    /// e.g. `"{{user_input:DISPLAY_NAME}}-Memory"` → `"-Memory"`
    private func configKeySuffixes(from entries: [ClaudeConfigEntry]) -> [String] {
        entries.compactMap { entry in
            guard let range = entry.key.range(of: "}}") else { return nil }
            return String(entry.key[range.upperBound...])
        }
    }

    /// Resolve actual config keys by finding entries that match the expected suffixes.
    private func resolveActualKeys(for entries: [ClaudeConfigEntry]) async -> [String] {
        let suffixes = configKeySuffixes(from: entries)
        var keys: [String] = []
        for suffix in suffixes {
            let matches = await claudeConfigService.entriesMatching(suffix: suffix)
            keys.append(contentsOf: matches)
        }
        return keys
    }

    // MARK: - Legacy Migration

    /// Detect if a legacy Memory install exists (hardcoded keys, no stored DISPLAY_NAME).
    /// Called during checkAll() to trigger the migration prompt.
    func detectMemoryMigration() async {
        guard persistedInputs(for: "setup-claude-memory") == nil else { return }

        // Check if any *-Memory or *-Deep-Context keys exist in the config
        let memoryKeys = await claudeConfigService.entriesMatching(suffix: "-Memory")
        let deepContextKeys = await claudeConfigService.entriesMatching(suffix: "-Deep-Context")

        if !memoryKeys.isEmpty || !deepContextKeys.isEmpty {
            memoryNeedsMigration = true
        }
    }

    /// Rename legacy Memory config keys to use the provided display name.
    /// Called from the migration UI after the user enters their name.
    func migrateMemoryKeys(displayName: String) async {
        let memoryKeys = await claudeConfigService.entriesMatching(suffix: "-Memory")
        let deepContextKeys = await claudeConfigService.entriesMatching(suffix: "-Deep-Context")

        var mapping: [String: String] = [:]
        for key in memoryKeys {
            mapping[key] = "\(displayName)-Memory"
        }
        for key in deepContextKeys {
            mapping[key] = "\(displayName)-Deep-Context"
        }

        do {
            try await claudeConfigService.renameServerEntries(mapping: mapping)
            storeInputs(["DISPLAY_NAME": displayName], for: "setup-claude-memory")
            memoryNeedsMigration = false
            showRestartHint = true
        } catch {
            await ErrorLogger.shared.log(
                componentId: "setup-claude-memory",
                displayName: "Memory",
                error: "Migration failed: \(error.localizedDescription)",
                installedVersion: nil
            )
        }
    }

    /// Pin the iCloud Claude folders so they stay downloaded locally.
    /// Safe to call from app launch — runs in background, silent on success.
    func pinICloudFolders() async {
        await filePinningService.pinAll()
    }

    // MARK: - Manual Install (user-triggered plugin install)

    /// Manually trigger the Weekly Rhythm plugin install. Used by the
    /// "Install Plugin in Claude Code" button in ComponentDetailView. Forces
    /// a redeploy of the managed iCloud files (engine-spec.md, dashboard-template.html)
    /// and then shells out to `claude plugin install weekly-rhythm-engine@fort-abode-marketplace`
    /// via the Claude Code CLI — the same path as the launch-time self-heal, but
    /// the result is returned so the UI can show success / failure inline.
    ///
    /// Idempotent — safe to re-run. `claude plugin install` treats an already-
    /// installed plugin as a successful no-op.
    func installWeeklyRhythmPluginManually() async -> PluginInstallResult {
        await ErrorLogger.shared.log(
            area: "installWeeklyRhythmPluginManually",
            message: "User tapped the manual 'Install Plugin in Claude Code' button"
        )
        do {
            try await weeklyRhythmService.updateManagedFiles()
            await ErrorLogger.shared.log(
                area: "installWeeklyRhythmPluginManually",
                message: "updateManagedFiles succeeded — proceeding to plugin install"
            )
        } catch {
            await ErrorLogger.shared.log(
                area: "installWeeklyRhythmPluginManually",
                message: "updateManagedFiles FAILED: \(error.localizedDescription)",
                context: ["error": String(describing: error)]
            )
            // Continue anyway — installWeeklyRhythmPlugin will report a specific
            // error if anything else is missing, and that's useful diagnostic
            // info for the debug report.
        }
        let result = await coworkSkillService.installWeeklyRhythmPlugin()
        // Update the install flag so the self-heal doesn't re-run on next launch
        if case .succeeded = result {
            UserDefaults.standard.set(true, forKey: "weeklyRhythmPluginInstalled_v1")
            showRestartHint = true
        }
        return result
    }

    /// Post-install tasks specific to the Memory component:
    /// 1. Pin iCloud folders
    /// 2. Sync CLAUDE.md
    /// 3. If user opted in, run `npx setup-claude-memory --family` to deploy family memory
    private func performMemoryPostInstall(component: Component, inputs: [String: String]) async {
        await filePinningService.pinAll()

        let claudeCodeService = ClaudeCodeConfigService()
        do {
            try await claudeCodeService.setupClaudeMD()
        } catch {
            await ErrorLogger.shared.log(
                componentId: component.id,
                displayName: component.displayName,
                error: "CLAUDE.md sync failed: \(error.localizedDescription)",
                installedVersion: nil
            )
        }

        // Family memory is opt-in during the setup wizard. When the user picks "yes",
        // we run `npx setup-claude-memory --family` which deploys the Kennedy Family Docs/
        // Claude/Family Memory/ structure and appends a routing block to ~/.claude/CLAUDE.md.
        if inputs["ENABLE_FAMILY_MEMORY"] == "yes" {
            await runFamilyMemorySetup(component: component)
        }
    }

    /// Best-effort family memory setup via `npx -y setup-claude-memory --family`.
    /// Non-fatal: if it fails, the main Memory install already succeeded.
    private func runFamilyMemorySetup(component: Component) async {
        let result = await updateExecutionService.executeFamilyMemorySetup()
        if !result.success {
            await ErrorLogger.shared.log(
                componentId: component.id,
                displayName: component.displayName,
                error: "Family memory setup failed: \(result.errorOutput.isEmpty ? "unknown error" : result.errorOutput)",
                installedVersion: nil
            )
        }
    }

    /// Post-install tasks for the Weekly Rhythm Engine (deploy files to iCloud + install plugin via CLI).
    /// v3.7.6: the old `coworkSkillService.registerWeeklyRhythmSkill` call wrote directly
    /// to Cowork's manifest.json which got clobbered. The new path shells out to
    /// `claude plugin install weekly-rhythm-engine@fort-abode-marketplace` via the
    /// Claude Code CLI, which installs a proper plugin Cowork picks up natively.
    private func performWeeklyRhythmPostInstall(userName: String) async {
        do {
            try await weeklyRhythmService.setupWeeklyFlow(userName: userName)
            await filePinningService.pinAll()
        } catch {
            await ErrorLogger.shared.log(
                componentId: "weekly-rhythm",
                displayName: "Weekly Rhythm Engine",
                error: "Setup failed: \(error.localizedDescription)",
                installedVersion: nil
            )
        }

        // Install the plugin via Claude Code CLI (best-effort — non-fatal if CLI not found).
        // On success, mark the install flag so the launch self-heal doesn't re-run it.
        let result = await coworkSkillService.installWeeklyRhythmPlugin()
        if case .succeeded = result {
            UserDefaults.standard.set(true, forKey: "weeklyRhythmPluginInstalled_v1")
            showRestartHint = true
        }
    }
}
