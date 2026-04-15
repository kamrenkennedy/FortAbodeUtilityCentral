---
name: fort-abode-preflight
description: Pre-commit checklist for Fort Abode Utility Central. Run before any commit that touches FortAbodeUtilityCentral/. Catches the bug classes that have historically shipped broken updates to Kam's or Tiera's Mac — silent Cowork registration failures, auto-opt-in regressions, display bugs, appcast drift, missing version bumps. Self-replicating: every new bug class discovered gets a new checklist entry here so the same mistake never ships twice.
---

# Fort Abode Preflight

## When to run

Invoke this skill **after the code is done and before you stage files for commit**, any time the diff touches `FortAbodeUtilityCentral/`. The project's CLAUDE.md requires it — this is load-bearing, not optional.

Process:

1. Run `git status` and `git diff --stat` to see what's in the changeset
2. For each path in the diff, find the matching section below
3. Walk every checklist item in that section — if you can't confirm it from the diff or the file, read the file and check
4. If a check fails, stop and fix before committing
5. Run the "always-check" section last regardless of what changed
6. Report a condensed pass/fail summary back to the user ("preflight: 12 checks, all pass" or "preflight: item 4 failed, fixing")

Never skip a check because "it's a tiny change." The v3.7.1 auto-opt-in bug was four lines.

## Conditional checks by path

### If the diff touches `Resources/component-registry.json`

1. **Copy matches behavior** — every `user_description` and `usage_instructions` field describes what the component actually does as of this release. If the component's capabilities changed (e.g. Memory gained family support in v3.7.1), the copy must name that change. Stale copy means Tiera sees an "update available" card with no idea what's new.
2. **setup_flow steps are valid** — every step's `type` is a real `SetupStepType` case (check `Models/Component.swift`). Every `input_config.field_name` is unique within the flow. Every `multi_choice` has at least two options.
3. **MCP requirements are researched** — if adding a new MCP, the `CLAUDE.md > Adding New MCPs to the Marketplace` waterfall was followed: env-vars-only → paste-a-token → interactive auth. Never ship a custom OAuth flow without checking for a wrapper MCP first.
4. **Placeholders resolve** — any `{{MEMORY_PATH}}` or similar placeholder has a matching resolver in the install pipeline. Grep for the placeholder string in the Swift sources.
5. **Version source is correct** — `version_source: keychainSecret` means the "version" is a literal like `"configured"` — the display layer MUST strip the `v` prefix (see UpdateStatus check below).

### If the diff touches `ViewModels/ComponentListViewModel.swift`

1. **Launch-time self-heal is gated on install state** — any block that deploys files, writes to Cowork's manifest.json, or runs `npx` on app launch MUST be guarded by a check that the user previously installed the component (`isConfigured()`, existence of a key file, a keychain entry, etc.). Without the guard, every Fort Abode update silently opts users in to components they never chose. (This is the exact v3.7.1 regression — ComponentListViewModel.swift:452-459 ran outside the `if installed != nil` guard.)
2. **Install-state guards use version detection, not file existence** — the gating condition for a launch-time self-heal block MUST check `installed != nil` (the version-detection result returned by `VersionDetectionService.detectInstalledVersion`), NOT a secondary file-existence helper like `service.isConfigured()`. If two functions check different file sets for the same "is this installed?" question, they WILL diverge in partial-install states. The v3.7.2→v3.7.3 bug: `VersionDetectionService.parseICloudTemplateVersion` read only `dashboard-template.html` while `WeeklyRhythmService.isConfigured()` required BOTH `dashboard-template.html` AND `engine-spec.md`. On Tiera's Mac, the template existed (version reported "v2.0.0 up to date") but engine-spec.md was missing (isConfigured() returned false), so the self-heal block silently skipped, leaving Cowork with no manifest entry. The fix: gate on `installed != nil` and let `updateManagedFiles()` redeploy any missing files from the bundle.
3. **Self-heal is idempotent** — calling it twice in a row must be safe. Registration functions upsert by name; file writes overwrite atomically. Never append without a dedupe check.
4. **Self-heal logs on failure** — if a self-heal step can't complete (Cowork not installed, iCloud folder missing, network unreachable), it must call `ErrorLogger.shared.log` with a specific actionable message. Silent `return nil` branches are the #1 cause of "it just didn't work" bug reports.
5. **Post-install hooks still work** — if you refactored a self-heal helper, verify the post-install call sites still produce the same effect. The initial install path and the launch-time re-run path must converge on the same state.

### If the diff touches `Services/CoworkSkillService.swift` (or any skill-registration code)

1. **Every discovery failure branch logs** — the canonical Cowork path has four failure modes: base dir missing, no session subdirs, no user subdirs, no manifest.json. Each branch must have its own `ErrorLogger.shared.log` with path-specific guidance ("launch Claude Code once, then reopen Fort Abode"). Do not consolidate branches into a single generic message — specificity is what makes Tiera's bug reports debuggable.
2. **Manifest writes upsert** — registering a skill with the same `name` twice must update, not duplicate. Check by `name`, preserve existing `skillId` and `creatorType`.
3. **SKILL.md deploy preserves user files** — overwriting `SKILL.md` is fine, but never touch sibling files in the same skill directory (evals/, user configs, etc.).
4. **Uninstall is symmetric** — if you added a registration call, make sure there's a matching unregister path for when the component is removed from the marketplace or the user uninstalls it.
5. **No silent returns in skill-registration code paths** — every `guard let ... else { return }` in `CoworkSkillService.swift` that guards a filesystem operation or state transition MUST either (a) `throw` a specific error that the caller logs, or (b) call `ErrorLogger.shared.log` with the exact reason and the context it needs to be debugged. Bare `return`s in this file are the single most expensive class of bug we ship — the v3.7.1 → v3.7.3 debugging marathon (three shipped releases, none of which fixed Tiera's Mac) was entirely because `deploySkillFile:152` and `registerSkill:181` silently returned when `discoverSkillsRoot()` was nil. The outer `do/catch` in `registerWeeklyRhythmSkill` never fired, no log was written, no debug report ever captured the failure, and we spent three releases theorizing instead of fixing. Never again.
6. **Every step of `registerWeeklyRhythmSkill` logs a breadcrumb** — at minimum: STEP 1 (starting), STEP N (before each failure-prone call), STEP N+1 (on success). The debug report should read like a flight recorder — if it fails at STEP 4, we know exactly which line. Success paths log too; `lastRegistrationStatus` stays accurate.
7. **Manifest writes stamp `fortAbodeLastWrite`** — every `writeManifest()` call must add a `fortAbodeLastWrite` dictionary with `timestamp`, `appVersion`, and `build`. This is the canonical "did Fort Abode actually touch this file?" signal — filesystem mtime is too noisy to trust because any process can bump it. The debug report's skills-plugin inventory reads this marker to confirm (or disprove) that Fort Abode's last registration attempt actually landed.

### If the diff touches `Services/ErrorLogger.swift`

1. **Dual-write stays intact** — every `log()` call must attempt BOTH the iCloud path AND the local fallback, and the `lastWriteStatus` enum must accurately reflect the outcome (`icloudOk`, `localOnlyOk`, or `bothFailed`). Never remove the local fallback just because iCloud is "usually there" — on Tiera's Mac, iCloud writes failed silently for an unknown stretch of time and we couldn't see any breadcrumbs from her machine until v3.7.4 added the fallback.
2. **iCloud log path stays inside `Fort Abode Logs/`** — the canonical path is `Claude Memory/Fort Abode Logs/errors.jsonl`. Never revert to writing loose files at the Claude Memory root — that was the pre-v3.7.4 mess that cluttered up Kam's memory folder with diagnostic files. Any new log files (crash logs, registration traces, etc.) go into the same `Fort Abode Logs/` subfolder as sibling files, never loose.
3. **Legacy migration still runs** — if you refactor `migrateLegacyFileIfNeeded()`, verify that the old `fort-abode-errors.jsonl` at the Claude Memory root still gets moved into `Fort Abode Logs/errors-legacy.jsonl` on first launch after upgrade. Users who've been on v3.7.3 or earlier shouldn't be left with a stray file.
4. **New log entries use `area` + `message`** — the new canonical fields are `area` (e.g. `CoworkSkillService.deploySkillFile`) and `message` (the human-readable description), with optional `context: [String: String]?` for structured data. The legacy `componentId` / `errorMessage` fields still decode for backwards compat but new call sites must use the new names via `ErrorLogger.shared.log(area:message:context:)`.
5. **`FeedbackService.generateDebugReport` still reads the state snapshot + write status** — the expanded report (Weekly Rhythm state snapshot + Logger lastWriteStatus + recent log entries) is load-bearing for future debugging. Don't remove any of those sections unless you're replacing them with something better.

### If the diff touches `Services/FilePinningService.swift`

1. **Paths match the actual iCloud layout** — do not trust the existing hardcoded path. Run `ls` against the real iCloud directory and confirm every target root in the code actually exists on disk. The v3.7.1 pinning bug was three months old because the base path was wrong and the `fileExists` guard silently no-op'd.
2. **Pinning is recursive** — `brctl download` is non-recursive. If you want a whole tree pinned, walk it with `FileManager.enumerator(atPath:)` and call `brctl download` on every directory.
3. **Pinning runs on launch, not just install** — macOS evicts files. If the only call site is a post-install hook, the files will be gone a week later. Verify the app-launch entry point still calls `pinAll()`.
4. **Missing folders skip gracefully** — Tiera's Mac may not have a given folder yet. Each target root must guard on `fileExists` and continue to the next one on miss — never error out the whole pin run.

### If the diff touches `Models/UpdateStatus.swift` or any component-version display code

1. **Version formatting handles non-numeric strings** — keychain-backed components return literals like `"configured"` or `"installed"`. The display layer must NOT prefix `v` to those (renders as `"vconfigured"`, which is exactly what Tiera's v3.7.1 bug report showed). Every code path that builds a version-display string must run through a formatter that only prefixes `v` when the first character is a digit.
2. **Both display sites are fixed** — the bug lived in BOTH `ComponentRowView.swift` AND `UpdateStatus.debugLabel`. When fixing a display bug, grep the whole codebase for the raw `"v\(version)"` pattern and fix every occurrence, not just the one you can see in the UI.
3. **Debug reports reflect the fix** — the `FeedbackService.generateDebugReport` output is what ends up in Notion bug reports. Verify the fix flows through to `debugLabel`, not just the on-screen Text view.

### If the diff adds a new MCP to `component-registry.json`

1. **Research auth model BEFORE writing the setup_flow** — does it have a `manage_accounts`-style internal tool? Is there a wrapper package (like `@aaronsb/google-workspace-mcp`)? Can it work with just env vars? Only build a wizard if none of those work.
2. **Env vars > paste-a-token > interactive auth** — follow the waterfall in project CLAUDE.md.
3. **Test on a clean machine mentally** — walk the setup_flow as if you're Tiera seeing it for the first time. Every step's title and body must make sense without context. No jargon ("OAuth scope", "npx cache") unless you explain it inline.
4. **If the MCP requires a key that must sync across machines, flag it** — add a note to the APP TO-DO LIST in the memory entity. Cross-machine key sync is an open architectural problem (see Travel Itinerary Google Maps API key) — do not assume it's solved.

## Always-check section (runs regardless of diff)

Every preflight run ends with these:

1. **`project.yml` version bump if shipping a release** — if this commit is going to be tagged, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are both bumped. Infrastructure-only commits (docs, skills, CI) don't need a bump.
2. **`xcodegen generate` has been re-run** — if `project.yml` changed, `xcodegen` was run afterward. The `.xcodeproj/` changes must be in the same commit.
3. **BOTH `appcast.xml` files have matching entries** — if shipping a release, the root `appcast.xml` and the subdirectory `FortAbodeUtilityCentral/appcast.xml` both have a `<item>` for this version with matching `sparkle:edSignature` and length. Root-appcast drift is historical failure mode #1 (CLAUDE.md:50).
4. **`whats-new.json` has a new entry for this version** — if shipping a release, there's a new top-of-array object with this version's notes. Notes describe user-visible behavior, not implementation details.
5. **No API keys, tokens, or secrets in the diff** — `git diff` does NOT contain any `sk-`, `ghp_`, `pat-`, `AIza`, Bearer tokens, or `.env`-style KEY=VALUE pairs. If the diff touches `Resources/*.json` files, those files are either intentionally public config or explicitly excluded from git via `.gitignore`.
6. **No files from `Resources/` were deleted unintentionally** — `project.yml`'s `sources` list still matches what's on disk. Deleting a bundled resource without removing it from `project.yml` causes a build failure on CI.
7. **Commit message follows Kam's conventions** — imperative mood, explains the "why" not the "what", ends with `Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>`.

## Self-replication rule

**Every time a new bug class ships to Kam's or Tiera's Mac, add a new check to this skill that would have caught it.** When you finish a session where a bug was root-caused and fixed:

1. Figure out which section the bug belonged in (or create a new section if it's a new path)
2. Write a check that would have failed the preflight if the buggy code had been run through it
3. Phrase the check in terms of what to verify, not what the original bug was
4. Commit the skill update in the same changeset as the fix

The skill grows over time. It is expected to be 3x longer in a year than it is today. A long preflight is a feature — it means every past mistake is remembered.

## What this skill is NOT

- **Not a substitute for testing** — it's a static checklist, not a build. Always still run `xcodegen generate` and `xcodebuild` locally before shipping a release.
- **Not a git hook** — hooks run on every commit including WIPs, docs, and merges, which would make it noise. This skill runs only when you (Claude) explicitly invoke it, ideally right before staging files for a real commit.
- **Not exhaustive** — it catches known bug classes. New bug classes still require human thought. When in doubt, ask Kam.
