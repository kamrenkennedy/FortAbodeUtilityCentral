import Foundation

/// Manages the Weekly Rhythm Engine files in iCloud.
/// Deploys and updates engine-spec.md and dashboard-template.html (app-managed).
/// Never touches user-owned config.md files.
actor WeeklyRhythmService {

    private let fm = FileManager.default

    private var homePath: String {
        fm.homeDirectoryForCurrentUser.path
    }

    /// iCloud path where Weekly Flow lives
    private var weeklyFlowPath: String {
        "\(homePath)/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Claude/Weekly Flow"
    }

    private var deployedEnginSpec: String { "\(weeklyFlowPath)/engine-spec.md" }
    private var deployedTemplate: String { "\(weeklyFlowPath)/dashboard-template.html" }

    // MARK: - Setup

    /// Deploy the Weekly Rhythm Engine files to iCloud and create the user's config folder.
    func setupWeeklyFlow(userName: String) async throws {
        // Create the Weekly Flow directory
        if !fm.fileExists(atPath: weeklyFlowPath) {
            try fm.createDirectory(atPath: weeklyFlowPath, withIntermediateDirectories: true)
        }

        // Deploy managed files from bundle
        try deployBundledFile(resource: "engine-spec", ext: "md", destination: deployedEnginSpec)
        try deployBundledFile(resource: "dashboard-template", ext: "html", destination: deployedTemplate)

        // Create user's config folder (empty — config.md created by skill on first run)
        let userFolder = "\(weeklyFlowPath)/\(userName)"
        if !fm.fileExists(atPath: userFolder) {
            try fm.createDirectory(atPath: userFolder, withIntermediateDirectories: true)
        }

        // Create dashboards subdirectory for generated dashboard HTML files
        let dashboardsDir = "\(userFolder)/dashboards"
        if !fm.fileExists(atPath: dashboardsDir) {
            try fm.createDirectory(atPath: dashboardsDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Update

    /// Compare bundled vs deployed template version and overwrite managed files if bundled is newer.
    func updateManagedFiles() async throws {
        guard let deployed = deployedTemplateVersion(),
              let bundled = bundledTemplateVersion() else {
            // If either is missing, deploy from bundle
            if fm.fileExists(atPath: weeklyFlowPath) {
                try? deployBundledFile(resource: "engine-spec", ext: "md", destination: deployedEnginSpec)
                try? deployBundledFile(resource: "dashboard-template", ext: "html", destination: deployedTemplate)
            }
            return
        }

        if SemverComparison.isNewer(bundled, than: deployed) {
            try deployBundledFile(resource: "engine-spec", ext: "md", destination: deployedEnginSpec)
            try deployBundledFile(resource: "dashboard-template", ext: "html", destination: deployedTemplate)
        }
    }

    // MARK: - Version Detection

    /// Parse the version from the deployed dashboard-template.html in iCloud.
    func deployedTemplateVersion() -> String? {
        guard let content = try? String(contentsOfFile: deployedTemplate, encoding: .utf8) else {
            return nil
        }
        return parseVersion(from: content)
    }

    /// Parse the version from the bundled dashboard-template.html in the app bundle.
    func bundledTemplateVersion() -> String? {
        guard let url = Bundle.main.url(forResource: "dashboard-template", withExtension: "html"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parseVersion(from: content)
    }

    // MARK: - Status

    /// Whether the Weekly Flow folder and managed files exist in iCloud.
    func isConfigured() -> Bool {
        fm.fileExists(atPath: deployedEnginSpec) && fm.fileExists(atPath: deployedTemplate)
    }

    /// Whether a user's config.md exists (indicates the skill has been run at least once).
    func configExists(for userName: String) -> Bool {
        fm.fileExists(atPath: "\(weeklyFlowPath)/\(userName)/config.md")
    }

    // MARK: - Uninstall

    /// Remove managed files only. Preserves user config folders.
    func uninstall() async throws {
        if fm.fileExists(atPath: deployedEnginSpec) {
            try fm.removeItem(atPath: deployedEnginSpec)
        }
        if fm.fileExists(atPath: deployedTemplate) {
            try fm.removeItem(atPath: deployedTemplate)
        }
    }

    // MARK: - Private

    private func deployBundledFile(resource: String, ext: String, destination: String) throws {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            throw WeeklyRhythmError.resourceNotFound(resource: "\(resource).\(ext)")
        }
        let content = try String(contentsOf: url, encoding: .utf8)

        // Overwrite if exists
        if fm.fileExists(atPath: destination) {
            try fm.removeItem(atPath: destination)
        }
        try content.write(toFile: destination, atomically: true, encoding: .utf8)
    }

    /// Parse version from HTML comment: <!-- Weekly Rhythm Dashboard v1.6.0 — Managed by Fort Abode — DO NOT EDIT -->
    /// Checks the first 5 lines (version comment may follow <!DOCTYPE html>).
    private func parseVersion(from content: String) -> String? {
        let lines = content.components(separatedBy: "\n").prefix(5)
        let pattern = "Weekly Rhythm Dashboard v([0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in lines {
            if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return nil
    }
}

enum WeeklyRhythmError: LocalizedError {
    case resourceNotFound(resource: String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let resource):
            return "Weekly Rhythm resource '\(resource)' not found in app bundle"
        }
    }
}
