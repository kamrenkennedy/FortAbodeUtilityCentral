import Foundation

// MARK: - GitHub Release Model

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: String?
    let htmlUrl: String?

    /// Version string with `v` prefix stripped
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

// MARK: - GitHub Service

actor GitHubService {

    /// Fetch the latest version for a given update source
    func fetchLatestVersion(for source: UpdateSource) async -> String? {
        switch source {
        case .githubRelease(let owner, let repo):
            return await fetchGitHubRelease(owner: owner, repo: repo)
        case .npmRegistry(let packageName):
            return await fetchNpmVersion(packageName: packageName)
        case .none:
            return nil
        }
    }

    // MARK: - GitHub Releases API

    private func fetchGitHubRelease(owner: String, repo: String) async -> String? {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 404 {
                // No releases found — try npm fallback if this is also an npm package
                return nil
            }

            guard httpResponse.statusCode == 200 else { return nil }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = try decoder.decode(GitHubRelease.self, from: data)
            return release.version
        } catch {
            print("[GitHubService] Error fetching release for \(owner)/\(repo): \(error)")
            return nil
        }
    }

    // MARK: - npm Registry API (fallback)

    private func fetchNpmVersion(packageName: String) async -> String? {
        let urlString = "https://registry.npmjs.org/\(packageName)/latest"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["version"] as? String
        } catch {
            print("[GitHubService] Error fetching npm version for \(packageName): \(error)")
            return nil
        }
    }
}
