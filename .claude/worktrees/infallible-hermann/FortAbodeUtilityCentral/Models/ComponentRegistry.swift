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

    /// Components that can be independently updated (not children of a parent)
    var updatableComponents: [Component] {
        components.filter { $0.isIndependentlyUpdatable }
    }

    /// Child components of a given parent
    func children(of parentId: String) -> [Component] {
        components.filter { $0.parentId == parentId }
    }
}
