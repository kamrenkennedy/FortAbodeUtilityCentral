import XCTest
@testable import Fort_Abode_Utility_Central

final class GitHubServiceTests: XCTestCase {

    func testGitHubReleaseVersionParsing() {
        let release = GitHubRelease(
            tagName: "v1.3.0",
            name: "Version 1.3.0",
            body: "Release notes",
            publishedAt: "2026-04-01T00:00:00Z",
            htmlUrl: "https://github.com/test/test/releases/tag/v1.3.0"
        )

        XCTAssertEqual(release.version, "1.3.0")
    }

    func testGitHubReleaseVersionWithoutPrefix() {
        let release = GitHubRelease(
            tagName: "1.3.0",
            name: nil,
            body: nil,
            publishedAt: nil,
            htmlUrl: nil
        )

        XCTAssertEqual(release.version, "1.3.0")
    }

    func testGitHubReleaseJSONDecoding() throws {
        let json = """
        {
          "tag_name": "v2.0.0",
          "name": "Big Update",
          "body": "Lots of changes",
          "published_at": "2026-04-01T12:00:00Z",
          "html_url": "https://github.com/test/test/releases/tag/v2.0.0"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: json)

        XCTAssertEqual(release.version, "2.0.0")
        XCTAssertEqual(release.name, "Big Update")
        XCTAssertEqual(release.body, "Lots of changes")
    }
}
