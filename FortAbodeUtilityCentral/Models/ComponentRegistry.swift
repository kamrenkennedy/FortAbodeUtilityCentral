import Foundation

// MARK: - Component Registry

/// Loads the component registry from a remote GitHub source, with local cache and bundled fallback.
@MainActor
@Observable
final class ComponentRegistry {

    private(set) var components: [Component] = []

    /// Whether the most recent load came from the remote source
    private(set) var loadedFromRemote = false

    /// The remote URL for the registry (raw GitHub content)
    private static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/kamrenkennedy/FortAbodeUtilityCentral/main/FortAbodeUtilityCentral/Resources/component-registry.json"
    )!

    /// Local cache file in Application Support
    private static var cacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FortAbodeUtilityCentral", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("component-registry-cache.json")
    }

    init() {
        // Load synchronously from cache or bundle for instant UI
        loadFromCacheOrBundle()
    }

    // MARK: - Public

    /// Fetch the latest registry from GitHub. Merges with bundled, caches locally.
    /// Call this during checkAll() so the refresh button also updates the marketplace.
    func refresh() async {
        guard let remote = await fetchRemote() else { return }

        // Merge: remote wins for matching IDs, bundled fills any gaps
        let bundled = loadBundledComponents()
        let merged = mergeComponents(remote: remote, bundled: bundled)

        components = merged
        loadedFromRemote = true

        // Persist to cache
        saveToCache(remote)
    }

    /// Find a component by ID
    func component(withId id: String) -> Component? {
        components.first { $0.id == id }
    }

    /// Components that are installed (status is not .notInstalled or .unknown)
    func installedComponents(statuses: [String: UpdateStatus]) -> [Component] {
        components.filter { component in
            guard let status = statuses[component.id] else { return false }
            switch status {
            case .notInstalled, .unknown:
                return false
            default:
                return true
            }
        }
    }

    /// Components available in the marketplace (not installed, marketplace=true, compatible with this app version)
    func marketplaceComponents(statuses: [String: UpdateStatus]) -> [Component] {
        components.filter { component in
            guard component.showInMarketplace else { return false }
            guard component.isCompatibleWithCurrentApp else { return false }
            guard let status = statuses[component.id] else { return true }
            if case .notInstalled = status { return true }
            return false
        }
    }

    // MARK: - Private Loading

    /// Load from local cache if available, otherwise from bundled JSON.
    /// Used at init for instant startup — no network delay.
    private func loadFromCacheOrBundle() {
        // Try cache first
        if let cached = loadFromCache() {
            let bundled = loadBundledComponents()
            components = mergeComponents(remote: cached, bundled: bundled)
            return
        }

        // Fall back to bundled
        components = loadBundledComponents()
    }

    /// Decode components from the bundled JSON resource.
    private func loadBundledComponents() -> [Component] {
        let url = Bundle.main.url(forResource: "component-registry", withExtension: "json")
                ?? Bundle.main.url(forResource: "component-registry", withExtension: "json", subdirectory: "Resources")
        guard let url else {
            print("[ComponentRegistry] component-registry.json not found in bundle")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try decodeComponents(from: data)
        } catch {
            print("[ComponentRegistry] Failed to decode bundled registry: \(error)")
            return []
        }
    }

    /// Fetch registry from GitHub.
    private func fetchRemote() async -> [Component]? {
        var request = URLRequest(url: Self.remoteURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("[ComponentRegistry] Remote fetch returned non-200")
                return nil
            }
            return try decodeComponents(from: data)
        } catch {
            print("[ComponentRegistry] Remote fetch failed: \(error)")
            return nil
        }
    }

    /// Load components from the local cache file.
    private func loadFromCache() -> [Component]? {
        guard FileManager.default.fileExists(atPath: Self.cacheURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: Self.cacheURL)
            return try decodeComponents(from: data)
        } catch {
            print("[ComponentRegistry] Cache decode failed: \(error)")
            return nil
        }
    }

    /// Save remote components to the local cache file.
    private func saveToCache(_ components: [Component]) {
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(components)
            try data.write(to: Self.cacheURL, options: .atomic)
        } catch {
            print("[ComponentRegistry] Cache write failed: \(error)")
        }
    }

    /// Merge remote and bundled registries. Remote entries win for matching IDs.
    /// Bundled entries that don't exist in remote are preserved (safety net).
    private func mergeComponents(remote: [Component], bundled: [Component]) -> [Component] {
        var byId: [String: Component] = [:]

        // Start with bundled as base
        for component in bundled {
            byId[component.id] = component
        }

        // Remote overwrites matching IDs + adds new ones
        for component in remote {
            byId[component.id] = component
        }

        // Return in a stable order: remote order first, then any bundled-only entries
        var result: [Component] = []
        var seen: Set<String> = []

        for component in remote {
            result.append(byId[component.id]!)
            seen.insert(component.id)
        }

        for component in bundled where !seen.contains(component.id) {
            result.append(component)
        }

        return result
    }

    /// Shared decoder
    private func decodeComponents(from data: Data) throws -> [Component] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Component].self, from: data)
    }
}
