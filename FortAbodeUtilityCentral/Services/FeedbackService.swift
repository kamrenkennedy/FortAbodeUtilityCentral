import Foundation

// MARK: - Feedback Config (dormant since v3.7.5)

/// Unused as of v3.7.5 — feedback reports now write directly to an iCloud folder
/// (`Claude Memory/Fort Abode Logs/feedback/`) via `FeedbackService.saveFeedbackReport`.
/// This struct is kept so `SettingsView`'s feedback config UI compiles unchanged. It
/// can be deleted in v3.8.0 or revived if a future release adds an API destination as
/// an optional side channel (see the preflight skill — file-write is always the primary).
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

    /// As of v3.7.5, the feedback path no longer requires any configuration — reports
    /// save directly to the shared iCloud folder with no token, no database ID, no API.
    /// This method always returns `true` so the `FeedbackView.notConfiguredView` gate
    /// is unreachable. The method is kept (vs. deleted) so `SettingsView` keeps
    /// compiling without changes and the underlying `loadConfig` / `saveConfig` methods
    /// can be revived if a future release adds Notion back as an optional side channel.
    func isConfigured() -> Bool {
        true
    }

    /// Dormant since v3.7.5 — still used by `SettingsView` to display the (now unused)
    /// Notion token + database fields. Do not call from the feedback submission path.
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

    /// Dormant since v3.7.5 — see `loadConfig` note.
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

    // MARK: - Save Feedback Report (v3.7.5 — file-based, replaces Notion path)

    /// Save a feedback report as a markdown file in the shared `Fort Abode Logs/feedback/`
    /// folder (iCloud primary, local fallback). Returns the URL of the saved file so the
    /// UI can show the user exactly where it went.
    ///
    /// Why file-based: v3.7.4's Notion-based submission failed on Tiera's Mac with a
    /// `body.children[0].paragraph.rich_text[0].text.content.length should be ≤ 2000,
    /// instead was 6458` error — the expanded debug report exceeded Notion's per-block
    /// character limit and every submission silently bounced. Writing to a shared iCloud
    /// folder has none of those limits and puts the reports where Kam can read them
    /// directly (same pattern as the Weekly Flow engine files).
    ///
    /// Dual-write: tries iCloud first, falls back to `~/Library/Logs/FortAbodeUtilityCentral/feedback/`
    /// if iCloud is unavailable or the write fails. Throws `saveFailed` only when both
    /// paths fail — a single filesystem error never drops the report.
    func saveFeedbackReport(
        type: FeedbackType,
        component: String?,
        subject: String,
        description: String,
        debugReport: String?,
        submittedBy: String,
        appVersion: String,
        buildNumber: String
    ) async throws -> URL {
        let timestamp = Date()
        let filename = buildFilename(timestamp: timestamp, submitter: submittedBy, subject: subject)
        let markdown = renderMarkdown(
            timestamp: timestamp,
            type: type,
            component: component,
            subject: subject,
            description: description,
            debugReport: debugReport,
            submittedBy: submittedBy,
            appVersion: appVersion,
            buildNumber: buildNumber
        )

        // Attempt iCloud write first. The primary reason we're writing to iCloud is so
        // Kam can pick up reports from Tiera's Mac on his own Mac without any API.
        var icloudError: String?
        if let icloudDir = iCloudFeedbackDir() {
            do {
                try ensureDirectoryWithReadme(icloudDir)
                let url = icloudDir.appendingPathComponent(filename)
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                await ErrorLogger.shared.log(
                    area: "FeedbackService.saveFeedbackReport",
                    message: "Saved feedback report to iCloud",
                    context: ["path": url.path, "bytes": "\(markdown.utf8.count)"]
                )
                return url
            } catch {
                icloudError = error.localizedDescription
                await ErrorLogger.shared.log(
                    area: "FeedbackService.saveFeedbackReport",
                    message: "iCloud write failed, falling back to local",
                    context: ["error": error.localizedDescription, "path": icloudDir.path]
                )
            }
        } else {
            await ErrorLogger.shared.log(
                area: "FeedbackService.saveFeedbackReport",
                message: "iCloud path unavailable (Claude Memory folder missing), falling back to local"
            )
        }

        // Local fallback — always available, auto-created on first write
        let localDir = localFeedbackDir()
        do {
            try ensureDirectoryWithReadme(localDir)
            let url = localDir.appendingPathComponent(filename)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            await ErrorLogger.shared.log(
                area: "FeedbackService.saveFeedbackReport",
                message: "Saved feedback report to local fallback",
                context: ["path": url.path, "bytes": "\(markdown.utf8.count)"]
            )
            return url
        } catch {
            await ErrorLogger.shared.log(
                area: "FeedbackService.saveFeedbackReport",
                message: "Both iCloud and local writes FAILED",
                context: [
                    "icloudError": icloudError ?? "path-unavailable",
                    "localError": error.localizedDescription
                ]
            )
            throw FeedbackError.saveFailed(
                icloudError: icloudError,
                localError: error.localizedDescription
            )
        }
    }

    // MARK: - Private: Feedback Save Helpers

    /// Returns `Claude Memory/Fort Abode Logs/feedback/` as a URL, or nil if the Claude
    /// Memory folder doesn't exist on this machine — we never create Claude Memory from
    /// scratch just to drop feedback in it.
    private func iCloudFeedbackDir() -> URL? {
        let home = fm.homeDirectoryForCurrentUser
        let claudeMemory = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/Claude Memory"
        )
        guard fm.fileExists(atPath: claudeMemory.path) else {
            return nil
        }
        return claudeMemory
            .appendingPathComponent("Fort Abode Logs")
            .appendingPathComponent("feedback")
    }

    /// Local fallback path — always available, auto-created on first write.
    private func localFeedbackDir() -> URL {
        let home = fm.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Logs/FortAbodeUtilityCentral")
            .appendingPathComponent("feedback")
    }

    /// Create the directory if needed and drop a README.txt once so a human browsing
    /// the folder in Finder understands what it is.
    private func ensureDirectoryWithReadme(_ dir: URL) throws {
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let readme = dir.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            let contents = """
                This folder contains Fort Abode Utility Central feedback reports.

                Each .md file is one submission from the in-app "Send Feedback" screen,
                containing the user's description and (for bug reports) a full debug
                report from the machine that submitted it.

                Safe to delete individual files or the whole folder — Fort Abode will
                recreate it on the next submission.
                """
            try? contents.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    /// Build the filename: `{timestamp}-{submitter-slug}-{subject-slug}.md`.
    /// ISO 8601 local time with colons replaced by hyphens (filesystem-safe).
    private func buildFilename(timestamp: Date, submitter: String, subject: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone.current
        let ts = formatter.string(from: timestamp)

        let submitterSlug = slugify(submitter, maxLength: 30)
        let subjectSlug = slugify(subject, maxLength: 40)

        // Handle edge case where slugs are empty (e.g., CJK-only subjects)
        let submitterPart = submitterSlug.isEmpty ? "user" : submitterSlug
        let subjectPart = subjectSlug.isEmpty ? "feedback" : subjectSlug

        return "\(ts)-\(submitterPart)-\(subjectPart).md"
    }

    /// Lowercase, strip non-alphanumerics, collapse runs of hyphens, trim ends. Produces
    /// filesystem-safe slugs. Returns empty string if the input contains no valid chars.
    private func slugify(_ s: String, maxLength: Int) -> String {
        let lowered = s.lowercased()
        let mapped = lowered.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "-"
        }
        var result = String(mapped)
        // Collapse runs of hyphens
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        // Trim leading/trailing hyphens
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        // Truncate
        if result.count > maxLength {
            let end = result.index(result.startIndex, offsetBy: maxLength)
            result = String(result[result.startIndex..<end])
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return result
    }

    /// Build the full markdown document: YAML-ish frontmatter + heading + description
    /// + debug report fenced in a code block. No chunking — the file is a file.
    private func renderMarkdown(
        timestamp: Date,
        type: FeedbackType,
        component: String?,
        subject: String,
        description: String,
        debugReport: String?,
        submittedBy: String,
        appVersion: String,
        buildNumber: String
    ) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let stamp = iso.string(from: timestamp)

        var lines: [String] = []
        lines.append("---")
        lines.append("submitted: \(stamp)")
        lines.append("submitter: \(submittedBy)")
        lines.append("type: \(type.rawValue)")
        if let component, !component.isEmpty {
            lines.append("component: \(component)")
        }
        lines.append("subject: \(subject)")
        lines.append("appVersion: \(appVersion)")
        lines.append("build: \(buildNumber)")
        lines.append("---")
        lines.append("")
        lines.append("# \(subject)")
        lines.append("")
        lines.append(description.isEmpty ? "_(no description provided)_" : description)

        if let debugReport, !debugReport.isEmpty {
            lines.append("")
            lines.append("## Debug Report")
            lines.append("")
            lines.append("```")
            lines.append(debugReport)
            lines.append("```")
        }

        return lines.joined(separator: "\n") + "\n"
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
    /// v3.7.5: both iCloud primary AND local fallback writes failed. Surface both error
    /// messages to the user so they can tell at a glance whether it's an iCloud-only
    /// issue (rare) or a filesystem-wide problem (very rare).
    case saveFailed(icloudError: String?, localError: String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let icloudError, let localError):
            if let icloudError {
                return "Couldn't save feedback report. iCloud: \(icloudError). Local: \(localError)."
            }
            return "Couldn't save feedback report to local folder: \(localError)."
        }
    }
}
