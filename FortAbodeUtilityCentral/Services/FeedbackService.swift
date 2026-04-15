import Foundation

// MARK: - Feedback Config (iCloud shared)

struct FeedbackConfig: Codable {
    let notionToken: String
    let databaseId: String

    private enum CodingKeys: String, CodingKey {
        case notionToken = "notion_token"
        case databaseId = "database_id"
    }
}

// MARK: - Feedback Type

enum FeedbackType: String, CaseIterable, Identifiable {
    case bug = "Bug"
    case featureRequest = "Feature Request"
    case general = "General"

    var id: String { rawValue }
}

// MARK: - Feedback Service

actor FeedbackService {

    static let shared = FeedbackService()

    private let fm = FileManager.default

    private var configPath: String {
        let home = fm.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Claude/feedback-config.json"
    }

    // MARK: - Configuration

    func isConfigured() -> Bool {
        loadConfig() != nil
    }

    func loadConfig() -> FeedbackConfig? {
        guard fm.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(FeedbackConfig.self, from: data),
              !config.notionToken.isEmpty,
              !config.databaseId.isEmpty else {
            return nil
        }
        return config
    }

    func saveConfig(token: String, databaseId: String) throws {
        let config = FeedbackConfig(notionToken: token, databaseId: databaseId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        let dir = (configPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try data.write(to: URL(fileURLWithPath: configPath))
    }

    // MARK: - Submit Feedback

    func submitFeedback(
        type: FeedbackType,
        component: String?,
        subject: String,
        description: String,
        debugReport: String?,
        submittedBy: String,
        appVersion: String
    ) async throws {
        guard let config = loadConfig() else {
            throw FeedbackError.notConfigured
        }

        let url = URL(string: "https://api.notion.com/v1/pages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")

        var properties: [String: Any] = [
            "Title": [
                "title": [["text": ["content": subject]]]
            ],
            "Type": [
                "select": ["name": type.rawValue]
            ],
            "Submitted By": [
                "rich_text": [["text": ["content": submittedBy]]]
            ],
            "App Version": [
                "rich_text": [["text": ["content": appVersion]]]
            ]
        ]

        if let component, !component.isEmpty {
            properties["Component"] = [
                "select": ["name": component]
            ]
        }

        var bodyText = description
        if let debugReport, !debugReport.isEmpty {
            bodyText += "\n\n--- Debug Report ---\n" + debugReport
        }

        let body: [String: Any] = [
            "parent": ["database_id": config.databaseId],
            "properties": properties,
            "children": [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [["type": "text", "text": ["content": bodyText]]]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FeedbackError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }
    }

    // MARK: - Debug Report

    func generateDebugReport(
        statuses: [String: UpdateStatus],
        components: [Component]
    ) async -> String {
        var lines: [String] = []

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString

        lines.append("App: Fort Abode Utility Central v\(appVersion) (build \(buildNumber))")
        lines.append("macOS: \(macOS)")
        lines.append("")
        lines.append("Components:")

        for component in components {
            let status = statuses[component.id] ?? .unknown
            lines.append("  \(component.displayName): \(status.debugLabel)")
        }

        // v3.7.4: Weekly Rhythm state snapshot — filesystem + Cowork manifest + bundle checks.
        // Added because v3.7.1-3 debug reports had no way to tell whether:
        //   (a) the iCloud files actually existed on the user's machine
        //   (b) Fort Abode had ever successfully written to the Cowork manifest
        //   (c) the bundled SKILL.md wrapper was present in the installed app
        // Without these, we shipped 3 "fixes" based on theories. v3.7.4 makes the actual
        // state visible in every bug report.
        lines.append("")
        lines.append("Weekly Rhythm State Snapshot:")
        appendWeeklyRhythmSnapshot(to: &lines)

        // Logger self-check — if this says bothFailed, nothing else in the report can
        // be trusted. If it says icloudOk, every breadcrumb in the log is reliable.
        let writeStatus = await ErrorLogger.shared.lastWriteStatus
        lines.append("")
        lines.append("Logger:")
        lines.append("  lastWriteStatus: \(writeStatus.description)")

        let recentErrors = await ErrorLogger.shared.recentErrors(limit: 50)
        if !recentErrors.isEmpty {
            lines.append("")
            lines.append("Recent Log Entries (last \(recentErrors.count)):")
            let formatter = ISO8601DateFormatter()
            for error in recentErrors {
                let stamp = formatter.string(from: error.timestamp)
                let label = error.componentDisplayName.map { "\($0) (\(error.area))" } ?? error.area
                var line = "  [\(stamp)] \(label): \(error.message)"
                if let context = error.context, !context.isEmpty {
                    let contextStr = context.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                    line += " {\(contextStr)}"
                }
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Weekly Rhythm State Snapshot

    /// Inspect every filesystem location that Weekly Rhythm depends on and append a
    /// readable summary to the debug report. Every check is local + fast — nothing
    /// network, nothing that can hang the UI.
    private func appendWeeklyRhythmSnapshot(to lines: inout [String]) {
        let home = fm.homeDirectoryForCurrentUser.path

        // iCloud managed files
        let weeklyFlowDir = "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Claude/Weekly Flow"
        lines.append("  iCloud Weekly Flow dir: \(fm.fileExists(atPath: weeklyFlowDir) ? "EXISTS" : "MISSING") (\(weeklyFlowDir))")
        if fm.fileExists(atPath: weeklyFlowDir) {
            let dashboard = "\(weeklyFlowDir)/dashboard-template.html"
            let spec = "\(weeklyFlowDir)/engine-spec.md"
            lines.append("    dashboard-template.html: \(sizeDescription(for: dashboard))")
            lines.append("    engine-spec.md: \(sizeDescription(for: spec))")

            if let contents = try? fm.contentsOfDirectory(atPath: weeklyFlowDir) {
                let filtered = contents.filter { !$0.hasPrefix(".") }.sorted()
                lines.append("    contents: \(filtered.joined(separator: ", "))")
            }
        }

        // Bundled resources (proof the app shipped what it needs)
        let bundledWrapper = Bundle.main.url(forResource: "weekly-rhythm-skill-wrapper", withExtension: "md") != nil
        let bundledDashboard = Bundle.main.url(forResource: "dashboard-template", withExtension: "html") != nil
        let bundledSpec = Bundle.main.url(forResource: "engine-spec", withExtension: "md") != nil
        lines.append("  Bundled resources:")
        lines.append("    weekly-rhythm-skill-wrapper.md: \(bundledWrapper ? "present" : "MISSING")")
        lines.append("    dashboard-template.html: \(bundledDashboard ? "present" : "MISSING")")
        lines.append("    engine-spec.md: \(bundledSpec ? "present" : "MISSING")")

        // Claude skills-plugin manifest discovery (shared by Cowork + Claude Code)
        let skillsPluginBase = "\(home)/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin"
        lines.append("  Claude skills-plugin base: \(fm.fileExists(atPath: skillsPluginBase) ? "EXISTS" : "MISSING")")
        if fm.fileExists(atPath: skillsPluginBase) {
            appendSkillsPluginInventory(at: skillsPluginBase, to: &lines)
        }
    }

    /// Walk every `session/<user>/manifest.json` under the skills-plugin base and report
    /// whether weekly-rhythm-engine is registered there, plus the `fortAbodeLastWrite`
    /// marker so we can prove (or disprove) whether Fort Abode ever touched that manifest.
    private func appendSkillsPluginInventory(at base: String, to lines: inout [String]) {
        guard let sessions = try? fm.contentsOfDirectory(atPath: base).filter({ !$0.hasPrefix(".") }).sorted(),
              !sessions.isEmpty else {
            lines.append("    (no session directories found)")
            return
        }

        for session in sessions {
            let sessionPath = "\(base)/\(session)"
            guard let users = try? fm.contentsOfDirectory(atPath: sessionPath).filter({ !$0.hasPrefix(".") }).sorted() else {
                continue
            }
            for user in users {
                let manifestPath = "\(sessionPath)/\(user)/manifest.json"
                guard fm.fileExists(atPath: manifestPath) else { continue }
                lines.append("    manifest: \(session.prefix(8))/\(user.prefix(8))/manifest.json")

                guard let data = fm.contents(atPath: manifestPath),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    lines.append("      (unreadable)")
                    continue
                }

                let skills = json["skills"] as? [[String: Any]] ?? []
                let skillNames = skills.compactMap { $0["name"] as? String }.sorted()
                lines.append("      skills (\(skillNames.count)): \(skillNames.joined(separator: ", "))")

                let hasWeeklyRhythm = skillNames.contains("weekly-rhythm-engine")
                lines.append("      weekly-rhythm-engine registered: \(hasWeeklyRhythm ? "YES" : "NO")")

                if let marker = json["fortAbodeLastWrite"] as? [String: Any] {
                    let ts = marker["timestamp"] as? String ?? "?"
                    let ver = marker["appVersion"] as? String ?? "?"
                    let build = marker["build"] as? String ?? "?"
                    lines.append("      fortAbodeLastWrite: \(ts) (v\(ver) build \(build))")
                } else {
                    lines.append("      fortAbodeLastWrite: (never — Fort Abode has not successfully written to this manifest)")
                }

                // Check for the deployed SKILL.md wrapper
                let skillFile = "\(sessionPath)/\(user)/skills/weekly-rhythm-engine/SKILL.md"
                if fm.fileExists(atPath: skillFile) {
                    if let attrs = try? fm.attributesOfItem(atPath: skillFile),
                       let size = attrs[.size] as? Int {
                        lines.append("      skills/weekly-rhythm-engine/SKILL.md: \(size) bytes")
                    }
                } else {
                    lines.append("      skills/weekly-rhythm-engine/SKILL.md: MISSING")
                }
            }
        }
    }

    private func sizeDescription(for path: String) -> String {
        guard fm.fileExists(atPath: path) else { return "MISSING" }
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int {
            return "\(size) bytes"
        }
        return "present"
    }
}

// MARK: - Errors

enum FeedbackError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Feedback isn't set up yet — ask Kam to configure it on his machine."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "Notion API error (\(code)): \(msg)"
        }
    }
}
