import XCTest
@testable import Fort_Abode_Utility_Central

final class ComponentRegistryTests: XCTestCase {

    func testRegistryLoadsFromJSON() {
        let json = """
        [
          {
            "id": "test-component",
            "display_name": "Test Component",
            "description": "A test component",
            "type": "npmPackage",
            "icon": "brain",
            "version_source": { "npx_cache": { "package_name": "test-pkg" } },
            "update_source": { "github_release": { "owner": "test", "repo": "test" } },
            "update_command": { "npx_install": { "package_name": "test-pkg" } }
          }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let components = try? decoder.decode([Component].self, from: json)
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.count, 1)
        XCTAssertEqual(components?.first?.id, "test-component")
        XCTAssertEqual(components?.first?.displayName, "Test Component")
        XCTAssertEqual(components?.first?.icon, "brain")
    }

    func testComponentIdsAreUnique() {
        let json = """
        [
          {
            "id": "comp-a",
            "display_name": "A",
            "description": "A",
            "type": "npmPackage",
            "version_source": { "npx_cache": { "package_name": "a" } },
            "update_source": "none",
            "update_command": "none"
          },
          {
            "id": "comp-b",
            "display_name": "B",
            "description": "B",
            "type": "localMCPServer",
            "version_source": { "local_directory": { "name": "b" } },
            "update_source": "none",
            "update_command": "none"
          }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let components = try! decoder.decode([Component].self, from: json)

        let ids = components.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Component IDs should be unique")
    }

    func testParentChildRelationship() {
        let parent = Component(
            id: "parent",
            displayName: "Parent",
            description: "Parent component",
            type: .npmPackage,
            icon: nil,
            versionSource: .npxCache(packageName: "parent"),
            updateSource: .githubRelease(owner: "test", repo: "test"),
            updateCommand: .npxInstall(packageName: "parent")
        )

        let child = Component(
            id: "child",
            displayName: "Child",
            description: "Child component",
            type: .mcpServer,
            icon: nil,
            versionSource: .npxCache(packageName: "parent"),
            updateSource: .githubRelease(owner: "test", repo: "test"),
            updateCommand: .parentPackage(parentId: "parent")
        )

        XCTAssertTrue(parent.isIndependentlyUpdatable)
        XCTAssertFalse(child.isIndependentlyUpdatable)
        XCTAssertNil(parent.parentId)
        XCTAssertEqual(child.parentId, "parent")
    }
}
