import Foundation

// MARK: - Skill Deploy Result

/// Outcome of deploying the Weekly Rhythm SKILL.md to the user skills directory.
enum SkillDeployResult: Sendable, Equatable {
    case notYetAttempted
    case succeeded(at: Date, path: String)
    case failed(at: Date, error: String)

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
            return "Skill deployed at \(formatter.string(from: at)) — say \"run my weekly rhythm\" in Claude to use it"
        case .failed(_, let error):
            return "Deploy failed: \(error)"
        }
    }
}

// MARK: - Cowork Skill Service (v3.7.7 — write to ~/.claude/skills/)

/// Deploys the Weekly Rhythm Engine skill to Claude's user skills directory.
///
/// **v3.7.7 rewrite — the simplest version yet.** After six releases trying to get
/// the skill into Cowork's internal state (v3.7.1-v3.7.5 wrote directly to
/// `manifest.json` which Cowork clobbered; v3.7.6 used `claude plugin install`
/// which targets a parallel system Cowork doesn't read), we discovered that
/// Cowork's own `skill-creator` tool writes skills to `~/.claude/skills/<name>/SKILL.md`.
/// That's a simple user-level skills directory that Cowork picks up via natural
/// language matching. When Tiera ran skill-creator manually on her Mac and then
/// typed "run my weekly rhythm", the skill worked perfectly — full engine spec
/// loaded from iCloud, day types recognized, personalized output generated.
///
/// v3.7.7 does exactly what skill-creator did: write SKILL.md to
/// `~/.claude/skills/weekly-rhythm-engine/SKILL.md`. One directory creation +
/// one file write. No CLI, no marketplace, no manifest, no plugin system.
/// Fort Abode overwrites this file on every install/update so the wrapper
/// stays current when the engine spec evolves.
///
/// The skill triggers via natural language ("run my weekly rhythm", "plan my week",
/// etc.) rather than slash-command autocomplete. Slash commands are for embedded
/// plugin skills; user-level skills at `~/.claude/skills/` trigger via description
/// matching. Both work — it's just a different invocation style.
actor CoworkSkillService {

    private let fm = FileManager.default

    /// Most recent outcome — read by the UI and the debug report.
    private(set) var lastDeployResult: SkillDeployResult = .notYetAttempted

    /// The user-level skills directory that Cowork reads from.
    /// This is where skill-creator writes when creating user skills.
    private var userSkillsDir: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
    }

    /// The specific skill directory for weekly-rhythm-engine.
    private var weeklyRhythmSkillDir: URL {
        userSkillsDir.appendingPathComponent("weekly-rhythm-engine")
    }

    /// The SKILL.md file path.
    private var weeklyRhythmSkillFile: URL {
        weeklyRhythmSkillDir.appendingPathComponent("SKILL.md")
    }

    // MARK: - Public API

    /// Deploy the bundled SKILL.md wrapper to `~/.claude/skills/weekly-rhythm-engine/SKILL.md`.
    /// Overwrites on every call so Fort Abode updates to the wrapper are picked up.
    /// Returns the deploy result for UI display.
    @discardableResult
    func deployWeeklyRhythmSkill() async -> SkillDeployResult {
        await ErrorLogger.shared.log(
            area: "deployWeeklyRhythmSkill",
            message: "Starting skill deploy to ~/.claude/skills/"
        )

        // Read the bundled wrapper from the app bundle
        guard let bundledURL = Bundle.main.url(
            forResource: "weekly-rhythm-skill-wrapper",
            withExtension: "md"
        ) else {
            let error = "weekly-rhythm-skill-wrapper.md not found in app bundle"
            await ErrorLogger.shared.log(
                area: "deployWeeklyRhythmSkill",
                message: "FAILED: \(error)"
            )
            let result = SkillDeployResult.failed(at: Date(), error: error)
            lastDeployResult = result
            return result
        }

        do {
            let content = try String(contentsOf: bundledURL, encoding: .utf8)

            // Create the skill directory if needed
            if !fm.fileExists(atPath: weeklyRhythmSkillDir.path) {
                try fm.createDirectory(
                    at: weeklyRhythmSkillDir,
                    withIntermediateDirectories: true
                )
            }

            // Write SKILL.md (overwrite any existing version)
            try content.write(to: weeklyRhythmSkillFile, atomically: true, encoding: .utf8)

            let path = weeklyRhythmSkillFile.path
            await ErrorLogger.shared.log(
                area: "deployWeeklyRhythmSkill",
                message: "Skill deployed successfully",
                context: ["path": path, "bytes": "\(content.utf8.count)"]
            )

            let result = SkillDeployResult.succeeded(at: Date(), path: path)
            lastDeployResult = result
            return result
        } catch {
            let message = error.localizedDescription
            await ErrorLogger.shared.log(
                area: "deployWeeklyRhythmSkill",
                message: "FAILED: \(message)",
                context: ["error": String(describing: error)]
            )
            let result = SkillDeployResult.failed(at: Date(), error: message)
            lastDeployResult = result
            return result
        }
    }

    /// Remove the skill from the user skills directory.
    /// Called from `ComponentListViewModel.uninstallComponent` for weekly-rhythm.
    func removeWeeklyRhythmSkill() async {
        await ErrorLogger.shared.log(
            area: "removeWeeklyRhythmSkill",
            message: "Removing skill from ~/.claude/skills/"
        )
        if fm.fileExists(atPath: weeklyRhythmSkillDir.path) {
            try? fm.removeItem(at: weeklyRhythmSkillDir)
        }
    }

    /// Whether the skill file currently exists at the user skills path.
    func isSkillDeployed() -> Bool {
        fm.fileExists(atPath: weeklyRhythmSkillFile.path)
    }
}
