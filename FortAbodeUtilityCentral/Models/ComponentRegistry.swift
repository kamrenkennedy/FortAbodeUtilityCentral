import Foundation

// MARK: - Component Registry

/// Loads the component registry from the bundled JSON resource.
@Observable
final class ComponentRegistry {

    private(set) var components: [Component] = []

    init() {
        loadRegistry()
    }

    private func loadRegistry() {
        // Try flat bundle root first, then the "Resources" subfolder created by xcodegen's folder reference
        let url = Bundle.main.url(forResource: "component-registry", withExtension: "json")
                ?? Bundle.main.url(forResource: "component-registry", withExtension: "json", subdirectory: "Resources")
        guard let url else {
            print("[ComponentRegistry] component-registry.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            components = try decoder.decode([Component].self, from: data)
        } catch {
            print("[ComponentRegistry] Failed to decode component-registry.json: \(error)")
        }
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

    /// Components available in the marketplace (not installed and marketplace=true)
    func marketplaceComponents(statuses: [String: UpdateStatus]) -> [Component] {
        components.filter { component in
            guard component.showInMarketplace else { return false }
            guard let status = statuses[component.id] else { return true }
            if case .notInstalled = status { return true }
            return false
        }
    }
}
