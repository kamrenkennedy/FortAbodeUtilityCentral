# Diagnostic Prompt: Weekly Rhythm Not Showing in Cowork

**When to use this:** A user installed Weekly Rhythm through Fort Abode, the app reports it as "v2.0.0 up to date," but the skill does not appear in Claude Code / Cowork's skills list after restarting.

**How to use it:** Copy the prompt block below verbatim and paste it into Claude Code on the affected user's Mac. Claude has Bash and Read tool access and can inspect its own session state directly — this is faster than another round trip through the in-app feedback form.

**What it does:**
1. Lists every session directory under `skills-plugin/` with modification times so we can see if Fort Abode's "most recently modified" heuristic picked the wrong one
2. Checks every manifest.json for a `weekly-rhythm-engine` entry
3. Checks every skills/ directory for the weekly-rhythm-engine SKILL.md
4. Reads Fort Abode's ErrorLogger output from both the iCloud path and the local fallback
5. Identifies which session directory Cowork is *actually* reading from (by checking which one has the other skills we know are registered, like `shoot-sync` or `xlsx`)
6. Offers to fix by writing the missing entry to the correct manifest.json

---

## The Prompt (copy everything below this line into Claude Code on the affected Mac)

> I'm troubleshooting a bug in the Fort Abode Utility Central app. It says it registered a skill called `weekly-rhythm-engine` in Claude Code's skills-plugin manifest, but the skill is not appearing in your skills list. Please diagnose and then offer to fix.
>
> **Step 1 — Inventory every skills-plugin session directory.**
>
> Run:
> ```bash
> ls -la "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/"
> ```
>
> For each session UUID directory, list its contents and modification time:
> ```bash
> find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/" -maxdepth 2 -type d -exec stat -f "%Sm  %N" -t "%Y-%m-%d %H:%M" {} \;
> ```
>
> Report back: how many session UUIDs exist? How many user UUIDs under each? Which is the most recently modified?
>
> **Step 2 — For every manifest.json found, check if weekly-rhythm-engine is registered.**
>
> ```bash
> find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/" -name "manifest.json" -exec echo "=== {} ===" \; -exec grep -l "weekly-rhythm-engine" {} \;
> ```
>
> For each manifest.json, report: does it contain `weekly-rhythm-engine`? What other skills are listed? (I want to know which manifest Cowork is actually reading, based on which one has the skills that *are* currently showing up in your skills list.)
>
> **Step 3 — For every skills/ directory, check if the weekly-rhythm-engine folder and SKILL.md exist.**
>
> ```bash
> find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/" -type d -name "weekly-rhythm-engine"
> ```
>
> For each hit, check whether SKILL.md exists and its size (the thin wrapper should be around 2KB):
> ```bash
> find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/" -name "SKILL.md" -path "*/weekly-rhythm-engine/*" -exec ls -la {} \;
> ```
>
> **Step 4 — Read Fort Abode's error log.**
>
> Two possible paths:
> ```bash
> cat "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Claude Memory/fort-abode-errors.jsonl" 2>/dev/null | tail -20
> cat "$HOME/Library/Logs/FortAbodeUtilityCentral/errors.jsonl" 2>/dev/null | tail -20
> ```
>
> Report any entries mentioning `weekly-rhythm` or `Cowork skills-plugin`.
>
> **Step 5 — Identify the canonical session directory YOU are running from.**
>
> You (the Claude Code instance reading this prompt) are running inside one of those session directories. Look at your own skills list — which skills are showing up right now? Then find which `manifest.json` contains exactly that set of skills. That's the one Fort Abode *should* have written to.
>
> **Step 6 — Diagnose and report.**
>
> Tell me plainly:
> - How many candidate session dirs exist
> - Which one Cowork is reading from (the one whose skills match your skills list)
> - Whether `weekly-rhythm-engine` is in that manifest.json
> - Whether the `skills/weekly-rhythm-engine/SKILL.md` file exists in that dir
> - What Fort Abode's error log says, if anything
>
> **Step 7 — If weekly-rhythm-engine is missing from the correct manifest.json, offer to fix it.**
>
> The fix is:
> 1. Read the SKILL.md wrapper from Fort Abode's app bundle at `/Applications/Fort Abode Utility Central.app/Contents/Resources/weekly-rhythm-skill-wrapper.md`
> 2. Create the directory `<correct-session>/<user>/skills/weekly-rhythm-engine/`
> 3. Copy the wrapper to `<correct-session>/<user>/skills/weekly-rhythm-engine/SKILL.md`
> 4. Edit the correct `manifest.json` to add a new entry:
>    ```json
>    {
>      "skillId": "skill_<24-char-random-hex>",
>      "name": "weekly-rhythm-engine",
>      "description": "The strategic engine for Kam's week — work and personal life in one unified rhythm. Runs on Fridays to plan the full coming week, and on-demand anytime something changes. Synthesizes all Google Calendars, Apple Reminders, and Gmail into a clean weekly brief shaped by day types, goals, errands, and milestone awareness.\nTrigger this skill for: \"run my weekly rhythm\", \"set up my week\", \"what's my plan for the week\", \"run the rhythm engine\", \"plan my week\", \"what do I have going on this week\", \"update my week\", or any variation of wanting a structured weekly planning view. Also trigger for first-time setup when no user config exists.",
>      "creatorType": "user",
>      "updatedAt": "<ISO-8601-now>",
>      "enabled": true
>    }
>    ```
> 5. Update the top-level `lastUpdated` field to the current unix-ms timestamp
>
> Ask me to confirm before writing anything. After fixing, tell me to restart Claude Code (not just the session — fully quit and relaunch) and verify the skill appears.

---

## Why this diagnostic prompt approach works

Cowork has full filesystem access. It can see exactly what Fort Abode wrote, where it wrote it, and which session dir it's actually reading from. No round-tripping through feedback reports. We get an answer in one session.

## What to do with the findings

### Real-world case: Tiera's iMac, v3.7.2 → v3.7.3 (2026-04-15)

When we actually ran this prompt on Tiera's machine, the session-dir hypothesis was **disproven** — she had exactly 1 session UUID, 1 user UUID, clean layout. The real root cause was a **guard mismatch** between two functions that check install state using different file sets:

| Function | Files checked |
|---|---|
| `VersionDetectionService.parseICloudTemplateVersion` | ONLY `dashboard-template.html` |
| `WeeklyRhythmService.isConfigured()` | BOTH `dashboard-template.html` AND `engine-spec.md` |

On Tiera's Mac, `dashboard-template.html` existed but `engine-spec.md` was missing (partial install state from an older deploy or iCloud hiccup). Result:

1. Debug report showed **"Weekly Rhythm Engine: v2.0.0 (up to date)"** — version detection succeeded
2. But `isConfigured()` returned **false** — engine-spec.md missing
3. The self-heal block at `ComponentListViewModel.swift:464` silently skipped
4. `registerWeeklyRhythmSkill()` never called
5. No manifest entry, no skill dir, no error log

**Fix in v3.7.3**: changed the guard from `await weeklyRhythmService.isConfigured()` to `installed != nil`. Now both checks use the version-detection result as the install-state signal — partial installs recover, fresh installs still return nil (v3.7.1 auto-opt-in regression stays fixed). `updateManagedFiles()` already had partial-state recovery, so missing engine-spec.md gets redeployed from the app bundle before registration fires.

### Other possible causes (ranked by remaining likelihood)

If the diagnosis shows multiple session UUIDs and the wrong one has the weekly-rhythm skill (session-dir hypothesis, so far unconfirmed): update `CoworkSkillService.discoverSkillsRoot()` to pick the session dir whose manifest.json contains the most recently-updated skills, NOT the session dir with the most recently modified filesystem mtime. Filesystem mtime is too noisy — any process touching a file in the dir (including our own test writes) skews it.

If the diagnosis shows the manifest write succeeded but Cowork isn't picking it up: Cowork may cache the manifest on process start. Adding a `manifest.json` watcher to Cowork is out of scope for Fort Abode — the fix is documentation ("quit and relaunch Claude Code after Fort Abode install") plus maybe a Fort Abode UI hint.

If the diagnosis shows an ErrorLogger entry we didn't expect: new check for the `fort-abode-preflight` skill.

## Update this file as we learn

Any time this diagnostic flow uncovers a new root cause or we add a new step, update this file in the same changeset as the fix. Same self-replication rule as the preflight skill.
