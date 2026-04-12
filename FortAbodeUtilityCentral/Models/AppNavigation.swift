import Foundation

// MARK: - App Navigation

enum AppDestination: Hashable {
    case componentDetail(componentId: String)
    case marketplace
    case feedback
}
