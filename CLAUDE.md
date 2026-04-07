# CLAUDE.md — Fort Abode Utility Central

## Project Overview

Native macOS SwiftUI app that manages Kam's Claude infrastructure — MCP servers, skills, and auto-updates. Built for the Kennedy family (Kam + Tiera). Currently v2.2.0 (build 9).

- **Bundle ID**: `com.kamstudios.fortabodeutilitycentral`
- **GitHub**: `kamrenkennedy/FortAbodeUtilityCentral` (public)
- **Stack**: SwiftUI, Swift 6, macOS 14+, non-sandboxed, hardened runtime
- **Signing**: Developer ID Application, team X6LBF9H7M5, manual signing
- **Updates**: Sparkle 2 (EdDSA signed)
- **Project generation**: xcodegen (`/opt/homebrew/bin/xcodegen`)

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

## Release Process

1. Edit `project.yml` — bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`
2. `/opt/homebrew/bin/xcodegen generate`
3. Xcode → Product → Archive → Distribute App → Direct Distribution → Export
4. `xcrun stapler staple "Fort Abode Utility Central.app"` (BEFORE zipping)
5. `cd build && ditto -c -k --keepParent "Fort Abode Utility Central.app" ../FortAbodeUtilityCentral/FortAbodeUtilityCentral-vX.Y.Z.zip`
6. Sign: `sign_update FortAbodeUtilityCentral-vX.Y.Z.zip` (outputs EdDSA signature + length)
7. Update **BOTH** `appcast.xml` files with new `<item>` entry (signature + length from step 6)
8. `git add && git commit && git push`
9. `gh release create vX.Y.Z FortAbodeUtilityCentral-vX.Y.Z.zip --title "vX.Y.Z" --notes "..."`

### Tool Locations
- **xcodegen**: `/opt/homebrew/bin/xcodegen`
- **sign_update**: `~/Library/Developer/Xcode/DerivedData/FortAbodeUtilityCentral-eofptxlehvthkkfvdivcdfxbejpc/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`
- **generate_keys**: same directory as sign_update

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
| **CLAUDE.md sync (Phase 6)** | **IN PROGRESS** |
| Skills support (Phase 3) | FULLY SPECCED, TABLED — PDF spec at project folder |
| Family Memory (Phase 7) | CONCEPT — shared iCloud memory for family communication |
| Future enhancements (Phase 8) | NOT STARTED |

## Family Activation
- Code validated against SHA-256 hash — plaintext never in binary
- Keychain: service `com.kamstudios.fortabodeutilitycentral`, account `family-activation`
- `KeychainService.deactivate()` available for testing
