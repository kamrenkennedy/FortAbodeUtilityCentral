import AppKit
import Foundation

// MARK: - Cowork Skill Service (v3.7.9 — clipboard-based setup)

/// Provides the Weekly Rhythm Engine setup prompt for users to paste into Cowork.
///
/// **v3.7.9 rewrite — the simplest version yet.** After eight releases trying to
/// auto-register the skill (direct manifest writes, CLI plugin install, direct
/// file writes to ~/.claude/skills/), we discovered that Cowork only properly
/// loads skills written by its OWN tools — not by external apps. The approach
/// that works: copy a ready-to-paste prompt to the clipboard, user pastes it
/// into a Cowork session, and Cowork's own Claude reads the engine spec from
/// iCloud and writes the SKILL.md using Cowork's native file tools.
///
/// Verified on Tiera's Mac 2026-04-15: Cowork read the full engine-spec.md,
/// wrote ~39,568 chars to ~/.claude/skills/weekly-rhythm-engine/SKILL.md, and
/// loaded the correct connectors (Tiera-Deep-Context, Tiera-Memory).
actor CoworkSkillService {

    /// The setup prompt that users paste into a Cowork session to register the skill.
    /// This is the exact prompt that worked on Tiera's Mac.
    static let setupPrompt = """
        I need you to set up my Weekly Rhythm Engine skill. Please do the following:

        1. Read the full engine specification from: ~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Weekly Rhythm/engine-spec.md

        2. Create the skill directory and file at ~/.claude/skills/weekly-rhythm-engine/SKILL.md with:
           - Start with this exact YAML frontmatter:
             ---
             name: weekly-rhythm-engine
             model: opus
             description: >
               The strategic engine for my week — work and personal life in one unified rhythm.
               Trigger for: "run my weekly rhythm", "set up my week", "plan my week",
               "what's my plan for the week", "run the rhythm engine"
             ---
           - Then paste the ENTIRE contents of engine-spec.md after the closing ---

        3. Confirm the file was written successfully.
        """

    /// Copy the setup prompt to the system clipboard.
    /// Returns true if the copy succeeded (it always does on macOS, but the
    /// return value is there for completeness).
    @MainActor
    func copySetupInstructionsToClipboard() -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(Self.setupPrompt, forType: .string)

        Task {
            await ErrorLogger.shared.log(
                area: "CoworkSkillService.copySetupInstructions",
                message: "Setup instructions copied to clipboard",
                context: ["promptLength": "\(Self.setupPrompt.count)"]
            )
        }

        return success
    }
}
