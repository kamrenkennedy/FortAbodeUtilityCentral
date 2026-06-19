# CLAUDE.md — Fort Abode Utility Central

## Project Overview

Native macOS SwiftUI app that manages Kam's Claude infrastructure — MCP servers, skills, and auto-updates. Built for the Kennedy family (Kam + Tiera). Currently v3.12.1 (build 41).

- **Bundle ID**: `com.kamstudios.fortabodeutilitycentral`
- **GitHub**: `kamrenkennedy/FortAbodeUtilityCentral` (public)
- **Stack**: SwiftUI, Swift 6, macOS 14+, non-sandboxed, hardened runtime
- **Signing**: Developer ID Application, team X6LBF9H7M5, manual signing
- **Updates**: Sparkle 2 (EdDSA signed)
- **Project generation**: xcodegen (`/opt/homebrew/bin/xcodegen`)

## Preflight is mandatory

**Before staging any commit that touches `FortAbodeUtilityCentral/`, invoke the `fort-abode-preflight` skill** (at `skills/fort-abode-preflight/SKILL.md`). It walks a conditional checklist keyed to the paths in your diff and catches the bug classes that have historically shipped broken updates to Kam's or Tiera's Mac. This is not optional — every session that ships code must run through it.

If the preflight surfaces a failure, fix it before committing. If you discover a new bug class that preflight didn't catch, add a new check to the skill file in the same changeset as the fix. The skill is self-replicating — it grows every time we learn something the hard way.

## Repository Structure

The **git repo root** is `Fort Abode Utility Central/` — NOT the `FortAbodeUtilityCentral/` subdirectory. This matters for paths in git commands and for the appcast.

```
Fort Abode Utility Central/          ← git root
├── appcast.xml                      ← ROOT appcast (what Sparkle fetches via SUFeedURL)
├── build/                           ← exported .app goes here
├── FortAbodeUtilityCentral/         ← Xcode project subdirectory
│   ├── project.yml                  ← xcodegen config (version lives here)
│   ├── appcast.xml                  ← SUBDIRECTORY appcast (keep in sync with root!)
│   ├── Resources/
│   │   ├── Info.plist               ← explicit (not generated) — has SUFeedURL, SUPublicEDKey
│   │   ├── component-registry.json  ← marketplace components
│   │   └── Assets.xcassets/
│   ├── App/
│   ├── Models/
│   ├── Views/
│   ├── ViewModels/
│   └── Services/
└── Fort Abode — Skills Support Spec.pdf
```

## Adding New MCPs to the Marketplace

**First option (gold standard):** One-click install with env vars only. If the MCP handles auth internally via its own tools (like `manage_accounts`), just write the config entry with the required env vars. No wizard, no setup flow. Example: `@aaronsb/google-workspace-mcp` takes `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET` as env vars and handles multi-account auth through Claude's tool system.

**Second option:** Paste-a-token wizard (like Notion). Only if the MCP requires a user-provided secret that must be collected before install. Use the existing `setup_flow` system with `secure_input` steps.

**Last resort:** Interactive auth (browser OAuth, terminal commands). Avoid building custom auth flows in the app — if the MCP can't handle auth through its own tools, evaluate whether a wrapper MCP exists that does.

**Always research the MCP's auth model first** before building any wizard steps. Check: does it have built-in account management tools? Does a wrapper package exist that handles auth? Can it work with just env vars?

## Critical Rules

### Two Appcast Files
There are TWO `appcast.xml` files — the repo root one (what Sparkle fetches) and the one inside `FortAbodeUtilityCentral/`. **BOTH must be updated on every release.** Forgetting the root one causes Sparkle to report "up to date" even when updates exist.

### SUPublicEDKey
The correct EdDSA public key is: `y+SVlkSIOrgn/DOapgxZG39y29vhGl9BI/nGVSI5Tz0=`
- That's capital letter **I**, not digit **1**, at position 8
- Never manually type this key — always copy from `generate_keys` output
- The signing keypair lives in macOS Keychain (accessed automatically by `sign_update`)

### Version Bumping
Version and build number live in `project.yml`:
```yaml
MARKETING_VERSION: "X.Y.Z"
CURRENT_PROJECT_VERSION: "N"
```
After changing these, always run `xcodegen generate` before building.

### Info.plist
Uses an **explicit** `Resources/Info.plist` — not `GENERATE_INFOPLIST_FILE`. This is because Sparkle's custom keys (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`) are not Apple-recognized keys and would be silently dropped by the generated plist mechanism.

### AlignedDesignSystem package source
**Always pin via the GitHub URL, never a local `path:`.** `project.yml` must declare:
```yaml
AlignedDesignSystem:
  url: https://github.com/kamrenkennedy/AlignedDesignSystem.git
  from: "1.1.0"
```
Repo: `https://github.com/kamrenkennedy/AlignedDesignSystem` (private). Local Dropbox copy at `~/Library/CloudStorage/Dropbox-KamStudios,LLC/Aligned/App Projects/AlignedDesignSystem/` is for editing the design system itself — never as a SwiftPM source for Fort Abode. The relative-path form (`path: ../../../../...`) breaks in `.claude/worktrees/` because they sit one extra level deep, and it's fragile across machines because resolution is anchored to `project.yml`'s location. When AlignedDesignSystem ships a new tag, bump the `from:` version here in the same commit. The fort-abode-preflight skill (always-check 2b) verifies this on every commit.

### WHAT'S NEW changelog is mandatory for every release

**Every Fort Abode release MUST add an entry to `FortAbodeUtilityCentral/Resources/whats-new.json` before bumping `project.yml`.** That JSON drives the in-app "WHAT'S NEW" panel users see after auto-update — without an entry, Sparkle still ships the new version but users see no description of what changed and may assume nothing did.

Format: array entries with `{version: "X.Y.Z", notes: ["..."]}`. Notes are user-facing (not engineering jargon). One sentence per bullet. Lead with the user-visible change, not the implementation.

**Cross-repo discipline — non-negotiable:** When a bundled component bumps version (Weekly Rhythm engine, setup-claude-memory, travel-itinerary, etc.), the corresponding Fort Abode release that ships the new bundled copy MUST include WHAT'S NEW notes describing the user-visible component change. Without this, users see a Fort Abode update card with no idea their Weekly Rhythm now writes a dashboard JSON, their Travel Itinerary added a new feature, etc. Every project CLAUDE.md that ships through Fort Abode mirrors this rule in its own release ceremony.

#### Authoring rules — Tiera's reading guide

Tiera is the primary reader of every WHAT'S NEW entry. If an entry is too long or too technical she'll skip it, and the update lands silently from her perspective. The volume creep on bigger releases makes it easy to ship a 12-bullet wall of text — every entry must pass these seven rules:

1. Lead with user-visible behavior. Never the implementation.
2. Plain English. No `MCP`, phase codes (`Y6`, etc.), `engine spec`, `session-id`, `runner`, `parser`, `delegate`, `appcast`, `Sparkle`, internal file/class names, etc.
3. One sentence per bullet. If two are needed, the second is a "how to use it" line for Tiera, not a "how it works" line.
4. **Maximum 5–7 bullets per release.** Consolidate aggressively — a 12-bullet draft becomes a 5-bullet final by collapsing related work and dropping anything invisible to the user.
5. Reference where the user finds the change ("in the Family tab", "on the Weekly Rhythm dashboard", etc.).
6. Silent bug fixes aggregate to ONE bottom bullet: "Various fixes and stability improvements."
7. Bundled-component bumps still get a bullet describing the user-visible improvement, not the version number.

**Kam-approval gate (enforced by the `fort-abode-preflight` skill):** before staging any change to `whats-new.json`, Claude must draft the proposed entry as plain text in chat — for big releases, draft both a "long version" and a ≤5-bullet "Tiera version" side-by-side — and explicitly ask "Is this Tiera-ready, or want me to consolidate further?" Only commit after Kam confirms in chat. See the preflight skill's "If the diff touches `Resources/whats-new.json`" section for the full procedure.

## Release Process

1. **Update `FortAbodeUtilityCentral/Resources/whats-new.json` FIRST** — add a new top-of-array entry for the version about to ship. Cover both Fort Abode app changes AND any bundled-component changes from upstream releases (Weekly Rhythm, setup-claude-memory, travel-itinerary, etc.).
2. Edit `project.yml` — bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`
3. `/opt/homebrew/bin/xcodegen generate`
4. Xcode → Product → Archive → Distribute App → Direct Distribution → Export
5. `xcrun stapler staple "Fort Abode Utility Central.app"` (BEFORE zipping)
6. `cd build && ditto -c -k --keepParent "Fort Abode Utility Central.app" ../FortAbodeUtilityCentral/FortAbodeUtilityCentral-vX.Y.Z.zip`
7. Sign: `sign_update FortAbodeUtilityCentral-vX.Y.Z.zip` (outputs EdDSA signature + length)
8. Update **BOTH** `appcast.xml` files with new `<item>` entry (signature + length from step 7)
9. `git add && git commit && git push`
10. `gh release create vX.Y.Z FortAbodeUtilityCentral-vX.Y.Z.zip --title "vX.Y.Z" --notes "..."`

### Tool Locations
- **xcodegen**: `/opt/homebrew/bin/xcodegen`
- **sign_update**: locate with `find ~/Library/Developer/Xcode/DerivedData -type f -name sign_update -path '*Sparkle*'` — the DerivedData hash changes per package resolve, so never hardcode the path
- **generate_keys**: same directory as `sign_update` (locate the same way)

## Architecture

### Services (all actors for concurrency safety)
- `ClaudeDesktopConfigService` — reads/writes `claude_desktop_config.json`
- `VersionDetectionService` — detects installed versions (npx cache, local dirs, config)
- `UpdateExecutionService` — runs npm installs, finds Node.js across nvm/fnm/Homebrew
- `GitHubService` — fetches versions from GitHub API + npm registry, caches changelogs
- `KeychainService` — family activation via macOS Keychain (SHA-256 hashed code)
- `NotificationService` — system notifications for available updates
- `BackgroundTaskService` — LaunchAgent for background update checks
- `ErrorLogger` — logs errors to iCloud for remote debugging

### Key Patterns
- `ComponentRegistry` loads from bundled JSON at init, fetches from GitHub on `refresh()`, caches locally
- `{{MEMORY_PATH}}` placeholder in `component-registry.json` is resolved at install time to the iCloud Claude Memory path
- Install flow: npm cache → write to `claude_desktop_config.json` → verify → badge
- Self-healing: `checkAll()` detects half-installs (npx cached but config missing) and auto-repairs
- Dual detection: component is "installed" if npx cache OR config entry is present

## Coding Preferences

### Swift / SwiftUI Specific
- Swift 6 strict concurrency — use actors for shared mutable state, `@MainActor` for UI-bound classes
- `@Observable` (not `ObservableObject`) — this is a modern SwiftUI app
- Prefer `async/await` and `withTaskGroup` for concurrent work
- Use `JSONDecoder` with `.convertFromSnakeCase` for JSON ↔ Swift mapping
- Enums with associated values for type-safe modeling (see `VersionSource`, `UpdateSource`, `UpdateCommand`)
- `ComponentType.skill` exists in the data model but skills are not yet implemented

## Session Protocol (project-specific)

In addition to the global session protocol:

### Starting a Session
1. Check Kam Memory MCP for `Fort_Abode_Utility_Central` entity — has current version, phase status, key decisions
2. **Ask Kam which phase he wants to work on** — don't assume
3. **Ask if Kam wants to move the Skills phase to a different position in the roadmap** — it's fully specced but tabled

### Ending a Session
Update the `Fort_Abode_Utility_Central` entity specifically with current version number, phase status changes, and what's next.

## Current Phase Status

| Phase | Status |
|-------|--------|
| Core app + Sparkle (v1.0–1.3) | COMPLETE |
| Major redesign + marketplace (v2.0) | COMPLETE |
| Install → config + self-healing (v2.1) | COMPLETE |
| Dynamic marketplace (Phase 4) | COMPLETE |
| Family activation security | COMPLETE |
| Build-time key validation (Phase 5) | COMPLETE |
| In-App Configurator + Setup Wizards | COMPLETE |
| Google Workspace + Notion MCPs | COMPLETE |
| GitHub Actions CI/CD Pipeline | COMPLETE |
| iCloud folder pinning | COMPLETE |
| CLAUDE.md sync (Phase 6) | COMPLETE — ClaudeCodeConfigService deploys generic template to iCloud with symlink + stop hook |
| **Skills-over-MCP (replaces Phase 3)** | **IN PROGRESS** — Travel Itinerary is the pilot skill; long-term Weekly Rhythm migration waits on upstream MCP spec (~June 2026 per David Soria Parra talk). Original Skills-support Phase 3 PDF spec is superseded but kept at project folder for reference. |
| Family Memory (Phase 7) | COMPLETE — setup-claude-memory v1.5.0 deploys shared iCloud folder; Fort Abode v3.7.1 surfaces opt-in; v3.11.0 adds Family tab + Health dashboard |
| Future enhancements (Phase 8) | NOT STARTED |

## Family Activation
- Code validated against SHA-256 hash — plaintext never in binary
- Keychain: service `com.kamstudios.fortabodeutilitycentral`, account `family-activation`
- `KeychainService.deactivate()` available for testing

---

## Weekly Rhythm Engine — Handoff Protocol

**This section documents exactly how to ship a Weekly Rhythm Engine update through Fort Abode without missing steps.** Update it any time a new issue is discovered so the same mistake is never made twice.

### The Weekly Rhythm distribution chain

The Weekly Rhythm Engine is a Claude skill that lives in multiple places simultaneously. A full update touches **all of them**:

```
1. iCloud canonical (source of truth, edited during dev)
   ~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Weekly Flow/
     ├── dashboard-template.html      ← app-managed
     ├── engine-spec.md               ← app-managed
     └── {UserName}/                  ← user-owned, NEVER overwrite
         ├── config.md
         ├── memory.md
         └── dashboards/              ← generated output

2. iCloud sync copies (kept in sync with canonical)
   ~/.../Kennedy Family Docs/Weekly Flow/Kamren/dashboard-template.html
   ~/.../Kennedy Family Docs/Claude/Weekly Flow/dashboard-template.html
   ~/.../Kennedy Family Docs/Claude/Weekly Flow/engine-spec.md

3. Dropbox repo (source of truth for GitHub)
   ~/Library/CloudStorage/Dropbox-KamStudios,LLC/Aligned/Projects/Weekly Rythm/
     ├── SKILL.md                     ← thin wrapper
     ├── dashboard-template.html
     ├── engine-spec.md
     ├── CHANGELOG.md
     └── releases/{version}.md

4. GitHub repo: kamrenkennedy/weekly-rhythm (private)
   Pushed from the Dropbox repo above.

5. Fort Abode bundled skills (this repo)
   FortAbodeUtilityCentral/Resources/component-registry.json
   (or inline skill_manifest when sourcing from GitHub)

6. Installed skill path on each user's machine (managed by Fort Abode)
   ~/Library/Application Support/Claude/local-agent-mode-sessions/.../skills-plugin/.../skills/weekly-rhythm-engine/
```

### The handoff checklist (in order)

When a new Weekly Rhythm version is ready to ship, ALWAYS do all of these steps. Skipping any one has historically caused broken runs.

**Phase A — Verify the template**
1. Run `python3 /tmp/make-loc-preview.py` to regenerate the test fixture with all placeholders substituted. The script's final line reports `All placeholders substituted.` or `WARNING: Unsubstituted placeholders`. If any are unsubstituted, fix before proceeding.
2. Open the test fixture in a browser at a desktop viewport (1440×900 minimum) and click through every interactive element Kam cares about: day type dropdown, family message modal, travel itinerary edit, errand route selector, run health pill.
3. Take screenshots and get Kam's explicit approval BEFORE any shipping.

**Phase B — Sync the canonical files**
4. Sync dashboard-template.html from the iCloud canonical to ALL three sync locations:
   ```
   cp "~/.../Weekly Flow/dashboard-template.html" "~/.../Weekly Flow/Kamren/dashboard-template.html"
   cp "~/.../Weekly Flow/dashboard-template.html" "~/.../Claude/Weekly Flow/dashboard-template.html"
   cp "~/.../Weekly Flow/dashboard-template.html" "~/Dropbox/.../Weekly Rythm/dashboard-template.html"
   ```
5. Sync engine-spec.md from the Claude subfolder (which has the latest dev edits) to the non-Claude iCloud copy:
   ```
   cp "~/.../Claude/Weekly Flow/engine-spec.md" "~/.../Weekly Flow/engine-spec.md"
   ```
6. Verify SKILL.md (the thin wrapper) in the Dropbox repo matches the iCloud canonical if it was edited.
7. Bump `template_version:` in `Kamren/config.md` and any other per-user configs so the diagnostics system tracks the upgrade.

**Phase C — GitHub release**
8. `cd` to the weekly-rhythm repo (Dropbox folder).
9. Run `git status` to verify only expected files changed. **Check for any accidentally-committed secrets** — API keys, OAuth tokens, family config files. The `.gitignore` should cover these; if it doesn't, fix the gitignore FIRST and `git rm --cached` the leaked files.
10. Write or update `CHANGELOG.md` (Keep-a-Changelog format) with the new version.
11. Write `releases/{version}.md` (user-friendly release notes) — this is what Fort Abode reads for the "What's New" modal.
12. `git add CHANGELOG.md releases/{version}.md dashboard-template.html engine-spec.md SKILL.md`
13. `git commit -m "Release {version}: ..."`
14. `git push origin main`
15. `gh release create v{version} --title "v{version}" --notes-file releases/{version}.md`

**Phase D — Fort Abode bundle update**
16. If the skill's manifest (placeholders, setup prompts, API key requirements) changed, edit `FortAbodeUtilityCentral/Resources/component-registry.json` to match.
17. If the MCP requirements changed (e.g., Google Maps is now required), update the component entry's `mcp_requirements` or equivalent.
18. Bump Fort Abode's own version in `project.yml` (MARKETING_VERSION + CURRENT_PROJECT_VERSION) — this is separate from the Weekly Rhythm skill version.
19. `xcodegen generate`, archive, export, staple, zip, sign, update BOTH appcast.xml files (root + subdirectory).
20. Push, create GitHub release (see main Release Process above).

**Phase E — Verify the update lands**
21. On Kam's machine, open Fort Abode and trigger an update check. It should detect both the Weekly Rhythm skill version bump AND its own app update.
22. Install the update, then run the Weekly Rhythm Engine. Check the **Run Health pill** in the top-right of the dashboard:
    - Status should be `✓ All good` (if all MCPs healthy)
    - Versions section should show the NEW version numbers (not the old ones)
    - "Version drift detected" warning must NOT appear
23. Verify the update banner shows on first run after install.
24. Ask Kam to verify on his desktop machine before considering the release done.

### Common failure modes (fix log)

Update this list any time a new bug surfaces. The goal: never repeat the same mistake.

**[2026-06-18] Weekly Rhythm dashboards went silently stale for 22 days — the engine was never triggered**
- **Symptom**: Weekly Rhythm showed hardcoded April sample data ("doesn't even show today's date"). Newest dashboard on disk was `dashboard-2026-05-25.json` (generated 2026-05-27); no run had happened since.
- **Root cause**: Two compounding gaps, neither a CLI/auth failure (CLI healthy, OAuth token present). (1) The weekly Schedule was never turned on, so the `com.kamstudios.fortabodeutilitycentral.weekly-rhythm-engine` LaunchAgent was never installed — the only auto-trigger left was the foreground auto-run. (2) `WeeklyRhythmEngineStore.startObservingActivation()` deliberately skips the FIRST `didBecomeActive`, so a cold launch / Sparkle update relaunch never fires a stale-data run unless the user alt-tabs away and back. The app was opened ~once in 22 days (one of those was a Sparkle update relaunch, which logged two "falling back to mock" reads and zero `Runner.start`).
- **Fix**: Operational — turn the weekly Schedule ON (installs the LaunchAgent so runs fire even when the app is closed) + click Run for an immediate brief; refresh the OAuth token (unrotated since 2026-04-28). App-side (backlog P0-2/P1-3): call `runIfStaleOnForeground()` once on launch so a cold/Sparkle relaunch fires, and kick a silent `runNow()` when `FileBacked` hits mock-fallback while auto-run is enabled and `lastRunAt` is past threshold.
- **Prevention**: Dashboards must never depend solely on the user re-activating the app. Any auto-run path that gates on window activation needs a launch-time + data-staleness trigger as a backstop, and the weekly Schedule should be installed by default (or the user prompted to enable it). Also note: the engine run does not refresh the in-app view (stores are decoupled — backlog P1-1), so a fresh dashboard isn't visible until a tab/week switch or relaunch. Full audit: `docs/data-architecture-audit-2026-06-18.md`.

**[2026-04-28] Fort Abode resolver preferred legacy `Weekly Flow/` over canonical `Weekly Rhythm/`**
- **Symptom**: After a successful engine run, Fort Abode kept showing mock data with `WeeklyRhythm.FileBacked` logging "falling back to mock". Tiera's most recent engine output landed at `Weekly Rhythm/Tiera/dashboards/weekly-brief-2026-04-13.html` but the data source was scanning `Weekly Flow/Tiera/dashboards/`.
- **Root cause**: Weekly Rhythm engine v2.1.0 (2026-04-23) renamed the canonical iCloud folder from `Weekly Flow/` → `Weekly Rhythm/`, but the v2.1.0 cleanup that was supposed to delete the legacy folder never ran on Kam's Mac, so both folders still existed. `WeeklyRhythmPathResolver.ResolvedRoot.allCases` listed `weeklyFlow` first, so the resolver always picked the legacy folder when both existed.
- **Fix**: Reversed the enum case order in `WeeklyRhythmPathResolver.swift` — `weeklyRhythm` first, `weeklyFlow` as a legacy fallback. Updated the header comment.
- **Prevention**: When the upstream Weekly Rhythm engine renames a path, the corresponding Fort Abode resolver MUST be updated in the same coordinated release. This CLAUDE.md previously hardcoded "Weekly Flow is canonical" — that statement was already stale at v2.1.0 ship time but no one noticed because Fort Abode's resolver agreed with the (now wrong) doc. Source of truth for canonical name is the Weekly Rhythm engine's CHANGELOG, not the Fort Abode CLAUDE.md.

**[2026-04-13] Cowork used a stale bundled dashboard template**
- **Symptom**: Cowork-generated dashboard was missing Project Pulse, Weekly Triage, carousel — all Phase 3/5/6 features that were already in the iCloud template.
- **Root cause**: The skill in Cowork reads from `local-agent-mode-sessions/.../skills/weekly-rhythm-engine/` which had an old bundled copy of `dashboard-template.html`. The iCloud canonical had been updated but Cowork never saw the new version.
- **Fix**: Engine-spec Step 10b-ii added — Python template substitution reads `dashboard-template.html` directly from iCloud (not from the installed skill path), so Cowork always gets the latest.
- **Prevention**: Never bundle `dashboard-template.html` into the skill zip. The skill only needs `SKILL.md` + `engine-spec.md`. The template lives in iCloud and is updated separately via Fort Abode.

**[2026-04-13] Engine-spec version drift between `Claude/Weekly Flow/` and `Weekly Flow/` folders**
- **Symptom**: Today's fixes were applied to `Kennedy Family Docs/Claude/Weekly Flow/engine-spec.md` but the `Weekly Flow/engine-spec.md` was 100+ lines behind. Some runs may have read the stale copy depending on path resolution.
- **Root cause**: Two iCloud copies with no automatic sync. Dev edits went to one but not the other.
- **Fix**: Phase B Step 5 in the handoff checklist always syncs both.
- **Prevention**: When editing engine-spec.md, always `cp` to both iCloud locations immediately. Better yet: consolidate to a single canonical path and symlink the other.

**[2026-04-13] `{{FAMILY_PARTNERS_JSON}}` placeholder appeared in a code comment and failed the preview substitution check**
- **Symptom**: The preview generator's "all placeholders substituted" check failed because a code comment mentioned `{{FAMILY_PARTNERS_JSON}}` as a TODO reference, and the regex picked it up.
- **Root cause**: Using `{{...}}` syntax anywhere in the template (even in comments) triggers the substitution check.
- **Fix**: Removed the comment reference.
- **Prevention**: Never use `{{...}}` syntax in comments. Use `<< ... >>` or `__...__` for comment markers.

**[2026-04-13] `last_run` timestamp lost when config.md was not writable in Cowork sandbox**
- **Symptom**: Cowork sandbox couldn't write to iCloud config.md, so subsequent Gmail pulls used the wrong window (defaulted to 7 days).
- **Root cause**: config.md was the only persistence target.
- **Fix**: Step 11a expanded — `last_run` is also written to Memory MCP (`Weekly_Rhythm_Config` entity) as a fallback. Next run checks BOTH and uses the most recent.
- **Prevention**: Any persistent state the engine needs across runs should have a Memory MCP fallback, not just file-based storage.

### Handoff non-negotiables

Never ship a Weekly Rhythm update without:
- [ ] Running the preview generator and confirming all placeholders substituted
- [ ] Kam's explicit visual approval via screenshots or a live preview walkthrough
- [ ] All four sync locations updated (canonical iCloud, Kamren/, Claude/Weekly Flow/, Dropbox repo)
- [ ] CHANGELOG.md and releases/{version}.md in the GitHub repo
- [ ] `git log` verified — no API keys or secrets committed
- [ ] Fort Abode bundle version bumped in `project.yml`
- [ ] BOTH appcast.xml files updated (root + subdirectory)
- [ ] First-run verification on Kam's machine: Run Health pill shows new version, update banner displays, no version drift warnings

### When in doubt

If anything about the handoff is ambiguous, **ask Kam first** rather than guessing. The cost of pausing to confirm is low; the cost of shipping a broken update to his desktop Mac (or worse, Tiera's Cowork session) is high.

### Always update this section

**Any time you discover a new bug, add it to the "Common failure modes" list above with symptom, root cause, fix, and prevention.** Any time you change the handoff process (new step, changed order, new tool), update the checklist above. This file is the only thing keeping future Claude sessions from repeating the same mistakes.
