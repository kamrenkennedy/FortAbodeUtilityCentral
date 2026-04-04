import Foundation

// MARK: - GitHub Release Model

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: String?
    let htmlUrl: String?

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

// MARK: - GitHub Service

actor GitHubService {

    /// In-memory changelog cache (keyed by component ID)
    private var changelogCache: [String: [ChangelogEntry]] = [:]

    // MARK: - Version Checking

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

    // MARK: - Changelog Fetching

    func fetchChangelog(for source: UpdateSource, componentId: String, limit: Int = 5) async -> [ChangelogEntry] {
        // Check cache first
        if let cached = changelogCache[componentId] {
            return cached
        }

        let entries: [ChangelogEntry]

        switch source {
        case .githubRelease(let owner, let repo):
            entries = await fetchGitHubReleases(owner: owner, repo: repo, limit: limit)

        case .npmRegistry(let packageName):
            // Resolve GitHub repo from npm metadata, then fetch releases
            if let (owner, repo) = await resolveGitHubRepo(fromNpmPackage: packageName) {
                entries = await fetchGitHubReleases(owner: owner, repo: repo, limit: limit)
            } else {
                entries = []
            }

        case .none:
            entries = []
        }

        changelogCache[componentId] = entries
        return entries
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
            if httpResponse.statusCode == 404 { return nil }
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

    private func fetchGitHubReleases(owner: String, repo: String, limit: Int) async -> [ChangelogEntry] {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=\(limit)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            let releases = try decoder.decode([GitHubRelease].self, from: data)

            return releases.map { release in
                let date: Date?
                if let dateStr = release.publishedAt {
                    date = ISO8601DateFormatter().date(from: dateStr)
                } else {
                    date = nil
                }

                return ChangelogEntry(
                    version: release.version,
                    date: date,
                    body: release.body ?? "No release notes.",
                    htmlUrl: release.htmlUrl
                )
            }
        } catch {
            print("[GitHubService] Error fetching releases for \(owner)/\(repo): \(error)")
            return []
        }
    }

    // MARK: - npm Registry API

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

    /// Resolve GitHub owner/repo from npm registry metadata
    private func resolveGitHubRepo(fromNpmPackage packageName: String) async -> (String, String)? {
        let urlString = "https://registry.npmjs.org/\(packageName)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let repo = json?["repository"] as? [String: Any],
                  var repoUrl = repo["url"] as? String else { return nil }

            // Parse GitHub URL from various formats:
            // git+https://github.com/user/repo.git
            // https://github.com/user/repo
            // github:user/repo
            repoUrl = repoUrl
                .replacingOccurrences(of: "git+", with: "")
                .replacingOccurrences(of: "git://", with: "https://")
                .replacingOccurrences(of: ".git", with: "")

            if repoUrl.hasPrefix("github:") {
                let slug = String(repoUrl.dropFirst("github:".count))
                let parts = slug.split(separator: "/")
                if parts.count == 2 {
                    return (String(parts[0]), String(parts[1]))
                }
            }

            if let urlObj = URL(string: repoUrl),
               urlObj.host?.contains("github.com") == true {
                let pathParts = urlObj.pathComponents.filter { $0 != "/" }
                if pathParts.count >= 2 {
                    return (pathParts[0], pathParts[1])
                }
            }

            return nil
        } catch {
            return nil
        }
    }
}
