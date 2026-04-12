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

        let recentErrors = await ErrorLogger.shared.recentErrors(limit: 10)
        if !recentErrors.isEmpty {
            lines.append("")
            lines.append("Recent Errors:")
            let formatter = ISO8601DateFormatter()
            for error in recentErrors {
                lines.append("  [\(formatter.string(from: error.timestamp))] \(error.componentDisplayName): \(error.errorMessage)")
            }
        }

        return lines.joined(separator: "\n")
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
