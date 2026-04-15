import Foundation

// MARK: - Registration Status

/// Outcome of the most recent call to `registerWeeklyRhythmSkill()`. Exposed so the
/// manual "Register in Claude Code" button in ComponentDetailView can surface a
/// user-facing result inline, and so FeedbackService can include the state in bug
/// reports.
enum SkillRegistrationStatus: Sendable {
    case notYetAttempted
    case succeeded(at: Date, skillsRoot: String)
    case failed(at: Date, step: String, error: String)

    var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    var displayMessage: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        switch self {
        case .notYetAttempted:
            return "Not yet attempted"
        case .succeeded(let at, _):
            return "Registered successfully at \(formatter.string(from: at))"
        case .failed(_, let step, let error):
            return "Failed at \(step): \(error)"
        }
    }
}

/// Manages skill registration in Cowork (Claude Code).
/// Discovers the skills-plugin directory, deploys SKILL.md wrappers,
/// and registers/updates entries in Cowork's manifest.json.
///
/// **v3.7.4 instrumentation overhaul:** every step of `registerWeeklyRhythmSkill()`
/// logs a breadcrumb to `ErrorLogger`, the silent returns in `deploySkillFile` and
/// `registerSkill` now throw specific errors, and every manifest write stamps a
/// `fortAbodeLastWrite` marker so the debug report can prove (or disprove) whether
/// Fort Abode actually wrote to the user's manifest.json.
actor CoworkSkillService {

    private let fm = FileManager.default

    /// Most recent outcome — read by the UI and the debug report.
    private(set) var lastRegistrationStatus: SkillRegistrationStatus = .notYetAttempted

    private var homePath: String {
        fm.homeDirectoryForCurrentUser.path
    }

    /// Base path for Cowork skills-plugin data
    private var skillsPluginBase: String {
        "\(homePath)/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin"
    }

    // MARK: - Weekly Rhythm Convenience

    private static let weeklyRhythmName = "weekly-rhythm-engine"
    private static let weeklyRhythmDescription = """
        The strategic engine for Kam's week \u{2014} work and personal life in one unified rhythm. \
        Runs on Fridays to plan the full coming week, and on-demand anytime something changes. \
        Synthesizes all Google Calendars, Apple Reminders, and Gmail into a clean weekly brief \
        shaped by day types, goals, errands, and milestone awareness.

        Trigger this skill for: "run my weekly rhythm", "set up my week", \
        "what's my plan for the week", "run the rhythm engine", "plan my week", \
        "what do I have going on this week", "update my week", or any variation of \
        wanting a structured weekly planning view. Also trigger for first-time setup \
        when no user config exists.
        """

    /// Full Cowork registration: deploy thin SKILL.md + register in manifest.
    /// Logs a breadcrumb at every step so the debug report reveals exactly which
    /// phase succeeded or failed on a given machine.
    func registerWeeklyRhythmSkill() async {
        await ErrorLogger.shared.log(
            area: "registerWeeklyRhythmSkill",
            message: "STEP 1: starting"
        )

        // STEP 2: discover the skills root (with diagnostics logged inline)
        await ErrorLogger.shared.log(
            area: "registerWeeklyRhythmSkill",
            message: "STEP 2: discovering Cowork skills root"
        )
        guard let skillsRoot = await discoverSkillsRootWithDiagnostics() else {
            // discoverSkillsRootWithDiagnostics already logged the specific failure reason
            lastRegistrationStatus = .failed(
                at: Date(),
                step: "discoverSkillsRoot",
                error: "Cowork skills-plugin directory could not be resolved"
            )
            return
        }
        await ErrorLogger.shared.log(
            area: "registerWeeklyRhythmSkill",
            message: "STEP 3: skillsRoot resolved",
            context: ["skillsRoot": skillsRoot]
        )

        // STEP 4: deploy the thin SKILL.md wrapper
        do {
            await ErrorLogger.shared.log(
                area: "registerWeeklyRhythmSkill",
                message: "STEP 4: calling deploySkillFile"
            )
            try deploySkillFile(
                skillName: Self.weeklyRhythmName,
                bundledResource: "weekly-rhythm-skill-wrapper",
                bundledExtension: "md",
                preResolvedSkillsRoot: skillsRoot
            )
            await ErrorLogger.shared.log(
                area: "registerWeeklyRhythmSkill",
                message: "STEP 5: deploySkillFile succeeded"
            )
        } catch {
            await ErrorLogger.shared.log(
                area: "registerWeeklyRhythmSkill",
                message: "FAILED at STEP 4 (deploySkillFile): \(error.localizedDescription)",
                context: ["error": String(describing: error), "skillsRoot": skillsRoot]
            )
            lastRegistrationStatus = .failed(
                at: Date(),
                step: "deploySkillFile",
                error: error.localizedDescription
            )
            return
        }

        // STEP 6: upsert the manifest.json entry
        do {
            await ErrorLogger.shared.log(
                area: "registerWeeklyRhythmSkill",
                message: "STEP 6: calling registerSkill"
            )
            try registerSkill(
                name: Self.weeklyRhythmName,
                description: Self.weeklyRhythmDescription,
                preResolvedSkillsRoot: skillsRoot
            )
            await ErrorLogger.shared.log(
                area: "registerWeeklyRhythmSkill",
                message: "STEP 7: registerSkill succeeded — DONE",
                context: ["skillsRoot": skillsRoot]
            )
        } catch {
            await ErrorLogger.shared.log(
                area: "registerWeeklyRhythmSkill",
                message: "FAILED at STEP 6 (registerSkill): \(error.localizedDescription)",
                context: ["error": String(describing: error), "skillsRoot": skillsRoot]
            )
            lastRegistrationStatus = .failed(
                at: Date(),
                step: "registerSkill",
                error: error.localizedDescription
            )
            return
        }

        lastRegistrationStatus = .succeeded(at: Date(), skillsRoot: skillsRoot)
    }

    /// Wraps `discoverSkillsRoot()` and logs the precise failure mode when it returns nil.
    /// Every silent-failure branch in `discoverSkillsRoot` has a matching log here so we
    /// can tell from a bug report whether Cowork isn't installed, the session structure
    /// is unexpected, or there's no manifest.json anywhere.
    private func discoverSkillsRootWithDiagnostics() async -> String? {
        // (1) Base path missing — Cowork was never launched / Claude Code not installed
        guard fm.fileExists(atPath: skillsPluginBase) else {
            await ErrorLogger.shared.log(
                area: "discoverSkillsRoot",
                message: "Cowork skills-plugin directory not found at \(skillsPluginBase). Claude Code has likely never been launched on this machine. Open Claude Code at least once, then reopen Fort Abode.",
                componentDisplayName: "Weekly Rhythm Engine"
            )
            return nil
        }

        // (2) Base exists but contains no session subdirectories
        guard let sessionDirs = try? fm.contentsOfDirectory(atPath: skillsPluginBase)
            .filter({ !$0.hasPrefix(".") }), !sessionDirs.isEmpty else {
            await ErrorLogger.shared.log(
                area: "discoverSkillsRoot",
                message: "Cowork skills-plugin at \(skillsPluginBase) exists but contains no session directories. Launch Claude Code and start at least one agent-mode session, then reopen Fort Abode.",
                componentDisplayName: "Weekly Rhythm Engine"
            )
            return nil
        }

        // (3) Pick the most recent session dir (matches discoverSkillsRoot logic)
        let sessionPath: String
        if sessionDirs.count == 1 {
            sessionPath = "\(skillsPluginBase)/\(sessionDirs[0])"
        } else {
            guard let picked = sessionDirs
                .map({ "\(skillsPluginBase)/\($0)" })
                .max(by: { path1, path2 in
                    let d1 = (try? fm.attributesOfItem(atPath: path1)[.modificationDate] as? Date) ?? .distantPast
                    let d2 = (try? fm.attributesOfItem(atPath: path2)[.modificationDate] as? Date) ?? .distantPast
                    return d1 < d2
                }) else {
                await ErrorLogger.shared.log(
                    area: "discoverSkillsRoot",
                    message: "Could not pick a session dir from \(sessionDirs.count) candidates under \(skillsPluginBase).",
                    componentDisplayName: "Weekly Rhythm Engine"
                )
                return nil
            }
            sessionPath = picked
        }

        // (4) Session dir exists but has no user subdirs
        guard let userDirs = try? fm.contentsOfDirectory(atPath: sessionPath)
            .filter({ !$0.hasPrefix(".") }), !userDirs.isEmpty else {
            await ErrorLogger.shared.log(
                area: "discoverSkillsRoot",
                message: "Cowork session dir \(sessionPath) has no user subdirectories. This usually means Claude Code hasn't completed initial agent-mode setup.",
                componentDisplayName: "Weekly Rhythm Engine"
            )
            return nil
        }

        // (5) Resolve to final user dir — single case is trusted, multi needs manifest.json
        if userDirs.count == 1 {
            return "\(sessionPath)/\(userDirs[0])"
        }

        if let withManifest = userDirs
            .map({ "\(sessionPath)/\($0)" })
            .first(where: { fm.fileExists(atPath: "\($0)/manifest.json") }) {
            return withManifest
        }

        await ErrorLogger.shared.log(
            area: "discoverSkillsRoot",
            message: "Cowork session \(sessionPath) has \(userDirs.count) user dirs but none contain manifest.json. Launch Claude Code and open an agent-mode session to initialize the manifest.",
            componentDisplayName: "Weekly Rhythm Engine"
        )
        return nil
    }

    // MARK: - Skill File Deployment

    /// Deploy a bundled SKILL.md wrapper to the Cowork skills directory.
    /// Overwrites existing SKILL.md but preserves all other files (evals/, user configs).
    ///
    /// **v3.7.4:** accepts an optional `preResolvedSkillsRoot` so `registerWeeklyRhythmSkill`
    /// can pass the root it already resolved (via the diagnostic wrapper). When nil, falls
    /// back to the sync `discoverSkillsRoot()` and THROWS on failure instead of silently
    /// returning — this is the single most important change in this release.
    func deploySkillFile(
        skillName: String,
        bundledResource: String,
        bundledExtension: String,
        preResolvedSkillsRoot: String? = nil
    ) throws {
        let skillsRoot: String
        if let preResolved = preResolvedSkillsRoot {
            skillsRoot = preResolved
        } else if let discovered = discoverSkillsRoot() {
            skillsRoot = discovered
        } else {
            // v3.7.4: previously returned silently. Now throws so the caller sees the
            // failure and it lands in the debug report.
            throw CoworkSkillError.skillsRootNotFound
        }

        guard let url = Bundle.main.url(forResource: bundledResource, withExtension: bundledExtension) else {
            throw CoworkSkillError.resourceNotFound(resource: "\(bundledResource).\(bundledExtension)")
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let skillDir = "\(skillsRoot)/skills/\(skillName)"

        // Create skill directory if needed
        if !fm.fileExists(atPath: skillDir) {
            try fm.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
        }

        // Write SKILL.md (overwrite stale versions)
        let skillFile = "\(skillDir)/SKILL.md"
        if fm.fileExists(atPath: skillFile) {
            try fm.removeItem(atPath: skillFile)
        }
        try content.write(toFile: skillFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Manifest Registration

    /// Register or update a skill entry in manifest.json.
    /// Upserts by name — preserves existing skillId if found.
    ///
    /// **v3.7.4:** accepts `preResolvedSkillsRoot` to match `deploySkillFile`, and THROWS
    /// on a nil skills root instead of silently returning.
    func registerSkill(
        name: String,
        description: String,
        preResolvedSkillsRoot: String? = nil
    ) throws {
        let skillsRoot: String
        if let preResolved = preResolvedSkillsRoot {
            skillsRoot = preResolved
        } else if let discovered = discoverSkillsRoot() {
            skillsRoot = discovered
        } else {
            // v3.7.4: previously returned silently. Now throws.
            throw CoworkSkillError.skillsRootNotFound
        }

        let manifestPath = "\(skillsRoot)/manifest.json"
        var manifest = readManifest(at: manifestPath) ?? ["skills": [[String: Any]](), "lastUpdated": 0]
        var skills = manifest["skills"] as? [[String: Any]] ?? []

        let now = ISO8601DateFormatter().string(from: Date())
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)

        // Find existing entry by name
        if let index = skills.firstIndex(where: { ($0["name"] as? String) == name }) {
            // Update existing — preserve skillId and creatorType
            skills[index]["description"] = description
            skills[index]["updatedAt"] = now
            skills[index]["enabled"] = true
        } else {
            // Add new entry
            let skillId = "skill_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"
            let entry: [String: Any] = [
                "skillId": skillId,
                "name": name,
                "description": description,
                "creatorType": "user",
                "updatedAt": now,
                "enabled": true
            ]
            skills.append(entry)
        }

        manifest["skills"] = skills
        manifest["lastUpdated"] = nowMillis

        try writeManifest(manifest, at: manifestPath)
    }

    // MARK: - Status

    /// Whether a skill is registered in Cowork's manifest.
    func isSkillRegistered(name: String) -> Bool {
        guard let skillsRoot = discoverSkillsRoot() else { return false }
        let manifestPath = "\(skillsRoot)/manifest.json"
        guard let manifest = readManifest(at: manifestPath),
              let skills = manifest["skills"] as? [[String: Any]] else { return false }
        return skills.contains { ($0["name"] as? String) == name }
    }

    /// Whether the deployed SKILL.md is the thin wrapper (not the stale full spec).
    func isSkillWrapperCurrent(name: String) -> Bool {
        guard let skillsRoot = discoverSkillsRoot() else { return false }
        let skillFile = "\(skillsRoot)/skills/\(name)/SKILL.md"

        guard let attrs = try? fm.attributesOfItem(atPath: skillFile),
              let size = attrs[.size] as? Int else { return false }

        // Thin wrapper is ~2KB, stale full spec is ~33KB
        return size < 5000
    }

    // MARK: - Unregistration

    /// Remove a skill from manifest.json and delete its skill directory.
    func unregisterSkill(name: String) throws {
        guard let skillsRoot = discoverSkillsRoot() else { return }

        // Remove from manifest
        let manifestPath = "\(skillsRoot)/manifest.json"
        if var manifest = readManifest(at: manifestPath),
           var skills = manifest["skills"] as? [[String: Any]] {
            skills.removeAll { ($0["name"] as? String) == name }
            manifest["skills"] = skills
            manifest["lastUpdated"] = Int64(Date().timeIntervalSince1970 * 1000)
            try writeManifest(manifest, at: manifestPath)
        }

        // Remove skill directory
        let skillDir = "\(skillsRoot)/skills/\(name)"
        if fm.fileExists(atPath: skillDir) {
            try fm.removeItem(atPath: skillDir)
        }
    }

    // MARK: - Private: Discovery

    /// Discover the Cowork skills root by scanning the two-level UUID directory structure.
    /// Returns nil if Cowork isn't installed or the structure is unexpected.
    private func discoverSkillsRoot() -> String? {
        guard fm.fileExists(atPath: skillsPluginBase) else { return nil }

        guard let sessionDirs = try? fm.contentsOfDirectory(atPath: skillsPluginBase)
            .filter({ !$0.hasPrefix(".") }) else { return nil }

        // Use the most recently modified session directory
        let sessionPath: String?
        if sessionDirs.count == 1 {
            sessionPath = "\(skillsPluginBase)/\(sessionDirs[0])"
        } else if sessionDirs.count > 1 {
            sessionPath = sessionDirs
                .map { "\(skillsPluginBase)/\($0)" }
                .max(by: { path1, path2 in
                    let d1 = (try? fm.attributesOfItem(atPath: path1)[.modificationDate] as? Date) ?? .distantPast
                    let d2 = (try? fm.attributesOfItem(atPath: path2)[.modificationDate] as? Date) ?? .distantPast
                    return d1 < d2
                })
        } else {
            return nil
        }

        guard let session = sessionPath else { return nil }

        guard let userDirs = try? fm.contentsOfDirectory(atPath: session)
            .filter({ !$0.hasPrefix(".") }) else { return nil }

        if userDirs.count == 1 {
            return "\(session)/\(userDirs[0])"
        } else if userDirs.count > 1 {
            // Use the one with a manifest.json
            return userDirs
                .map { "\(session)/\($0)" }
                .first { fm.fileExists(atPath: "\($0)/manifest.json") }
        }

        return nil
    }

    // MARK: - Private: Manifest I/O

    private func readManifest(at path: String) -> [String: Any]? {
        guard let data = fm.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Write the manifest, stamping a `fortAbodeLastWrite` marker so the debug report can
    /// confirm Fort Abode actually touched this manifest (independent of filesystem mtime,
    /// which is too noisy to trust).
    private func writeManifest(_ manifest: [String: Any], at path: String) throws {
        var mutableManifest = manifest
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        mutableManifest["fortAbodeLastWrite"] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "appVersion": appVersion,
            "build": build
        ]

        let data = try JSONSerialization.data(
            withJSONObject: mutableManifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

// MARK: - Errors

enum CoworkSkillError: LocalizedError {
    case resourceNotFound(resource: String)
    case manifestCorrupted
    case skillsRootNotFound

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let resource):
            return "Cowork skill resource '\(resource)' not found in app bundle"
        case .manifestCorrupted:
            return "Cowork skills manifest.json is corrupted"
        case .skillsRootNotFound:
            return "Cowork skills-plugin directory not found — Claude Code has likely never been launched on this machine, or the initial agent-mode session has not been started. Open Claude Code, start an agent-mode session, then reopen Fort Abode."
        }
    }
}
