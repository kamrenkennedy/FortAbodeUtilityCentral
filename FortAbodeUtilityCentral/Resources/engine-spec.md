<!-- Engine Spec v2.2.0 — Managed by Fort Abode — Updates to this file are picked up on next skill run -->

# Weekly Rhythm Engine

The strategic engine for Kam's life — work and personal. Sets up the full week ahead every Friday. Also runs on-demand whenever something changes mid-week.

The daily brief is a separate skill — this skill handles the weekly rhythm only.

## Required Connections

### Core (engine won't run without these)
- Google Calendar (MCP) — ALL calendars, including personal and family
- Gmail (MCP) — email scanning since last run
- Apple Reminders (MCP) — task sync, errand tracking
- Notion (MCP) — Execution OS / Command Center databases (Projects, Tasks, Inbox, Areas)
- Memory MCP — cross-session context, triage history, active project snapshots

### Optional (engine degrades gracefully without these)
- iMessages (MCP) — context enrichment from text conversations. **Requires Full Disk Access** on macOS.
- Deep Context (MCP) — session persistence across machines
- Google Maps (MCP) — Phase 7 location intelligence (commute times, errand routing, lunch planning)
- Apple Notes (MCP) — travel itinerary output
- File system access — for reading/writing config, memory, and template files

## Planning Hierarchy

```
Yearly    → Are we on track for the big picture?
Quarterly → How are the last 3 months stacking up?
Monthly   → What happened across the last 4 weeks?
Weekly    → THE ENGINE — plans the week, drives everything below
```

## File Structure

```
[iCloud path]/                          ← Created by Fort Abode or manually
├── config.md                           ← User-owned. Never overwritten by updates.
├── memory.md                           ← User-owned. Never overwritten.
├── dashboard-template.html             ← App-managed. Updated by Fort Abode on new versions.
└── weekly-brief-YYYY-MM-DD.html        ← Generated dashboards. User-owned.
```

**Default iCloud path:** `~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Weekly Rhythm/{UserName}`

When Fort Abode is installed, it creates this folder automatically and copies the latest `dashboard-template.html` into it. The skill reads from whatever `icloud_path` is set in `config.md`.

**Update rules:**
- `dashboard-template.html` — app-managed, overwritten by Fort Abode when a new version ships
- `config.md` — user-owned, NEVER overwritten. New fields added in updates are detected as missing by Step 2b and the user is prompted to fill them in.
- `memory.md` — user-owned, NEVER overwritten
- `weekly-brief-*.html` — generated output, user-owned

---

## Step 1 — Identify User and Detect Setup State

### Step 1a — Find iCloud folder

Check the standard iCloud path for a Weekly Rhythm folder:

```
Glob: ~/Library/Mobile Documents/com~apple~CloudDocs/*/Weekly Rhythm/*/config.md
```

- **If found** → load the first match's `config.md`, read the `icloud_path` and `name` from it
- **If not found** → check if the folder exists without a config (Fort Abode may have created it):
  ```
  Glob: ~/Library/Mobile Documents/com~apple~CloudDocs/*/Weekly Rhythm/*/
  ```
  - **Folder exists, no config** → go to Step 2 (questionnaire, skip path question — folder is ready)
  - **No folder at all** → go to Step 2 (full questionnaire including path)

### Step 1a-ii — Environment detection (Cowork / sandbox)

If the iCloud Glob in Step 1a returns no results, check whether you're in a Cowork sandbox:

- **Detection:** Working directory starts with `/sessions/` or skill loaded from a path containing `/mnt/.claude/skills/`
- **Do NOT fall back to any bundled config directory** (`kam/`, `{skill_root}/kam/`, or any config file found in the skill's own directory tree). These are development artifacts with placeholder data — using them produces incorrect output.
- **Request folder access:** Ask the user to select their Weekly Rhythm folder in iCloud. The path will be:
  `~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Weekly Rhythm`
  Tell the user: "I need access to your Weekly Rhythm folder in iCloud to load your config and save your dashboard. Please select it when prompted."
- Once the folder is mounted, re-run the Step 1a Glob against the mounted path to find `config.md`
- **If folder access is denied or unavailable:** Stop and explain that the engine needs iCloud access to run.
- **Automated/scheduled runs (no user present):** Emit an error and stop — folder access requires user interaction.

### Step 1b — Config completeness check

If `config.md` was found, score each section for completeness:

| Section | Required fields | Missing action |
|---------|----------------|----------------|
| Identity | `name`, `role`, `location` | Ask |
| Schedule | `run_schedule`, `week_starts_on`, Day Types | Ask |
| Reminders | `reminders_lists` with at least 1 mapping | Scan Apple Reminders + ask |
| Calendars | `calendars` with at least 1 Include | Scan Google Calendar + ask |
| Goals | At least 1 Work or Personal goal | Ask |
| Notion | `notion_databases` with `projects` + `tasks` IDs | Search Notion (Step 2d) |
| Triage | `overdue_threshold_days`, `fusion_enabled` | Use defaults |
| Location | `home_address` | Ask |
| Lunch | `lunch_preferences` | Ask or skip |

**If ALL sections complete:**
> "Your config looks good — ready to plan your week?"
> → Proceed to Step 3

**If SOME sections missing:**
> "I found your config but a few things need filling in: [list missing sections]. Want to set those up now or run with defaults?"
> → Ask only about missing sections, skip everything else

**If config exists but is mostly empty (blank template from Fort Abode):**
> → Run full questionnaire (Step 2), but skip path question since folder exists

### Step 1c — Determine run mode

From the user's prompt:

| Mode | When | What it does |
|------|------|-------------|
| **Weekly Planning** | Friday, or "set up my week" | Plans the full coming Sun–Sat |
| **Mid-Week Update** | Manual trigger after a change | Re-pulls inputs, shows what changed |
| **Shuffle** | "Move X to Thursday" | Proposes rearrangement, confirms before applying |
| **Rollup** | "How's my month/quarter going" | Summarizes weeks against goals |

### Step 1d — Version Check and Update Banner

After loading config (Step 1a/1b) and determining run mode (Step 1c), compare versions to detect a fresh install or upgrade and emit `UPDATE_BANNER_JSON` for the dashboard.

1. Read `last_seen_version:` from `config.md` (may be missing on first run after install).
2. Compare to the engine spec's current version (parse from the `<!-- Engine Spec vX.Y.Z -->` header on line 1 of this file).
3. **If `last_seen_version` is missing or older than the current version** → set `show_update_banner = true` and load release notes:
   - Try `{icloud_path}/../releases/{new_version}.md` first (Fort-Abode-managed iCloud copy)
   - Fall back to the bundled skill directory: `{skill_root}/releases/{new_version}.md`
   - If neither exists, use a one-line summary: `"Updated to v{new_version}"`
4. **Otherwise** → set `show_update_banner = false`.
5. Build `UPDATE_BANNER_JSON`:
   ```json
   {
     "version": "2.0.0",
     "title": "Updated to 2.0.0 — Location Intelligence & Family Sync",
     "summary": "First line of release notes",
     "notes": "Full markdown body of releases/{version}.md",
     "dismissed": false
   }
   ```
   If `show_update_banner = false`, set `UPDATE_BANNER_JSON = null` (the dashboard skips the banner entirely).
6. **After the dashboard renders successfully** (Step 10b complete), update `last_seen_version` in BOTH `config.md` AND Memory MCP fallback (`Weekly_Rhythm_Config` entity, fact: `last_seen_version: 2.0.0`) so the banner doesn't re-fire next run.

The dashboard's update banner has localStorage-based dismissal — if the user clicks "Dismiss" before next run, the banner won't reappear for that browser even if `last_seen_version` is stale. The release-notes modal is always reachable via the Run Health pill diagnostics.

---

## Step 2 — Setup (new users or incomplete config)

### Step 2a — MCP Health Check

Before asking the user anything, silently probe each MCP connection:

| Connection | Probe call | Required? |
|------------|-----------|-----------|
| Google Calendar | `gcal_list_calendars` | Core |
| Gmail | `gmail_get_profile` | Core |
| Apple Reminders | `list_reminders(list_name: "Inbox")` | Core |
| Notion | `notion-search(query: "test", page_size: 1)` | Core |
| Memory MCP | `aim_memory_list_stores` | Core |
| iMessages | `search_messages(query: "test", limit: 1)` | Optional |
| Google Maps | `maps_geocode(address: "test")` | Optional |
| Apple Notes | `list_notes` | Optional |

**Report results:**
> "Connections: 5 of 5 core ready ✓. Optional: iMessages needs Full Disk Access, Google Maps not connected."

If **any core connection is missing**, warn the user:
> "These are needed to run the engine: [list]. The engine can still run but will skip those sources. Want help setting them up?"

If **only optional connections are missing**, just note it and proceed.

### Step 2b — Questionnaire (only for missing sections)

Run conversationally — one or two questions at a time. **Only ask about sections flagged as missing in Step 1b.** Skip sections that already have data in config.

**Full question set (for brand-new users):**

1. **Path** (only if no iCloud folder found):
   > "Where should I store your Weekly Rhythm files? Ideally in iCloud so it works on every device. Tell me your username and I'll suggest the path."

2. **Identity:**
   > "What's your name? What do you do for work?"

3. **Schedule:**
   > "Walk me through your ideal week — what days are for what? What times are you sharpest? Any days completely off-limits?"

4. **Goals:**
   > "What are you working toward — at work? In your personal life?"

5. **Priorities:**
   > "Who or what always comes first — at work? At home?"

6. **Errands:**
   > "How do you handle errands — batch day or fill gaps?"

7. **Reminders mapping** (auto-scan first):
   > Pull all Apple Reminders lists → show them → "Which are Work, Personal, Errands, or should I exclude?"

8. **Calendar mapping** (auto-scan first):
   > Pull all Google Calendars → show them → "Which to Include, Exclude, or Reference-only? Default: include ALL."

9. **Location:**
   > "What's your home address? This helps with commute estimates and errand routing."

10. **Lunch preferences:**
    > "Any food preferences or diet restrictions? Favorite types of cuisine? This helps if you want lunch suggestions during busy days."

11. **Family Sync (v2.0.0+):**
    > "Do you want to share weekly context with a family member? This enables a shared message board, travel itinerary sync, and cross-user awareness. Each partner needs their own Weekly Rhythm folder."
    - If **yes** → ask: "Who's your partner, and where's their Weekly Rhythm folder? (e.g., Tiera at `~/.../Kennedy Family Docs/Weekly Rhythm/Tiera`)"
      - Persist as `family_sync_enabled: true`, `family_partners: [{name, icloud_path}]`, `message_auto_archive_days: 30`
    - If **no** → persist `family_sync_enabled: false`, omit `family_partners`
    - **Never copy a partner's config wholesale** — each user's identity, day types, goals, and lunch prefs must be answered fresh in their own setup run. Family Sync only shares the message board + travel itineraries, not the rest of the config.

12. **Diagnostics (v2.0.0+):**
    > "Want me to write a run report after each weekly rhythm run? It tracks MCP health, version drift, and any errors. Reports go to `{icloud_path}/diagnostics/runs/` and are visible in the dashboard's Run Health pill."
    - Default **yes** unless the user opts out
    - Persist as `diagnostics_enabled: true` (or `false`)

### Step 2c — Notion Command Center Detection

Search for an existing Command Center in Notion:

```
notion-search: query="Command Center"
```

- **Found** → pull database IDs (Projects, Tasks, Inbox, Areas) automatically, save to config
- **Not found** → offer to duplicate:
  > "You don't have a Command Center in Notion yet. Want me to duplicate the template into your workspace? This sets up Projects, Tasks, Inbox, and Areas databases."
  > - If yes → duplicate from template, save new database IDs to config
  > - If no → skip Notion integration (engine runs without it, uses calendar/reminders only)

### Step 2d — Generate and save config

After gathering all answers:
1. Generate `config.md` from answers + auto-scanned data
2. Generate blank `memory.md` with section headers
3. **Show the generated config before saving** — let user review
4. **Confirm before writing** — never write without explicit yes
5. Write files to `{icloud_path}/`
6. Create the user subdirectories: `{icloud_path}/dashboards/`, `{icloud_path}/messages/inbox/`, `{icloud_path}/messages/sent/`, `{icloud_path}/diagnostics/runs/` (the last two only if `family_sync_enabled` / `diagnostics_enabled` are true respectively)
7. Offer to schedule a Friday run

**v2.0.0+ required fields** — every newly-generated config MUST include:

```yaml
## System
template_version: 2.0.0          # auto-set by engine to current spec version
last_seen_version: 2.0.0         # auto-set on first run; bumps after dashboard renders
fort_abode_managed: true         # tells Fort Abode this config is upgrade-eligible

## Family Sync (v2.0.0+)
family_sync_enabled: {true|false}
family_partners:                 # only present if enabled
  - name: {Partner Name}
    icloud_path: {absolute path}
message_auto_archive_days: 30    # only present if enabled

## Diagnostics (v2.0.0+)
diagnostics_enabled: {true|false}

## Day Types (v2.0.0+, see Step 2e)
day_types:
  - id: {slug}
    label: {display name}
    color: "{hex}"
    exclusive: {true|false}
  ...
```

If any of these fields are missing on an existing config (e.g., user upgraded from 1.7.0), the engine fills them in from defaults during Step 1b's incremental setup pass — never silently skip.

> **Multi-user note:** Each person gets their own iCloud path with their own files. Memory MCP routing is handled at the MCP level — the skill calls Memory MCP tools directly and they route to whoever's MCP is connected. **Never copy one user's config to another** — always run Step 2 fresh for each new user. Names, day types, goals, lunch prefs, and identity must all be personalized.

### Step 2e — Day Types Setup

The dashboard supports a structured day-type editor with replace-or-add semantics and an exclusive `Off` type. Day types must be persisted to `config.md` as structured data — not just free-text answers in the schedule question.

**On first-run setup** (or when `day_types:` is missing from config), seed from the dashboard's hardcoded `DAY_TYPE_COLORS` map and walk the user through customization:

1. Present the default day type set:
   - `Creative` (#b8611a) — deep creative work
   - `Business Dev` (#2e6090) — pitches, calls, outreach
   - `Admin` (#6a3e98) — taxes, invoices, paperwork
   - `Personal` (#3a7a50) — non-work commitments
   - `Shoot Day` (#9e3020) — production days
   - `Content Day` (#8a6800) — capture/edit days
   - `Travel` (#1878a0) — travel mode
   - `Edit Day` (#5a6e7a) — post-production
   - `Off` (#555) — protected, exclusive

2. Ask: "Want to keep these, rename any, or add your own?"

3. Persist as a structured array under `day_types:` in config.md:
   ```yaml
   day_types:
     - id: creative
       label: Creative
       color: "#b8611a"
       exclusive: false
     - id: off
       label: Off
       color: "#555"
       exclusive: true
   ```

4. Emit `DAY_TYPES_JSON` placeholder (array of `{id, label, color, exclusive}` objects) for the dashboard's day-type dropdown UI.

**On subsequent runs**, read `day_types:` directly from config and emit unchanged. The user can edit them via the dashboard dropdown UI; on next paste-back, persist the changes back to config.

**Exclusive flag:** When `exclusive: true` (e.g., Off), selecting that type for a day removes all other types. Other types can stack additively (a day can be both Creative and Personal).

**Replace vs Add:** The dashboard dropdown defaults to "replace" semantics — picking a new type replaces whatever was there. A modifier key (or a checkbox) toggles "add" mode for stacking. Engine doesn't enforce this — it just persists whatever the user selected.

---

## Step 3 — Load Context

Read all three files using the Read tool, from the `icloud_path` in config:

```
Read: {icloud_path}/config.md
Read: {icloud_path}/memory.md
```

Parse from config:
- `name`, `icloud_path`, `run_schedule`, `last_run`, `gmail_window`, `week_starts_on`
- `Day Types` (Sun–Sat mapping)
- `protection_keywords`, `errand_nudge_threshold`
- `reminders_lists` mappings, `calendars` mappings
- `Goals` (Work + Personal)
- `memory_mcp`, `on_track_behavior`, `bible_translation`
- `home_address`, `rb_address` (Phase 7 — location intelligence)
- `lunch_preferences` (Phase 7 — style, likes, avoids, cheat_meals_ok, price_range, default_duration)
- `template_version`, `fort_abode_managed` (system fields)

Parse from memory:
- Recent history, upcoming milestones, learned patterns, evergreen notes

---

## Step 4 — Detect Protected Days

**Step 4a — Calendar check (priority):** Any all-day event today matching protection keywords (defaults: Personal Day, Day Off, Vacation, OOO, Holiday, Off, Rest).

**Step 4b — Config fallback:** If today maps to "Personal" in the day type schedule.

**If protected:** Pull Reminders only. Show tasks due today + overdue. Suppress everything else.

---

## Step 4c — Drain Pending Mutations

When the user edits state in Fort Abode (v4.x and later) — drag-reschedules an event, marks an errand done, accepts a proposal, RSVPs to an invite, edits a triage entry — the app captures each change as a JSON mutation entry in a sibling file alongside the engine's dashboard output:

```
{icloud_path}/dashboards/dashboard-{ISODate}.json           ← engine-emitted (existing)
{icloud_path}/dashboards/dashboard-{ISODate}-pending.json   ← app-emitted (new in v2.2.0)
```

The pending file accumulates user mutations until the engine drains it. Fort Abode handles optimistic UI and replay-on-load locally, but the actual side-effects on Apple Reminders, Google Calendar, Memory MCP, and Notion only happen when this step runs.

**This step must run before Step 5** so subsequent input pulls read the post-edit state of every source-of-truth.

### Pending file shape

```json
{
  "schemaVersion": 1,
  "weekISODate": "2026-04-21",
  "createdAt": "2026-04-26T14:30:12Z",
  "mutations": [
    {
      "id": "8C6D2E3A-...",
      "appliedAt": "2026-04-26T14:30:12Z",
      "mutation": {
        "kind": "errandDoneToggle",
        "errandID": "err-amazon",
        "isDone": true
      }
    }
  ]
}
```

- `schemaVersion` — currently `1`. If unknown, the engine logs a warning and skips the file (does NOT rename or drain).
- `weekISODate` — the Monday of the target week (matches the sibling `dashboard-{ISODate}.json`).
- `createdAt` — when the file was first written. Used to sort multiple pending files in order.
- `mutations[]` — append-only ordered list. Each entry has a stable UUID `id`, `appliedAt` timestamp, and a `mutation` payload tagged with `kind`.

### Drain protocol

1. **Glob** for `{icloud_path}/dashboards/dashboard-*-pending.json`. Exclude any path matching `*-pending.applied-*.json` — those are already-drained audit copies.
2. **Sort** matched files by `createdAt` ascending so older intent applies first.
3. **For each file:**
   1. Read and decode as JSON.
   2. If `schemaVersion` is unknown (anything other than `1`): log `[drain] file={name} schemaVersion={n} unknown, skipped` and move on. Do NOT rename — leave it for a future engine version that knows how to parse it.
   3. **For each mutation entry**, dispatch by `mutation.kind` per the table below. Per-entry failures are logged with the entry's `id` and the engine continues with the next entry — never abort the whole drain on one bad mutation.
   4. **On full-file processing complete** (every entry either applied or individually logged as failed): rename the file atomically to `dashboard-{ISODate}-pending.applied-{ISO_TIMESTAMP}.json` (e.g. `dashboard-2026-04-21-pending.applied-2026-04-26T08-02-15.json`). Do NOT delete — the rename leaves a 30-day audit breadcrumb that helps diagnose state drift. `mv` on the same filesystem is atomic on macOS.
4. Continue with Step 5 (Pull Inputs). The engine now reads the updated source-of-truth.

### Mutation kinds

#### `errandDoneToggle`

```json
{ "kind": "errandDoneToggle", "errandID": "err-amazon", "isDone": true }
```

**Action:** Apple Reminders MCP. Locate the matching Reminder by `errandID` (or by title-prefix match if the dashboard's emitted ID space differs from the engine's internal IDs). Mark complete (`isDone: true`) or un-complete (`isDone: false`).

#### `eventMove`

```json
{
  "kind": "eventMove",
  "eventID": "ev-thu-braxton3",
  "newDayIndex": 4,
  "newStartHour": 14.0,
  "newEndHour": 16.0
}
```

**Action:** Google Calendar MCP — `gcal_update_event`. Compute the new ISO start/end:
- Anchor to the week's Monday (from `weekISODate`).
- Add `newDayIndex` days (0 = Monday, 6 = Sunday — must match the engine's emitted `weekDays` array order).
- `newStartHour * 60` minutes = offset within the day (e.g. `14.0` → 14:00, `14.5` → 14:30).
- Same for `newEndHour`.

#### `eventEdit`

```json
{
  "kind": "eventEdit",
  "eventID": "ev-thu-braxton3",
  "patch": {
    "title": "Braxton edit · pass 3 (revised)",
    "dayOfWeek": "Friday",
    "typeTag": "Make",
    "startTime": "10:00 AM",
    "duration": "3 hours",
    "notes": "Move to Friday — Tuesday is over-booked."
  }
}
```

All `patch` fields are optional — only fields the user changed are present. Per-field actions:

- **`dayOfWeek` + `startTime` + `duration`**: parse to ISO start/end and `gcal_update_event`. Patterns:
  - Time: `^(\d+):(\d+)\s+(AM|PM)$` (e.g. `"10:00 AM"` → 10.0, `"2:30 PM"` → 14.5)
  - Duration: `^(\d+(?:\.\d+)?)\s+(hours?|min)$` (e.g. `"3 hours"` → 3.0, `"30 min"` → 0.5, `"1.5 hours"` → 1.5)
- **`title`**: `gcal_update_event` with new summary.
- **`notes`**: `gcal_update_event` with notes appended to event description.
- **`typeTag`**: NO GCal action. Type tags are engine state — reflected on the next dashboard generation by re-categorizing the event during render.

#### `reminderEdit`

```json
{
  "kind": "reminderEdit",
  "reminderID": "rem-amazon-return",
  "patch": {
    "title": "Return Amazon package — moved to Tuesday",
    "dueDay": "Tuesday",
    "list": "Errands",
    "tag": "Move",
    "notes": "Drop off after the gallery delivery."
  }
}
```

**Action:** Apple Reminders MCP — `update_reminder` with the matching ID. Apply per patch:
- `title` → reminder title
- `dueDay` → due date (parse `"Tuesday"` etc. relative to the current week's Monday)
- `list` → list move
- `notes` → reminder notes
- `tag` → engine state, no Reminders state change

#### `triageEdit`

```json
{
  "kind": "triageEdit",
  "triageID": "tri-marisol",
  "patch": {
    "followUp": "Tomorrow morning",
    "dismissReason": "Resolved via Slack thread",
    "disposition": "dismiss"
  }
}
```

**Action:**
- `disposition: "dismiss"` → write a `Triage_History` fact in Memory MCP (same dedup mechanism as Step 11b-ii — the item won't re-surface on next run). Format: `[YYYY-MM-DD] Dismissed: '{title}' — {dismissReason or "no reason given"}`.
- `disposition: "snooze"` → write a `Triage_Snooze` fact in Memory MCP with the resurface timestamp parsed from `followUp`. Step 5 should consult this entity and skip snoozed items until the resurface time has passed.
- `disposition: "reply"` → leave the item in triage but tag with the user's intent for the next run's display. Store as a `Triage_Intent` fact.

#### `triageRsvp`

```json
{ "kind": "triageRsvp", "triageID": "tri-team-sync", "response": "accept" }
```

`response` is one of `"accept" | "tentative" | "decline" | "cleared"`.

**Action:** Locate the underlying Google Calendar invite via the triage item's `pending_invite` linkage (engine state — when emitting `pending_invite` triage items, the engine records which calendar event ID the invite came from). Then call `gcal_respond_to_event`:
- `accept` → `accepted`
- `tentative` → `tentative`
- `decline` → `declined`
- `cleared` → revert to `needsAction` if the API allows it; otherwise no-op + log

#### `errandEdit`

```json
{
  "kind": "errandEdit",
  "errandID": "err-amazon",
  "patch": {
    "title": "Return Amazon package",
    "location": "Downtown · 12 min",
    "routedTo": "Monday",
    "notes": "After morning run.",
    "isDone": false
  }
}
```

**Action:** Apple Reminders MCP — `update_reminder` for title / list / due-date / completion state. `routedTo` is engine state and reflects on the next dashboard generation's errand routing — not a Reminders state change. `location` and `notes` go into the Reminders entry's notes field.

#### `proposalAccept` / `proposalDecline`

```json
{ "kind": "proposalAccept", "proposalID": "prop-move-sync" }
```

**Action:**
- For BOTH: write a calibration fact to Memory MCP under `Family_Message_Calibration` (same shape as Step 11d) so future runs weight similar proposals. Format: `[YYYY-MM-DD] {accepted|declined}: '{proposal title}' — {reason if any}`.
- For `proposalAccept`: also execute the side-effect described in the proposal's `proposedBlock` (per Step 10c) — typically a `notion-update-page` call for a Notion task update, or a `gcal_create_event` call for a calendar block creation. Match the action to the proposal's `actionKind`.
- For `proposalDecline`: just record the decision in Memory MCP, no side-effect.

#### `dayTypeChange` and `errandReorder` — should NOT appear in pending file

These mutation kinds are routed by the app to other destinations and should never reach the pending file:

- `dayTypeChange` → Fort Abode writes directly to `{icloud_path}/config.md` under the `## Day Types` section. The engine reads config on every run, so changes apply automatically with no drain action.
- `errandReorder` → app-local UI sort order at `~/Library/Application Support/FortAbodeUtilityCentral/weekly-rhythm-ui-state.json`. Pure UX state — never crosses the iCloud boundary.

If either kind appears in a pending file (defensive case — app bug or hand-crafted file), log `[drain] mutation={kind} id={id} unexpected — should not be in pending file, skipped` and skip the entry. Do NOT fail the whole file.

### Idempotency and safety

The protocol is naturally idempotent so retries are safe:

- Apple Reminders mark-complete on an already-complete reminder is a no-op.
- `gcal_update_event` to the same target time/title is a no-op.
- Memory MCP fact insertion deduplicates on entity + content.
- `gcal_respond_to_event` to the user's existing response is a no-op.

If the engine drains a file but crashes before the rename, the next run reads the same file and re-applies — no state corruption. If the rename succeeds but a per-entry action failed earlier, the failure is logged with the entry's `id` (one log line per failed entry — that's the audit). The engine does NOT retry per-entry failures across runs — the user can manually re-edit if needed.

**Atomicity:** Fort Abode writes pending files via `Data.write(.atomic)` (under-the-hood `.tmp` + rename), so the engine never reads a half-written file. The engine's rename is also atomic on the same filesystem.

### Logging

Every drain action emits a structured log entry. These flow into the Step 13 Run Report and surface in the dashboard's Run Health detail modal.

Format:

```
[drain] mutation={kind} id={id} applied
[drain] mutation={kind} id={id} failed: {error}
[drain] file={name} drained ok, renamed to *-pending.applied-{ISO}.json
[drain] file={name} schemaVersion={n} unknown, skipped
[drain] mutation={kind} id={id} unexpected — should not be in pending file, skipped
```

### Required MCPs for this step

- File system access to `{icloud_path}/dashboards/`
- Apple Reminders MCP (errand toggles, reminder edits, errand edits)
- Google Calendar MCP (event moves/edits, RSVP responses)
- Memory MCP (proposal calibration, triage dismissals/snoozes, triage intent)
- Notion MCP (proposal acceptance side-effects when the proposed block is a task update)

If any required MCP is unavailable when an entry needs it, log the failure for that entry with the MCP name and continue. The file stays in place for retry on the next run when the MCP is back.

### Graceful degradation

- **No pending file present:** silently skip this step. Almost every run on a single-Mac setup will have nothing to drain — Fort Abode only writes a pending file when the user has actually edited something.
- **Pending file present but empty mutations array:** rename to `applied` immediately (no work to do, just close out the file).
- **Folder access denied (Cowork sandbox):** if Step 1a-ii has already mounted folder access, this step works the same way. If folder access is unavailable, log `[drain] folder access unavailable, skipped` and continue — Fort Abode-side mutations will accumulate until the next run with full access.

---

## Step 5 — Pull Inputs

Pull from all sources in parallel.

### Google Calendar — ALL Calendars, Read Deeply

**Include ALL connected calendars by default** — work, personal, family, shared — unless explicitly marked Exclude in config. The family calendar is not optional; it's part of the rhythm.

Pull a **30-day window** starting from the week's Sunday (on Friday runs) or from today (on update runs). This powers the multi-view dashboard: primary week, following week, and 30-day overview.

The primary planning week is still the first 7 days (Sun–Sat), but events for the full 30-day window are included in `EXISTING_EVENTS_JSON` so the dashboard can display them in the "Week After" and "30 Days" views.

For every event extract and use:
- **Title** — full title, emoji prefixes, client shorthand (check memory for known shorthands)
- **Description/notes** — read fully. Prep needed? Contacts? This changes what the event demands.
- **Location** — on-site vs remote, travel implications
- **Duration** — affects what can be scheduled around it
- **Which calendar** — signals work vs personal vs family
- **Attendees** — hard commitment vs flexible solo block
- **Recurring vs one-time** — recurring = baseline rhythm
- **All-day events** — classify carefully:
  - Protection keywords → protected day
  - Release/launch days → milestone (apply Milestone Context below)
  - Shoot/content days → major work commitment
  - Travel → affects logistics all day
  - Birthdays/anniversaries → surface in PERSONAL
  - Deadline markers → surface in upcoming
- **Event color** — use color-to-category mapping from config if set

### Apple Reminders — Read Deeply

#### 5a — List Discovery and Reconciliation

Before reading any reminders, reconcile config against Apple Reminders reality:

1. Read all mapped list names from `reminders_lists` in config.
2. For each config entry with `auto_create: true` where the list does NOT exist in Apple Reminders, collect into a `missingLists` array.
3. If `missingLists` is not empty, present a single consent prompt: "These Apple Reminders lists from your config don't exist yet: [list names]. Create them now?"
   - On yes → call `create_reminder` with each list name (the MCP auto-creates the list if it doesn't exist)
   - On no → skip those lists for this run, note the skip in the brief
4. For any existing Apple Reminders list NOT in config → log a brief warning: "Apple Reminders list '[name]' exists but isn't mapped in config — consider adding it."

#### 5b — Read All Mapped Lists

For every mapped list that exists, extract per reminder:
- **List name** — primary classification signal (use list-to-category mapping from config)
- **Due date** — no due date = time-flexible errand
- **Notes/description** — read fully; context changes urgency
- **Priority flag** — maps to urgency
- **Tags** — use for category refinement
- **Subtasks** — factor into time estimation
- **Completion status** — surface incomplete only; note recently completed in memory

Collect: tasks due this week, overdue (clearly marked), time-flexible pool (errands).

#### 5c — Inbox Triage (Triage-category lists only)

For each incomplete item in a list mapped to category `Triage` (e.g., Inbox), classify into one of these routes:

| Route | Criteria | Engine Action |
|-------|----------|---------------|
| `notion_task` | Describes project work, references a known project/client, or involves multi-step deliverables | Propose creating a Task in the Notion Tasks DB, linked to the relevant Project |
| `move_to_list` | Simple single-step reminder with a clear category match | Propose moving to the appropriate list via `update_reminder(new_list_name)` |
| `errand` | Physical errand, shopping, or location-dependent task | Propose moving to Errands list |
| `keep_inbox` | Ambiguous, needs more context, or user should decide | Leave in Inbox, surface in dashboard with a "needs triage" flag |
| `complete` | Already done or no longer relevant | Propose completing the reminder |

**Classification signals:**
- Match title/notes against known Notion project names and client names (from Step 5b Notion data)
- Errand keywords: "buy", "pick up", "drop off", "return", "store", "grocery", "pharmacy"
- Project work signals: "edit", "deliver", "review", "send invoice", "draft", "schedule shoot", "add to Notion"
- Has a due date → more likely Quick Action or Notion Task than Errand
- If ambiguous, default to `keep_inbox` — never guess

Each Inbox item produces a triage proposal object (see INBOX_TRIAGE_JSON format below). These are separate from schedule proposals — they route items to other systems (Notion, other lists) rather than proposing time slots.

#### 5d — Overdue Detection

Scan for tasks and reminders that are past their Do Date / due date. These enter the Weekly Triage system so Kam can batch-reschedule them instead of discovering them scattered throughout the week.

**Sources:**
1. **Notion Tasks DB** — query for tasks where Do Date < today AND Status is NOT "Done" or "Cancelled"
2. **Apple Reminders** — from all mapped lists (already read in 5b), filter for items with due date < today and not completed

**Deduplication:** If a reminder and a Notion task share the same title and due date, keep only the Notion source (it's the richer record).

**For each overdue item, calculate:**
- `daysOverdue` — calendar days past Do Date
- `riskLevel` — based on Due Date proximity:
  - `critical` — Due Date is past OR within 2 days
  - `warning` — Due Date is within 3–7 days
  - `low` — Due Date is >7 days away OR no Due Date set
- `proposedNewDate` — the next appropriate day this week, based on:
  - Task energy level → time-of-day rules (deep = morning, light = afternoon)
  - Task category → day type match (Work → weekday creative/admin, Personal → weekend)
  - Available gaps in the calendar (don't stack on already-packed days)
- `proposedBlock` — if the task has a Duration field (from Notion) or estimated duration, propose a specific `{day, start, end}` time slot. If no duration, propose date only (no time block).

**Threshold:** Only include items where `daysOverdue >= overdue_threshold_days` (from config, default 1). This prevents items due earlier today from cluttering triage.

Each overdue item produces a triage object with `type: "overdue_task"` (see WEEKLY_TRIAGE_JSON format below).

#### 5e — Calendar Invite Detection

Scan Google Calendar for pending invites that haven't been RSVPed. These enter the Weekly Triage so Kam can batch-process accept/decline decisions.

**Query:** Using Google Calendar MCP (`gcal_list_events`), fetch events for the coming `invite_lookahead_days` (from config, default 7) where `myResponseStatus === "needsAction"`.

Check ALL calendars listed in the config's `calendars` section with `treatment: Include`.

**For each pending invite:**
1. **Analyze context:**
   - Is the organizer in `priority_contacts`? → weight toward accept
   - How many attendees? → large meetings may be lower priority for Kam
   - Does the time conflict with existing confirmed events or proposed blocks?
   - Does the event topic align with active projects? (match title/description against project names)

2. **Generate recommendation:** One of `accept`, `tentative`, or `decline` with a 1-2 sentence `reason` explaining why.
   - Default to `tentative` if unsure — never auto-decline priority contacts
   - Decline recommendation only if: clear time conflict with higher-priority work, or no relevance to active projects/goals

3. **Calculate cascade effects:** If the invite is accepted, what existing blocks would need to move?
   - Check for time overlaps with proposed blocks (`bs` state) and existing events
   - For each conflict: `{blockTitle, action: "shift"|"remove", from, to}`
   - Limit cascade chain depth to `cascade_max_depth` (from config, default 3)

Each pending invite produces a triage object with `type: "pending_invite"` (see WEEKLY_TRIAGE_JSON format below).

#### 5f — Task-Calendar Fusion

Identify Notion tasks that have a Duration set but no matching calendar event. These are tasks Kam has estimated but hasn't time-blocked — the engine proposes specific slots.

**Query:** From the Notion Tasks already gathered in Step 5b, filter for tasks where:
- Duration field > 0 (minutes)
- Status is "Not started" or "In progress" (not Done/Cancelled/Waiting)
- Do Date is within the current planning week OR has no Do Date (floating tasks)
- No matching Google Calendar event exists (match by title similarity against this week's events)

**For each unscheduled task:**
1. **Match energy to time-of-day:**
   - `deep` energy → morning slots (before noon)
   - `moderate` energy → midday (10am–3pm)
   - `light` energy → afternoon/evening (after 2pm)
   - If no Energy field, default to `moderate`

2. **Match category to day type:**
   - Check the task's Project Area → day type mapping (from `AREA_DT` in config)
   - Prefer days where the day type matches the task category
   - If no match this week, use any day with available time

3. **Find available slot:**
   - Scan the week's calendar for gaps that fit the task's Duration
   - Avoid stacking on days that already have 6+ hours scheduled
   - Respect deep focus minimum (from config proposal settings) — don't fragment deep tasks

4. **Propose block:** `{day, start, end}` with the specific time slot

Each unscheduled task produces a triage object with `type: "needs_time_block"` (see WEEKLY_TRIAGE_JSON format below).

**Skip condition:** If `fusion_enabled` is `false` in config, skip this step entirely.

### Gmail — Since Last Run

Pull everything since `last_run` in config. Default to past 7 days if no timestamp.

Silently skip before classifying: newsletters, receipts, automated notifications, marketing.

Extract: subject, sender, body snippet (300 chars), received time.

### iMessages — Since Last Run

Pull recent iMessage conversations using the iMessages MCP. Scan threads since `last_run` (default: past 7 days).

**What to look for:**
- Messages mentioning project names, client names, or shoot dates — associate with the matching Notion project
- Scheduling conversations ("can we do Thursday?", "let's push to next week") — these signal calendar changes the engine should reflect
- Action items or commitments ("I'll send the invoice", "I'll review it tonight") — surface as proposals or reminders
- Status updates ("it's done", "we wrapped", "still waiting") — update project context

**Context association:** For each relevant message thread, identify which project, client, or calendar event it relates to by matching:
1. Contact name against Notion clients, project owners, or priority contacts in config
2. Keywords against active project names, film titles, or milestones
3. Dates mentioned against calendar events this week

**Output:** Build a `messageContext` array — each entry has `contact`, `summary` (1-2 sentences), `relatedProject` (project name or empty), `actionItems` (array of strings), `timestamp`. This feeds into Step 6 proposal generation and Step 5b context research.

**Privacy:** Never reproduce full message text in the dashboard. Only use extracted context (summaries, action items) for planning.

### Memory MCP — Change Detection

Query Kam Memory MCP for changes since `last_run`. This catches decisions, facts, and status updates from other sessions that happened between engine runs.

```
aim_memory_search: query="weekly rhythm" OR project names from config
aim_memory_get: names=["Weekly_Rhythm_Engine", "Active_Projects_Snapshot"]
```

**What to look for:**
- Project status changes (e.g., "Phase 5 complete" → engine should update its understanding)
- New facts added since last run (new contacts, decisions, deadlines)
- Updated next actions that differ from what Notion shows (Memory may be more current than Notion)
- Session summaries from Deep Context that mention actionable items

**Reconciliation:** When Memory and Notion disagree (e.g., Memory says "Phase 5 complete" but Notion says "Phase 3"), trust Memory MCP as more current — it gets updated every session. Flag the discrepancy in the dashboard so the user can update Notion.

**Output:** A `memoryDiff` object with `changedProjects` (array of project names + what changed), `newFacts` (array of strings), `staleNotionFlags` (array of project names where Notion needs updating). This feeds into the brief content and project pulse rendering.

### Step 5b — Notion Project Data + Context Research

Query the Command Center databases for active project and task data. Use the database IDs from config (`notion_databases` section).

**Query 1 — Active Projects:** Search the Projects database for projects where Status is in the "In progress" group (Active, On Hold). For each project, extract: Name, Area, Type, Stage, Next Action, Next Action Due, Energy, Priority, Film Project Link (if any), Notes, Owner.

**Query 2 — This Week's Tasks:** Search the Tasks database for tasks with Do Date within the current week OR Due Date within the current week, AND Status is not "Done" or "Cancelled". Group by Project relation.

**Query 3 — Stalled Projects:** From the active projects, flag any where Next Action is empty. These are projects with no clear next step defined — they need attention before the engine can propose useful work.

**Query 4 — Film Milestones:** If any active projects have a Film Project Link, query the Workback Schedule for milestones landing this week or next.

#### Context-Richness Classification

After gathering all project data, classify each active project by how much the engine knows about it:

| Level | Criteria | What it means |
|-------|----------|---------------|
| **Rich** | Has 2+ tasks this week, a clear next action, activity in the last 7 days | Engine has enough to propose specific time-slotted actions |
| **Thin** | Exists but has 0-1 tasks, vague/missing next action, OR stalled >21 days | Engine needs more context before it can propose useful next steps |
| **New** | Created in the last 14 days, no tasks, no history | Engine knows almost nothing — needs research before proposing anything |

#### Smart Research (for Thin and New projects only)

For projects classified as **thin** or **new**, the engine gathers additional context before proposing next steps. This is the research phase — do NOT skip it for thin/new projects.

**Internal sources (always check for thin + new):**
1. **Gmail:** Search for threads mentioning the project name, client name, or key contacts. Extract relevant context — what's been discussed, what's been promised, what's pending.
2. **Calendar:** Search for past and upcoming events related to the project. What meetings happened? What's coming?
3. **Kam Memory MCP:** Search for any stored facts about this project or client.
4. **iMessages:** Search recent conversations with contacts associated with the project. Look for scheduling, status updates, commitments, or action items discussed via text.

**External sources (new projects only, when internal sources are insufficient):**
If after checking internal sources a new project still has no clear direction (no email threads, no calendar history, no memory):
1. Run 1-2 targeted web searches related to the project type or industry (e.g., "editorial shoot production workflow" or "podcast production timeline best practices")
2. Look for methodologies, common workflows, or industry standards that could inform a starting plan
3. Keep research focused and time-bounded — this is context gathering, not a deep dive

**Store findings:** For each thin/new project, compile a `researchFindings` summary — 2-4 sentences capturing what was found across all sources. This feeds into the proposal generation in Step 6.

**Graceful degradation:** If Notion MCP is unavailable or times out, skip this step entirely and proceed with Calendar + Reminders + Gmail data only. Log the skip in the brief.

---

## Step 5g — Location Intelligence Analysis

**Prerequisite:** `travel_itinerary_enabled: true` in config AND Google Maps MCP connected (detected in Step 2a health check). If either is false, skip this entire step and set `LOCATION_INTEL_JSON` to `{}`.

This step geocodes event locations, detects travel vs commute days, computes drive times, plans errand routes, and generates lunch suggestions.

### 5g-i — Geocode Home Address

First check Memory MCP for a cached `Location_Cache` entity with `home_geo` coordinates. If found, reuse them. If not:

```
maps_geocode(address: config.home_address)
```

Cache the result:
```
aim_memory_store(name: "Location_Cache", entityType: "cache")
aim_memory_add_facts(entityName: "Location_Cache", contents: [
  "home_geo: {lat},{lng} ({config.home_address})",
  "rb_geo: {lat},{lng} ({config.rb_address})"
])
```

Store as `homeGeo = { lat, lng }`.

### 5g-ii — Geocode Event Locations

For every event in the planning window (all dates covered by the current view — 7 or 30 days) that has a non-empty Location field:

**Skip if location matches any of:** "Zoom", "Virtual", "Google Meet", "Teams", "Remote", "Online", "FaceTime", any URL (starts with http/https), "Home", "TBD", "TBA"

For all others, call `maps_geocode(address: event.location)`.

Build a location map:
```json
{
  "eventId": {
    "address": "original location string",
    "lat": 36.1234,
    "lng": -86.5678,
    "isRemote": false,
    "geocodeSuccess": true
  }
}
```

If geocoding fails for an event (vague location like "downtown" or "studio"), set `geocodeSuccess: false` and skip that event in subsequent location analysis. Do NOT guess coordinates.

**Call budget:** Max ~15 geocode calls per run. If more than 15 events have locations, prioritize events in the current week over later dates.

### 5g-iii — Detect Travel vs Commute Mode

For each day in the planning window, check if any event's geocoded location is more than 60 miles from `homeGeo`.

**Distance calculation:** Use the Haversine formula (compute in reasoning, no MCP call needed):
```
d = 2 * R * arcsin(sqrt(sin²((lat2-lat1)/2) + cos(lat1)*cos(lat2)*sin²((lng2-lng1)/2)))
R = 3959 miles
```

- **Travel Mode:** Any event >60mi from home → that day (and travel days around it) are in travel mode
- **Commute Mode:** All events <60mi from home → normal commute analysis

Set `dayMode[date] = "travel" | "commute" | "home"` for each day. "home" means no events with physical locations.

### 5g-iv — Travel Mode Processing

For each travel day, check if the events indicate a flight:

**Flight detection keywords** (scan event title + description): airline names (Southwest, Delta, American, United, JetBlue, Spirit, Frontier, Alaska), flight numbers (2-4 digit numbers after airline abbreviations), airport codes (3-letter IATA codes like BNA, LAX, ATL, AUS), "boarding", "departs", "takeoff", "gate", "terminal", "TSA"

**If a flight is detected**, generate a full travel itinerary working backwards from boarding time:

1. **Boarding time** — from event start time or description
2. **Airport arrival** — boarding time minus buffer from config:
   - Check `config.familiar_airports` — if departure airport is in the list: `domestic_familiar_bag` (60min default)
   - If not familiar: `domestic_unfamiliar` (90min)
   - International flights: `international` (120min)
   - If rental car return at airport: add `rental_car_return` (25min) on top
3. **Drive to airport** — call `maps_directions(origin: home_address or last_event_location, destination: airport_address, departure_time: calculated_departure_iso)`. Use `duration_in_traffic` from response.
4. **R&B drop-off** — if departing from home and travel is >1 day, add a stop at `config.rb_address` before the airport. Call `maps_directions` for home→R&B and R&B→airport legs separately.
5. **Pack/prep block** — auto-propose a "Pack + prep for [trip name]" reminder for the day before departure, 1 hour duration, afternoon slot.

**Build itinerary object:**
```json
{
  "date": "2026-04-16",
  "mode": "travel",
  "destination": "Atlanta",
  "flight": {
    "airline": "Southwest",
    "number": "WN 1234",
    "from": "BNA",
    "to": "ATL",
    "boards": "11:00",
    "departs": "11:30"
  },
  "itinerary": [
    { "time": "07:15", "emoji": "car", "action": "Leave home", "detail": "18 min drive to parents" },
    { "time": "07:35", "emoji": "dog", "action": "R&B drop-off", "detail": "726 Ewell Farm Dr, Spring Hill" },
    { "time": "08:10", "emoji": "car", "action": "Drive to BNA", "detail": "35 min via I-65 N" },
    { "time": "08:45", "emoji": "airport", "action": "Arrive at BNA", "detail": "TSA + gate — 1hr 15min buffer" },
    { "time": "10:00", "emoji": "board", "action": "Board flight", "detail": "Gate TBD" }
  ],
  "appleNoteTitle": "Travel Iten — Nashville → Atlanta April 2026",
  "appleNoteBody": "<h1>Travel Iten — Nashville → Atlanta April 2026</h1>..."
}
```

**Apple Notes body format:** Follow the Travel Itinerary Skill format exactly:
- `<h1>` title, `<h3>` date
- Each step: emoji + time + action + detail in Courier 12px
- `<blockquote>` only for real alerts (tight timing, rental car notes)
- `#iten` tag at bottom with 4 blank lines above

**If NO flight detected** but the day is travel mode (distant event), generate a simpler drive itinerary:
- Call `maps_directions` from home to event location with departure_time
- Note the drive time in the itinerary
- Still propose pack/prep if overnight

### 5g-v — Commute Mode Processing

For each commute day, find consecutive events that are at different physical locations (both non-remote, both geocoded successfully).

For each pair, call:
```
maps_distance_matrix(
  origins: [first_event.location],
  destinations: [second_event.location],
  departure_time: first_event.endTime_iso
)
```

Calculate:
- `driveMinutes` = `duration_in_traffic` from response (in minutes)
- `gapMinutes` = second_event.startTime - first_event.endTime (in minutes)
- `severity` = driveMinutes > gapMinutes ? "conflict" : driveMinutes > gapMinutes - 10 ? "tight" : "ok"

**Build warnings array:**
```json
{
  "date": "2026-04-14",
  "fromEvent": "Client lunch downtown",
  "fromEndTime": "13:30",
  "toEvent": "Team standup at studio",
  "toStartTime": "14:00",
  "driveMinutes": 35,
  "gapMinutes": 30,
  "severity": "conflict",
  "suggestion": "Leave lunch 5 min early or shift standup to 2:15pm"
}
```

Only include warnings where `severity` is "conflict" or "tight". Skip "ok" pairs.

### 5g-vi — Smart Errand Routing

Gather all floating errands — reminders in the "Errands" list (or category Errand) that have no specific scheduled time for this week.

For errands that have a location (from reminder notes, or infer from store names like "Target", "Kroger", "Home Depot", "Costco"):
1. Geocode each errand location
2. Compute distances from home to each errand and between errands
3. Route using **furthest-first**: start with the farthest errand from home, work back toward home. This minimizes total backtracking.

Call `maps_directions` with waypoints for the full route:
```
maps_directions(
  origin: config.home_address,
  destination: config.home_address,
  waypoints: [errand1_address, errand2_address, ...],
  departure_time: proposed_start_iso,
  optimize_waypoints: true
)
```

**Build errand route:**
```json
{
  "date": "2026-04-18",
  "stops": [
    { "name": "Costco (Cool Springs)", "address": "2100 Crossing Blvd, Franklin", "estimatedMinutes": 25 },
    { "name": "Target (Mallory Lane)", "address": "1745 Mallory Ln, Brentwood", "estimatedMinutes": 15 },
    { "name": "Kroger (Franklin Rd)", "address": "330 Franklin Rd, Franklin", "estimatedMinutes": 20 }
  ],
  "totalDriveMinutes": 38,
  "totalShoppingMinutes": 60,
  "departTime": "14:00",
  "returnTime": "15:38",
  "routeNote": "Furthest first (Costco), ending 8 min from home (Kroger)"
}
```

If no errands have geocodeable locations, skip this sub-step.

### 5g-vii — Lunch Planning

For each weekday in the planning window, determine the user's location over the lunch window (11:30am–1:30pm):

1. Check events that overlap or are adjacent to the lunch window
2. If the user has a physical-location event during lunch → they're **away from home**
3. If no events or only remote events → they're **at home**

**Away from home:**
Call `maps_search_places` to find nearby restaurants:
```
maps_search_places(
  query: config.lunch_preferences.likes[cycle_index],
  location: "{midday_event_lat},{midday_event_lng}",
  radius: 2000
)
```

Cycle through the `likes` array across different days (Monday = likes[0], Tuesday = likes[1], etc.) for variety.

Filter results:
- Exclude restaurants matching `config.lunch_preferences.avoids`
- Prefer `config.lunch_preferences.price_range` (map $$ to priceLevel 2)
- Take top 2-3 results

**At home:**
Set suggestion type to "home" with note "Home all morning — do you have something at home, or want to order?"

**Build lunch suggestions:**
```json
{
  "date": "2026-04-14",
  "type": "restaurant",
  "location": "downtown Nashville",
  "suggestions": [
    { "name": "Noko", "cuisine": "Japanese", "rating": 4.5, "priceLevel": 2, "walkMinutes": 3, "address": "163 3rd Ave N" },
    { "name": "Taqueria del Sol", "cuisine": "Mexican", "rating": 4.3, "priceLevel": 2, "walkMinutes": 5, "address": "600 8th Ave S" }
  ]
}
```

or:

```json
{
  "date": "2026-04-15",
  "type": "home",
  "note": "Home all morning — do you have something at home, or want to order?"
}
```

### 5g Output — LOCATION_INTEL_JSON

Assemble all location intelligence into one JSON object:

```json
{
  "travelDays": [ ...itinerary objects from 5g-iv... ],
  "commuteWarnings": [ ...warning objects from 5g-v... ],
  "errandRoute": { ...route object from 5g-vi... },
  "lunchSuggestions": [ ...suggestion objects from 5g-vii... ],
  "dayModes": { "2026-04-14": "commute", "2026-04-16": "travel", ... }
}
```

If a sub-step produced no results (e.g., no travel days, no commute conflicts), use an empty array `[]` or `null` for that field. Never omit the field.

### Graceful Degradation

- **Google Maps MCP unavailable:** Skip entire Step 5g. Set `LOCATION_INTEL_JSON = {}`. Note in brief: "Google Maps not connected — location intelligence unavailable this run."
- **Individual geocode failures:** Skip that event in subsequent analysis. Don't fail the whole step.
- **Maps API rate limit or error on a specific call:** Log it, skip that sub-analysis, continue with remaining sub-steps.
- **No events with locations:** Skip 5g-ii through 5g-v. Still run 5g-vii (lunch planning uses home-vs-away logic).

---

## Step 5h — Family Messages Inbox Scanner

**Prerequisite:** `family_sync_enabled: true` in config. If false, skip this step entirely and set `FAMILY_MESSAGES_JSON = []`.

This step scans the family messaging inbox for messages received from configured family partners since the last run, and surfaces them in the dashboard's Family Message Board card.

**Inbox path:** `{icloud_path}/messages/inbox/`

Each message is a markdown file named `{ISO-timestamp}-{sender}-{category}.md` with frontmatter:

```markdown
---
from: Tiera
timestamp: 2026-04-13T14:30:00-05:00
category: travel
urgency: normal
subject: Atlanta trip itinerary
status: unread
read_at: null
action_items:
  - Drop R&B at Mom's by 7:30am Thursday
  - Confirm hotel checkout time
---

Body of the message in markdown.
```

**Scan algorithm:**
1. List all `.md` files in `{icloud_path}/messages/inbox/`
2. Parse each frontmatter block; skip files that fail to parse (log a warning, never crash)
3. Filter out messages where `status: archived` AND `timestamp` is older than `message_auto_archive_days` (config, default 30)
4. Sort newest-first
5. (Optional check) For each `family_partners` entry in config, also peek at `{partner_icloud_path}/messages/inbox/` for messages where `from == currentUser` to verify Step 12b deliveries — informational only

**Build `FAMILY_MESSAGES_JSON`:**
```json
[
  {
    "id": "msg-2026-04-13-tiera-travel",
    "from": "Tiera",
    "timestamp": "2026-04-13T14:30:00-05:00",
    "category": "travel",
    "urgency": "normal",
    "subject": "Atlanta trip itinerary",
    "body": "Body markdown rendered to plain text",
    "status": "unread",
    "read_at": null,
    "action_items": [
      "Drop R&B at Mom's by 7:30am Thursday",
      "Confirm hotel checkout time"
    ],
    "filePath": "messages/inbox/2026-04-13T14:30:00-tiera-travel.md"
  }
]
```

**Auto-mark-read:** When the dashboard renders, any unread messages older than 24 hours get auto-marked as read on next run. Update the file frontmatter `status: read` and `read_at: {now}`.

**Action item bridging:** If a message has `action_items[]`, surface them in Step 6 as candidate proposals with `sourceType: "family_message"` and `sourceMessageId: msg-...`. The user can accept/reject in the planner. Accepted items inherit the message's urgency for placement priority.

**Graceful degradation:** If the inbox folder doesn't exist, create it on first run. If a message file fails to parse, log a warning and skip it. Never crash the run on a malformed message.

---

## Step 6 — Classify, Place, and Propose

Determine for each item: Category (Creative | Business Dev | Admin | Personal | Errand | Family), Urgency, Calendar block needed, Suggested placement.

### Proposal Types

Every proposal the engine generates has a `proposalType`. The type determines how the item appears in the dashboard and what information is shown when the user clicks "Why?"

#### Standard Proposal (`proposalType: "standard"`)

Used for **rich-context** items where the engine knows exactly what needs to happen and when.

- The engine proposes a specific time slot with a clear action
- The "Why?" modal shows the reasoning, connected project, and related items
- Example: "Upload RS shoot selects to Dropbox — Wed 9:00am–11:00am"

This is the default for most items: calendar events to prep for, tasks with clear next actions, follow-ups with known deadlines.

#### Direction Proposal (`proposalType: "direction"`)

Used for **thin** or **new** projects where the engine can't just schedule a task — it needs to propose *what to do*, not just *when to do it*.

The engine generates:
1. **2-3 concrete options** — each with a label, 1-sentence description, and a trade-off line (pro/con)
2. **A recommended option** — flagged with a "Recommended" badge, with a brief note on why. This reduces decision fatigue. However, **no option is pre-selected** — the user must actively choose. They can also choose nothing if none of the options fit.
3. **Questions** — specific things the engine doesn't know that would improve future proposals. Frame as "These would help me give better suggestions next time" — not as blockers. The dashboard includes a "→ Notion" button next to each question so the user can flag unknowns for later research.
4. **Research findings** — what the engine found in Gmail, Calendar, Memory, or web during Step 5b. Shows its work so the user trusts the recommendation.

**Title framing:** Direction proposals are triage sessions — title them as decision-making actions, not work execution. Examples: "cmdshft Retainer — Decide Next Move", "YouTube Channel — Work Through Direction". The time slot represents time to review options and decide, not to do the work itself.

Example:
```
Title: "cmdshft Retainer — Next Move"
Recommended: Schedule a casual scope call with Pierre
  → Faster than a formal proposal, builds rapport, and Pierre has been responsive in email.

Option B: Send formal retainer proposal document
  → Professional and clear scope, but takes 2+ hours to draft.

Option C: Email a rough scope outline for feedback
  → Low effort, keeps momentum, but less polished.

Questions:
  • Has Pierre mentioned a preferred format for proposals?
  • What retainer value range are you targeting?

Research: Found 3 email threads with Pierre from March discussing project scope.
  Last email (Mar 28): Pierre asked about "monthly content packages."
```

**Key principle:** Direction proposals educate the user and present options — they do NOT make the decision. The engine thinks like plan mode: research, surface what it found, propose paths, let the user choose.

#### Transition Buffer (`proposalType: "transition"`)

Used for 15-min blocks between task-type switches. See Step 6b below.

---

### Scheduling Rules

| Rule | Applies when |
|------|-------------|
| Creative: mornings only | Never after 3pm |
| Admin on Creative Day → noon+ | Keeps mornings protected |
| Priority contacts first | Matches config priority list |
| Calls ≤ 30 min flex | Any day type |
| Errands: fill open gaps | Batch or slot into space |
| Coffee/meeting buffer: +30min | After any in-person meeting (coffee, lunch, etc.) add at least 30 min before the next proposed block. Coffee at 9–10am → next block at 10:30am earliest, 11am preferred. |
| Flag rather than guess | Unclear scope or timing |

### ASD-Informed Scheduling Rules

These rules are informed by Kam's neurodivergent profile (circumscribed interests, routine sensitivity, transition difficulty, literal processing, planning-vs-executing friction). They are non-negotiable scheduling constraints — apply them automatically, every run.

1. **Protect deep focus blocks.** Never schedule a task shorter than 30 minutes inside a 2+ hour creative or deep-focus block. If creative work is happening 9am–12pm, do not slot a 15-min call at 10:30am. Deep focus is expensive to build and expensive to break.

2. **Honor circumscribed interests.** If a project has high engagement (high task count, recent activity, lots of energy), give it the largest uninterrupted time block of the week on its best-matching day type. This is the project the brain *wants* to work on — ride that energy.

3. **Reduce decision fatigue.** Direction proposals always lead with one recommended option. Standard proposals present one clear action, not multiple alternatives. The user can ask for alternatives — don't front-load them.

4. **Be concrete, not ambiguous.** Every proposal has a specific day, date, start time, end time, and action. Never "sometime this week," "when you get a chance," "morning," or "afternoon." Ambiguity creates decision paralysis.

5. **Anti-planning-spiral.** When proposing research or exploration tasks, time-box them: "Research X for 30 minutes" not "Figure out X." Open-ended tasks become planning traps. Put a clock on it.

6. **Predictable format.** The engine output follows the exact same section order every run. Same structure, same flow, same expectations. No surprise sections, no rearranging. Predictability reduces cognitive load.

7. **Transition buffers.** 15-min buffer blocks between different task types (see Step 6b). These are real proposed calendar events, not just notes.

### Location-Aware Scheduling Rules (requires Step 5g)

These rules apply when `LOCATION_INTEL_JSON` is populated. If Step 5g was skipped, ignore these rules.

8. **Travel days suppress proposals.** If `dayModes[date] == "travel"`, do NOT generate work proposals for that day. The travel itinerary IS the plan. Only exception: a pre-existing calendar event on a travel day stays on the grid.

9. **Pack/prep auto-proposal.** If tomorrow is a travel day and today is not, auto-propose a "Pack + prep for [trip name]" block. 1 hour, afternoon slot, Personal task type.

10. **Commute buffers.** If two proposed blocks on the same day are at different physical locations and `commuteWarnings` shows a conflict or tight gap, either: (a) add a commute buffer between them, or (b) shift the second block later to accommodate drive time. Note the drive time in the proposal reason.

11. **Errand batching by route.** When placing errands, prefer the route order from `errandRoute` in Step 5g-vi. Propose them as a single contiguous block rather than scattered individual slots. Include the route note in the proposal reason.

### Errand Handling
Surface as a floating pool. Nudge items sitting longer than config threshold (default: 14 days) — brief note, not pushy.

### Milestone Context
When a significant event lands — release day, launch, project delivery, anniversary — apply specific, useful context. Think about what Kam might forget to do.

Good examples:
- **Release day** → "Milestone day. Have promo content ready. Check socials, share the work, celebrate."
- **Shoot day** → "Prep the day before: confirm crew, pack gear, review call sheet."
- **Content day** → "Review shot list in the morning. Capture B-roll while energy is high."
- **Delivery deadline** → "Send 24 hrs early if possible. Follow up same day."
- **Birthday/anniversary** → "Don't let this slip. Plan something ahead of time."

Be specific and useful. Never generic motivational filler. If there's nothing meaningful to add, say nothing.

---

## Step 6b — Transition Buffer Scanning

After all items are placed in Step 6, scan each day's schedule chronologically for task-type transitions.

**When to insert a buffer:**
- Two consecutive scheduled blocks (existing events OR proposed blocks) have different `taskType` values
- AND the gap between them is less than 30 minutes

**When NOT to insert a buffer:**
- The gap is already 30+ minutes (natural transition time exists)
- Both blocks are the same task type
- One of the blocks is already a transition buffer

**Buffer block format:**
```
{
  "proposalType": "transition",
  "taskType": "transition",
  "title": "Transition: Creative → Admin",
  "proposalReason": "Switching from creative work to admin tasks. Take a moment to reset — close creative files, grab water, review your admin checklist. Transitions between modes cost energy; this buffer protects your focus on both sides.",
  "startTime": [end time of first block],
  "endTime": [start time + 15 min],
  "date": [same day]
}
```

Buffer blocks are proposed like any other item — the user can check or uncheck them. They appear in the Week Planner with a muted, dashed visual style distinct from real events.

**Limit:** Maximum 3 transition buffers per day. If a day has more than 3 task-type switches, only buffer the largest transitions (creative↔admin, creative↔personal, deep focus↔meetings).

---

## Step 6c — Proposed Family Messages

**Prerequisite:** `family_sync_enabled: true` in config. If false, skip this step and set `PROPOSED_FAM_MSGS_JSON = []`.

After all blocks are placed (Step 6/6b) but before brief generation (Step 9), query Memory MCP for past outbound-message patterns and unfulfilled partner action items. Synthesize 3–5 draft message candidates the engine thinks the user might want to send.

**Sources:**
1. **Memory MCP `Family_Message_Log` entity** — past outbound messages, by category. Look for recurring patterns (e.g., "Kam sends Tiera a travel itinerary heads-up the day before any flight").
2. **Unfulfilled action items from inbound messages** — items in `FAMILY_MESSAGES_JSON` where the user hasn't replied or acted yet (no matching outbound entry in the log within 48 hours of receipt).
3. **Calendar context** — upcoming travel days, late evenings, busy stretches that affect the partner.
4. **R&B drop-off detection** — if any travel itinerary in `LOCATION_INTEL_JSON` requires an R&B drop-off, propose a heads-up message to the partner about timing.

**For each candidate, build:**
```json
{
  "id": "fammsg-1",
  "to": "Tiera",
  "category": "travel",
  "draft": "Heads up — flying to Atlanta Thursday morning. R&B will go to Mom's at 7:30am. Boarding 11am, back Saturday evening.",
  "reason": "You usually send Tiera an itinerary heads-up the day before flights. This Thursday's BNA→ATL trip wasn't mentioned in the last 7 days of family messages.",
  "relatedItem": "loc-travel-2026-04-16",
  "urgency": "normal"
}
```

**Build `PROPOSED_FAM_MSGS_JSON`** with 3–5 of the strongest candidates. Empty array if no patterns surface or if the partner has been kept up to date.

The dashboard renders these in the Family Message Board "Proposed messages" section. The user can:
- **Accept** → message is queued in the dashboard's compose buffer and sent via Step 12b on paste-back
- **Edit** → edit the draft inline before accepting
- **Dismiss** → log dismissal to Memory MCP so the engine doesn't re-propose the same draft next run

**Calibration over time:** Memory MCP `Family_Message_Calibration` entity tracks accept-rate per category. If "travel heads-up" gets accepted 4/4 times, weight it higher in future proposals. If "weekly check-in" gets dismissed 5/5 times, stop proposing it.

---

## Step 7 — Birthdays and Personal Awareness

Scan ALL calendars for:
- **Birthdays** in the next 14 days → surface in PERSONAL with an explicit days-away count
- **Anniversaries** → same treatment
- **Family events** from the family calendar that affect availability or need coordination

**Format required:** Always include the day name, date, AND how many days away — e.g., `"Dad's Birthday — Sunday, April 5, 2 days away"`. Never just a date without the day count. Never just a name without the date.

Surface with enough lead time to act — not the morning of.

---

## Step 8 — Check Goals

For each active goal in config `## Goals`:
1. Does anything on this week's calendar/tasks move toward it?
2. If yes: covered (silent if `on_track_behavior: silent`)
3. If no: one specific, actionable suggestion — concrete, tied to the goal, not already scheduled

One suggestion per goal max. Omit section if all covered + silent.

---

## Step 8b — Write Scratchpad (context preservation)

After completing classification (Steps 5–8), write a structured scratchpad file to preserve all assembled data before brief and dashboard generation. This prevents context compaction from losing classified data mid-run — especially important in Cowork on Sonnet where the context window fills up fast with calendar, reminder, Gmail, and Memory MCP data.

**Write to:** `{icloud_path}/scratchpad-{YYYY-MM-DD}.md` (or the session outputs directory if iCloud is unavailable)

**Contents — include ALL of these:**
- All classified events (day, time, title, type, source calendar)
- All reminders with list mapping, priority, and due dates
- Flagged items with decision context
- Proposed calendar blocks with specific times and proposal reasons
- Proposed reminders with list, priority, and due date
- Day narratives (one paragraph per day)
- Brief content HTML (the structured `<div class="bct-line">` divs per Step 9's format)
- Goal coverage status and any suggestions
- All JSON arrays ready for template injection (PROPOSED_BLOCKS_JSON, EXISTING_EVENTS_JSON, REMINDERS_JSON, REMINDER_LISTS_JSON, INBOX_TRIAGE_JSON, WEEKLY_TRIAGE_JSON, DAY_NARRATIVES_JSON, WEEK_GOALS_JSON, PROJECTS_JSON, LOCATION_INTEL_JSON, UPDATE_BANNER_JSON, DAY_TYPES_JSON, FAMILY_MESSAGES_JSON, PROPOSED_FAM_MSGS_JSON, RUN_REPORT_JSON)

**Placeholder-ready format:** Structure the scratchpad so that each JSON array section is already valid JSON that can be copied directly into the `.placeholders-{YYYY-MM-DD}.json` file used by Step 10b-ii. This means if context compacts between Step 8b and Step 10b, the engine can re-read the scratchpad and pipe the values straight to the Python substitution script without re-deriving anything.

**Recovery:** If context is compacted before Step 10b, re-read the scratchpad file to recover all structured data needed for dashboard generation.

**Cleanup:** Delete the scratchpad after successful dashboard generation. If the run fails, leave it in place as a debug artifact.

---

## Step 9 — Generate the Weekly Brief

Read the template using the Read tool:

```
Read: {icloud_path}/template-weekly.md
```

Fill each `{{variable}}` with the content assembled in Steps 4–8.

### Output Principles
- No metadata, no scan notes — just the brief
- Every line earns its place
- Stay within template sections — never invent new ones
- Omit `{{draft_count}}` if zero; omit any empty section
- **Never fabricate** — every item must come from an actual tool result

### Biblical Verse (Optional)
If there's a genuinely fitting connection between the week ahead and scripture — include one verse at the top. KJV or NIV only. The verse must feel earned and relevant to this specific week.

If nothing fits: say nothing. No motivational filler, no generic inspiration, no "Bring creative energy." Either a real verse with real relevance, or silence.

### Brief Content — Structured Highlights ({{BRIEF_CONTENT}})

The brief card at the top of the dashboard is the first thing the user sees. It must work like a filing cabinet — organize information so the brain can slot things immediately without reading a wall of text.

**Format:** Generate `{{BRIEF_CONTENT}}` as structured HTML, one div per day. Each day gets:
- A colored dot matching its day type
- Bold day label (e.g., "Mon — RS Editorial Shoot")
- 1-line summary of the key items/theme for that day
- Optional detail line with supporting context (smaller, muted)

**HTML structure:**
```html
<div class="bct-line">
  <div class="bct-dot" style="background:#9e3020"></div>
  <div class="bct-content">
    <div class="bct-day">Mon — RS Editorial Shoot</div>
    <div class="bct-summary">Crew call 9am · Fire Tower Farm, Only TN · 2x Burano + FX9 + FX3</div>
  </div>
</div>
<div class="bct-line">
  <div class="bct-dot" style="background:#2e6090"></div>
  <div class="bct-content">
    <div class="bct-day">Tue — Business Dev Push</div>
    <div class="bct-summary">cmdshft retainer call with Pierre · Reply to BMP Creative cam op gig</div>
  </div>
</div>
```

**Color mapping for dots:** Use the day type color from the DTC constants — Creative=#b8611a, Business Dev=#2e6090, Admin=#6a3e98, Personal=#3a7a50, Shoot Day=#9e3020, Content Day=#8a6800, Travel=#1878a0, Edit Day=#5a6e7a, Off=#555.

**Location alerts in brief:** If `LOCATION_INTEL_JSON` has travel days or commute conflicts, add alert lines at the TOP of BRIEF_CONTENT (before the first day):

```html
<div class="bct-line">
  <div class="bct-dot" style="background:#1878a0"></div>
  <div class="bct-content">
    <div class="bct-day">Travel: Nashville → Atlanta (Thu Apr 16)</div>
    <div class="bct-summary">Leave home 7:15am · R&B drop-off · BNA boards 10:00am</div>
  </div>
</div>
```

For commute conflicts:
```html
<div class="bct-line">
  <div class="bct-dot" style="background:#b85848"></div>
  <div class="bct-content">
    <div class="bct-day">Commute conflict: Tue 1:30pm → 2:00pm</div>
    <div class="bct-summary">Client lunch downtown → Studio (35min drive, only 30min gap)</div>
  </div>
</div>
```

**Rules:**
- Skip days with nothing notable (no events, no proposals, no milestones)
- Keep each day to 1-2 lines max — this is a snapshot, not a full breakdown
- The Day-by-Day Breakdown section has the full detail — the brief just sets the mental frame
- Bold the most important word or phrase in each summary (the thing the brain should latch onto)
- Use middle dots (·) to separate items within a line, not commas or "and"

### Day-by-Day Overview (for template-weekly.md)
Show each day as a block with times and inline context from event descriptions. This populates `{{week_calendar_overview}}` in the text brief:

```
Monday, March 30 — Creative Day
  10:00–12:00   Tiera Kennedy content edit
                Rough cut review — selects due before Wednesday

Friday, April 3 — Business Dev Day
  All-day        Tiera Kennedy — Greenhouse Sessions Release
                 Milestone day. Have promo content ready. Check socials, share the work.
```

### Template Variables

| Variable | Content |
|----------|---------|
| `{{verse}}` | Optional KJV/NIV verse. Omit if nothing fits. |
| `{{week_start_date}}` | Sunday of the week being planned |
| `{{run_context}}` | "Planning Next Week" or "This Week Update" |
| `{{week_calendar_overview}}` | Day-by-day with times, context, milestone notes |
| `{{work_priorities}}` | Top work tasks and deliverables |
| `{{personal_this_week}}` | Personal commitments, birthdays, anniversaries, family events |
| `{{errands_this_week}}` | Floating errand pool |
| `{{goal_suggestions}}` | 1 suggestion per uncovered goal. Omit if all covered + silent. |
| `{{flagged_items}}` | Items needing a human decision |
| `{{upcoming_beyond_this_week}}` | Key items 2–4 weeks out |
| `{{draft_count}}` | Proposed calendar blocks. Omit if zero. |

---

## Step 10 — Propose Calendar Blocks

Every proposed item must have a **specific day, date, and time window** — no exceptions. This applies to every single block: work tasks, personal reminders, errands, calls. All of them.

**Required format:** `Day Month Date   HH:MM–HH:MM   Description`

**NOT acceptable:** "By end of day", "morning", "afternoon", "evening", "sometime Saturday", "when free". These are vague and will not work for calendar creation. Every block needs an actual clock time like `10:00–10:30am` or `6:00–7:00pm`.

For personal reminders (e.g. "Book anniversary dinner"), pick a realistic time window — e.g. `10:00–10:30am` if it's a Saturday morning task, or `7:00–8:00pm` for an evening booking call. Never leave it as "by end of day."

Show each proposal as a structured block. The confirmation question at the end is **REQUIRED** — never omit it:

```
Proposed for your calendar:
  ✦  Mon March 30   9:00–10:00am    Tiera Kennedy selects — deliver via Dropbox
  ✦  Tue March 31   10:30–11:00am   YouTube Foundry follow-up — email Pierre
  ✦  Thu April 2    1:00–1:30pm     Prospecting call — retainer client outreach

Add these to your calendar? You can adjust times before confirming.
(yes / some / no — or tell me which ones and I'll update the times)
```

**The two lines after the blocks are mandatory every time:**
- `Add these to your calendar? You can adjust times before confirming.`
- `(yes / some / no — or tell me which ones and I'll update the times)`

Never end the proposed blocks without these two lines.

**Time-picking logic:**
- For each item, look at the day's existing calendar blocks and find a realistic open window
- Apply day type rules (Creative = before 3pm for creative tasks, Admin = Thu, calls = any day)
- Factor in realistic durations — don't suggest a 15-min window for a 2-hour task
- If two items compete for the same slot, spread them across different days
- If no slot is available this week, propose it for the following week (`weekOffset: 1`) instead of only surfacing it in COMING UP NEXT. The dashboard's "Week After" view makes next-week proposals actionable.

**Editable fields:** These map directly to the dashboard form fields (Step 10b below).

---

## Step 10b — Generate Dashboard HTML

After producing the proposed blocks, generate an interactive HTML dashboard file.

> ### ⚠️ CRITICAL — DO NOT REBUILD THE DASHBOARD TEMPLATE
>
> The dashboard's HTML, CSS, and JavaScript are **fully owned** by `dashboard-template.html`. Your job in this step is **placeholder substitution only** — replace each `{{PLACEHOLDER}}` token with the value you computed in Steps 4–9. You MUST NOT:
> - Read `dashboard-template.html` into the conversation (it is ~100KB and will poison context).
> - Write, edit, or emit any HTML, CSS, or `<script>` content yourself.
> - Regenerate, "clean up," reformat, or restructure any section of the template.
> - Recreate the dashboard from memory if the file appears missing or partial.
>
> The **only** acceptable mechanism for producing the weekly brief HTML is the on-disk Python substitution script in **Step 10b-ii**. Do not use the Edit tool, the Write tool, or an in-context string replacement as a substitute — those paths let the model drift into regenerating the template and are the historical source of the "rebuild" bug.
>
> **If `dashboard-template.html` is missing or unreadable:** STOP. Tell the user: *"Dashboard template not found at `<path>`. Fort Abode manages this file — please open Fort Abode and re-run the Weekly Rhythm Module setup to restore it."* Do not generate a replacement.
>
> **If Python-via-Bash is unavailable in this environment:** STOP. Tell the user: *"This environment can't run the dashboard substitution script, so I can't produce the HTML brief here. Run the skill from Claude Code or Claude Desktop instead."* Do not inline-replace placeholders or write HTML from memory.

**Template location:** `dashboard-template.html` in the shared Weekly Rhythm iCloud folder (same directory as this spec file). The Python script in Step 10b-ii opens it directly from disk — you never read it into the conversation.

**Output file:** `{icloud_path}/dashboards/weekly-brief-{YYYY-MM-DD}.html`

Create the `dashboards/` directory if it doesn't exist. This keeps generated output separate from config files and makes it easy to browse past weeks. Each user gets their own dashboards folder (Kam → `Kamren/dashboards/`, Tiera → `Tiera/dashboards/`) — always write to the detected user's path, never a hardcoded one.

**Cowork fallback:** If `{icloud_path}` is not writable (sandbox), write to the session outputs directory instead and note in the run output: "Dashboard saved to Cowork outputs (iCloud path unavailable). Copy to your Weekly Rhythm dashboards folder after the session."

**Inject ALL of these values into the template:**

| Placeholder | Replace with |
|-------------|-------------|
| `{{WEEK_OF}}` | Sunday of the week being planned, e.g. `March 29, 2026` |
| `{{GENERATED_ON}}` | Day + date + time generated, e.g. `Generated Fri, Mar 27, 2026 · 7:42 AM` |
| `{{RUN_CONTEXT}}` | `Planning Next Week` or `This Week Update` or `Week 13 · Q1 2026` |
| `{{BRIEF_CONTENT}}` | Structured HTML highlights — one `<div class="bct-line">` per day with colored dots and 1-line summaries. See Step 9, "Brief Content — Structured Highlights" for the exact HTML format. Do NOT inject the full weekly brief text here — only the structured day-by-day snapshot. |
| `{{PROPOSED_BLOCKS_JSON}}` | JSON array of proposed new calendar blocks (see format below) |
| `{{EXISTING_EVENTS_JSON}}` | JSON array of events already confirmed on Google Calendar for the full 30-day window |
| `{{REMINDERS_JSON}}` | JSON array of proposed new reminders and errands (see format below) |
| `{{REMINDER_LISTS_JSON}}` | JSON array of reminder list names from Apple Reminders, e.g. `["Inbox","Kam Studios","Personal","Errands","Groceries","Home","Family","Ideas","Systems"]` |
| `{{INBOX_TRIAGE_JSON}}` | JSON array of proposed Inbox triage routing decisions (see INBOX_TRIAGE_JSON format below) |
| `{{WEEKLY_TRIAGE_JSON}}` | JSON array of weekly triage items: overdue tasks, pending invites, unscheduled tasks (see WEEKLY_TRIAGE_JSON format below) |
| `{{DAY_NARRATIVES_JSON}}` | JSON object keyed by ISO date → string narrative for each day of the week |
| `{{WEEK_GOALS_JSON}}` | JSON array of weekly goals with `id`, `label`, `description`, `relatedTypes` |
| `{{PROJECTS_JSON}}` | JSON array of active Notion projects for the Project Pulse strip (see format below) |
| `{{LOCATION_INTEL_JSON}}` | JSON object with travel itineraries, commute warnings, errand routes, and lunch suggestions (from Step 5g). Empty object `{}` if Step 5g was skipped. |
| `{{UPDATE_BANNER_JSON}}` | JSON object with `{version, title, summary, notes, dismissed}` for the update banner (from Step 1d). `null` if no banner should display this run. |
| `{{DAY_TYPES_JSON}}` | JSON array of `{id, label, color, exclusive}` from `config.day_types` (from Step 2e). |
| `{{FAMILY_MESSAGES_JSON}}` | JSON array of inbound family messages (from Step 5h). Empty array `[]` if `family_sync_enabled` is false or no messages exist. |
| `{{PROPOSED_FAM_MSGS_JSON}}` | JSON array of proposed outbound family message drafts (from Step 6c). Empty array `[]` if disabled or no candidates. |
| `{{RUN_REPORT_JSON}}` | JSON object with `runId`, `versions` (5-string), `mcpHealth`, `dataPulled`, `status`, `errors`, `warnings` (from Step 13). Powers the Run Health pill. |

---

### Step 10b-ii — Template substitution method (MANDATORY)

**This is the only acceptable path for generating the dashboard HTML.** See the "DO NOT REBUILD" banner at the top of Step 10b — that banner governs this step. The goal of this method is not just context efficiency; it is drift prevention. When the template bytes pass through the conversation, the model reliably corrupts them. Keeping the template on disk and substituting with a Python script sidesteps that entire failure mode.

**Do NOT read `dashboard-template.html` into the conversation under any circumstances.** Not with the Read tool, not via `cat`, not via any inline approach. The script below opens it directly from disk.

Write all placeholder values to a JSON file, then run the Python script that performs the substitution on disk:

**1. Write the placeholders file** to `{icloud_path}/dashboards/.placeholders-{YYYY-MM-DD}.json` containing all 19 placeholder key-value pairs as a JSON object. Keys are the placeholder names without curly braces (e.g. `"WEEK_OF"`, `"BRIEF_CONTENT"`, `"PROPOSED_BLOCKS_JSON"`, `"UPDATE_BANNER_JSON"`, `"FAMILY_MESSAGES_JSON"`, `"DAY_TYPES_JSON"`, `"PROPOSED_FAM_MSGS_JSON"`, `"RUN_REPORT_JSON"`, etc.). Values are the fully-formed strings ready for injection — JSON arrays and objects should be serialized as strings.

**2. Run this Python script via Bash:**

```python
import json, sys, os

icloud_base = sys.argv[1]  # Weekly Rhythm root (e.g. ~/...Kennedy Family Docs/Weekly Rhythm)
user_path = sys.argv[2]    # User folder (e.g. ~/...Weekly Rhythm/Kamren)
date_str = sys.argv[3]     # ISO date (e.g. 2026-04-13)

# Read template (from Weekly Rhythm root, not user folder)
with open(os.path.join(icloud_base, 'dashboard-template.html'), 'r') as f:
    html = f.read()

# Read placeholders
ph_path = os.path.join(user_path, 'dashboards', f'.placeholders-{date_str}.json')
with open(ph_path, 'r') as f:
    placeholders = json.load(f)

# Replace all placeholders
for key, value in placeholders.items():
    html = html.replace('{{' + key + '}}', str(value))

# Write output
out_dir = os.path.join(user_path, 'dashboards')
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, f'weekly-brief-{date_str}.html')
with open(out_path, 'w') as f:
    f.write(html)

# Clean up placeholders file
os.remove(ph_path)
print(f'Dashboard written to {out_path} ({os.path.getsize(out_path)} bytes)')
```

**3. Verify** the script's stdout confirms the file was written and check the byte count is reasonable (should be ~100KB+).

**Important:** The engine must produce all 19 placeholder values and write them to the JSON file BEFORE running the script. If any placeholder is missing, the template will render with raw `{{PLACEHOLDER}}` text. Double-check the JSON file has all keys from the table above. Use `null` for `UPDATE_BANNER_JSON` when no banner should display, and `[]` for the `*_JSON` arrays when their feature is disabled — never omit the key.

---

### Proposed blocks JSON format (PROPOSED_BLOCKS_JSON)

Each block is a NEW proposed calendar event (not yet on the calendar). Blocks now have a `proposalType` that determines how they render in the dashboard.

#### Standard proposal example:
```json
{
  "id": 1,
  "proposalType": "standard",
  "dayLabel": "Wed Apr 8",
  "title": "Upload RS shoot selects to Dropbox",
  "date": "2026-04-08",
  "startTime": "09:00",
  "endTime": "11:00",
  "taskType": "creative",
  "isNew": true,
  "proposalReason": "Wednesday is your creative recovery day after the shoot. Getting selects uploaded first thing means you can start reviewing with fresh eyes by midday.",
  "projectName": "RS Editorial Shoot",
  "projectArea": "Kam Studios"
}
```

#### Direction proposal example:
```json
{
  "id": 2,
  "proposalType": "direction",
  "dayLabel": "Tue Apr 7",
  "title": "cmdshft Retainer — Next Move",
  "date": "2026-04-07",
  "startTime": "14:00",
  "endTime": "15:00",
  "taskType": "bizdev",
  "isNew": true,
  "proposalReason": "Pierre has been responsive in email but the retainer conversation hasn't moved to a formal proposal yet.",
  "projectName": "cmdshft Retainer",
  "projectArea": "Kam Studios",
  "options": [
    {"label": "Casual scope call", "description": "Call Pierre to align on scope before writing anything.", "tradeoff": "Faster, builds rapport, but may delay formal close."},
    {"label": "Send formal proposal", "description": "Draft a retainer proposal doc with scope and pricing.", "tradeoff": "Professional and clear, but takes 2+ hours to draft."},
    {"label": "Email scope outline", "description": "Send a rough outline via email, ask for feedback.", "tradeoff": "Low effort, keeps momentum, but less polished."}
  ],
  "recommended": 0,
  "questions": ["Has Pierre mentioned a preferred format for proposals?", "What retainer value range are you targeting?"],
  "researchFindings": "Found 3 email threads with Pierre from March. Last email (Mar 28): Pierre asked about 'monthly content packages.' No formal proposal has been sent yet."
}
```

#### Transition buffer example:
```json
{
  "id": 3,
  "proposalType": "transition",
  "dayLabel": "Thu Apr 9",
  "title": "Transition: Creative → Admin",
  "date": "2026-04-09",
  "startTime": "12:00",
  "endTime": "12:15",
  "taskType": "transition",
  "isNew": true,
  "proposalReason": "Switching from creative work to admin tasks. Take a moment to reset — close creative files, grab water, review your admin checklist."
}
```

Fields:
- **id** — unique integer
- **proposalType** — `"standard"` | `"direction"` | `"transition"` (determines dashboard rendering)
- **dayLabel** — short label e.g. `"Mon Mar 30"` (for card display)
- **title** — event title
- **date** — `YYYY-MM-DD`
- **startTime / endTime** — `HH:MM` 24-hour
- **taskType** — one of `creative | admin | bizdev | personal | errand | transition`
- **isNew** — always `true` for proposed blocks
- **proposalReason** — 1–2 sentence explanation. Be specific and contextual, not generic.
- **projectName** — the Notion project this proposal is connected to (empty string if none)
- **projectArea** — the Area the project belongs to (empty string if none)
- **weekOffset** — `0` for the primary planning week, `1` for the following week. The engine proposes blocks for the following week when: (a) this week is full, (b) a task's Do Date falls next week, or (c) the user explicitly requests it. Dashboard uses this to filter proposals by view.
- **options** — (direction proposals only) array of `{label, description, tradeoff}`. First item is the recommended option.
- **recommended** — (direction proposals only) index of the recommended option (usually `0`)
- **questions** — (direction proposals only) array of strings — things the engine needs to know
- **researchFindings** — (direction proposals only) string summarizing what the engine found during research

---

### Existing events JSON format (EXISTING_EVENTS_JSON)

Events already confirmed on Google Calendar — shown in the week planner. Draggable so the user can reschedule. If `attendeeCount` > 1, a styled warning modal appears before applying the move.

```json
[
  {"id": "ex-1", "title": "Team standup", "date": "2026-03-30", "startTime": "08:00", "endTime": "08:30", "attendeeCount": 1},
  {"id": "ex-2", "title": "Tiera Kennedy — review session", "date": "2026-03-30", "startTime": "14:00", "endTime": "16:00", "attendeeCount": 3}
]
```

`attendeeCount` — number of attendees on the event (including organizer). Populate from the Google Calendar event's `attendees` array length.

---

### Reminders JSON format (REMINDERS_JSON)

Proposed new reminders and errands (not yet in Apple Reminders):

```json
[
  {
    "id": 1,
    "title": "Review Tiera Kennedy color grades",
    "list": "Kam Studios",
    "dueDate": "2026-03-30",
    "dueTime": "11:00",
    "priority": "high",
    "notes": "Check contrast on indoor shots",
    "flagged": true,
    "category": "Work",
    "isNew": true,
    "proposalReason": "Color grade review needs to happen before the afternoon session — flagged high so it surfaces at the top of your list."
  }
]
```

Fields:
- **id** — unique integer (separate number space from proposedBlocks)
- **title**, **list**, **dueDate**, **dueTime**, **priority** (`none|low|medium|high`), **notes**, **flagged**, **category** (`Work|Personal|Errand|Creative`)
- **isNew** — always `true` for proposed reminders
- **proposalReason** — same as for calendar blocks: specific, contextual, 1–2 sentences

---

### Inbox Triage JSON format (INBOX_TRIAGE_JSON)

Proposed routing for items currently in Apple Reminders Inbox (or any Triage-category list). Each item gets exactly one proposed route. The user approves or rejects each individually in the dashboard.

```json
[
  {
    "id": "triage-1",
    "title": "Add Fort Abode Utility Central to Notion Projects",
    "currentList": "Inbox",
    "notes": "",
    "isOverdue": false,
    "dueDate": null,
    "route": "notion_task",
    "routeTarget": "Notion Tasks DB",
    "routeReason": "This describes creating a new project entry — better tracked as a Notion Task.",
    "notionProject": "Fort Abode",
    "proposedTaskTitle": "Add Fort Abode Utility Central to Notion Projects",
    "proposedTaskDueDate": "2026-04-18"
  },
  {
    "id": "triage-2",
    "title": "Pick up dry cleaning",
    "currentList": "Inbox",
    "notes": "",
    "isOverdue": false,
    "dueDate": null,
    "route": "errand",
    "routeTarget": "Errands",
    "routeReason": "Physical errand — routing to Errands list where it joins the floating errand pool."
  },
  {
    "id": "triage-3",
    "title": "Find Onewheel contact info",
    "currentList": "Inbox",
    "notes": "",
    "isOverdue": true,
    "dueDate": "2026-04-11",
    "route": "move_to_list",
    "routeTarget": "Personal",
    "routeReason": "Quick action — personal item, not project work."
  },
  {
    "id": "triage-4",
    "title": "Research LED panel options",
    "currentList": "Inbox",
    "notes": "For the studio upgrade",
    "isOverdue": false,
    "dueDate": null,
    "route": "keep_inbox",
    "routeTarget": "Inbox",
    "routeReason": "Could be a project task or a one-off purchase — needs more context from you before routing."
  }
]
```

Fields:
- **id** — unique string prefixed with `triage-`
- **title** — original reminder title
- **currentList** — the Triage-category list name (e.g., "Inbox")
- **notes** — original reminder notes (may be empty)
- **isOverdue** — `true` if the item has a past due date
- **dueDate** — `YYYY-MM-DD` or `null`
- **route** — one of `"notion_task"` | `"move_to_list"` | `"errand"` | `"keep_inbox"` | `"complete"`
- **routeTarget** — destination list name, or `"Notion Tasks DB"` for notion_task route
- **routeReason** — 1–2 sentence explanation of why this route was chosen
- **notionProject** — (notion_task only) the Notion project name to link the task to
- **proposedTaskTitle** — (notion_task only) cleaned-up title for the Notion task
- **proposedTaskDueDate** — (notion_task only) proposed due date, `YYYY-MM-DD`

---

### Weekly Triage JSON format (WEEKLY_TRIAGE_JSON)

Items requiring weekly triage decisions — overdue tasks, pending calendar invites, and tasks needing time blocks. The user approves, dismisses, or modifies each in the dashboard. Accepted items with time blocks bridge into the `bs` (proposed blocks) state on the week grid.

**Dedup rule:** If a triage item has a `proposedBlock`, do NOT also generate a separate entry in `PROPOSED_BLOCKS_JSON` for the same item. The triage card owns it — when the user accepts the triage item, the dashboard bridges it into the week grid automatically. Duplicating across both arrays creates confusion (two cards for one action). If the triage item's `proposedBlock` is accepted, it appears on the grid via the triage bridge — never via a standalone proposed block.

```json
[
  {
    "id": "triage-overdue-1",
    "type": "overdue_task",
    "title": "Review Fort Abode PR",
    "source": "notion",
    "sourceId": "page-uuid-here",
    "projectName": "Fort Abode",
    "currentDoDate": "2026-04-08",
    "dueDate": "2026-04-15",
    "daysOverdue": 3,
    "riskLevel": "critical",
    "proposedNewDate": "2026-04-14",
    "proposedBlock": {"day": "Mon", "start": "10:00", "end": "12:00"},
    "duration": 120,
    "energyLevel": "deep",
    "reason": "3 days overdue with a Due Date in 4 days — reschedule to Monday morning deep focus slot."
  },
  {
    "id": "triage-invite-1",
    "type": "pending_invite",
    "title": "Design Review with Client",
    "calendarId": "kamren@kamstudios.com",
    "eventId": "abc123def",
    "start": "2026-04-14T14:00:00",
    "end": "2026-04-14T15:00:00",
    "organizer": "client@example.com",
    "attendeeCount": 4,
    "recommendation": "accept",
    "reason": "Aligns with Fort Abode milestone this week. Organizer is a priority contact.",
    "cascadeEffects": [
      {"blockTitle": "Deep Focus: Fort Abode", "action": "shift", "from": "14:00", "to": "15:30"}
    ]
  },
  {
    "id": "triage-fusion-1",
    "type": "needs_time_block",
    "title": "Write project proposal",
    "source": "notion",
    "sourceId": "page-uuid-here",
    "projectName": "Weekly Rhythm Engine",
    "duration": 90,
    "energyLevel": "deep",
    "category": "Work",
    "proposedBlock": {"day": "Tue", "start": "09:00", "end": "10:30"},
    "reason": "Deep focus task matched to Tuesday Creative morning. 90-min gap available."
  }
]
```

Fields (all types):
- **id** — unique string prefixed with `triage-overdue-`, `triage-invite-`, or `triage-fusion-`
- **type** — `"overdue_task"` | `"pending_invite"` | `"needs_time_block"`
- **title** — task or event title
- **reason** — 1–2 sentence explanation

Fields (overdue_task):
- **source** — `"notion"` or `"reminder"`
- **sourceId** — Notion page ID or reminder identifier
- **projectName** — connected project name (empty string if none)
- **currentDoDate** — the original Do Date that is now past, `YYYY-MM-DD`
- **dueDate** — the hard deadline (Due Date), `YYYY-MM-DD` or `null`
- **daysOverdue** — integer, days past currentDoDate
- **riskLevel** — `"critical"` | `"warning"` | `"low"` (based on dueDate proximity)
- **proposedNewDate** — `YYYY-MM-DD` suggested reschedule date
- **proposedBlock** — `{day, start, end}` or `null` if no duration info
- **duration** — minutes, or `null` if unknown
- **energyLevel** — `"deep"` | `"moderate"` | `"light"` or `null`

Fields (pending_invite):
- **calendarId** — which Google Calendar the event is on
- **eventId** — Google Calendar event ID (needed for RSVP)
- **start** / **end** — ISO datetime strings
- **organizer** — organizer email
- **attendeeCount** — integer
- **recommendation** — `"accept"` | `"tentative"` | `"decline"`
- **cascadeEffects** — array of `{blockTitle, action, from, to}` showing what would move if accepted. Empty array if no conflicts.

Fields (needs_time_block):
- **source** — `"notion"` | `"email"` | `"reminder"` | `"imessage"` (any source that surfaces an unscheduled action item)
- **sourceId** — Notion page ID, Gmail message ID, or empty string
- **projectName** — connected project name (empty string if standalone)
- **duration** — minutes (estimate if not from Notion Duration field)
- **energyLevel** — `"deep"` | `"moderate"` | `"light"`
- **category** — `"Work"` | `"Personal"` | `"Errand"` | `"Creative"`
- **proposedBlock** — `{day, start, end}` with the suggested time slot

If no items qualify for weekly triage, use an empty array `[]`. The dashboard handles the empty state.

---

### Day narratives JSON format (DAY_NARRATIVES_JSON)

```json
{
  "2026-03-30": "Creative day — priority is getting the Tiera Kennedy selects finalized before the 2pm review session.",
  "2026-03-31": "Business dev push — YouTube Foundry thread needs a reply, lunch with Marcus is an open door for the retainer pitch."
}
```

A 1–3 sentence summary for each day. Shown under the day's date in the Day-by-Day Breakdown.

---

### Week goals JSON format (WEEK_GOALS_JSON)

```json
[
  {"id": "g1", "label": "Delivery", "description": "Finalize + deliver Tiera Kennedy selects", "relatedTypes": ["creative"]},
  {"id": "g2", "label": "Retainer Growth", "description": "Send 2nd retainer pitch this month", "relatedTypes": ["bizdev"]}
]
```

**relatedTypes** controls which day goal tags appear — values are the same as `taskType` in proposed blocks.

---

### Projects JSON format (PROJECTS_JSON)

Active Notion projects for the Project Pulse strip and detail modals. Sourced from the Notion queries in Step 5b. Includes context-richness classification and research findings for thin/new projects.

```json
[
  {
    "id": "proj-1",
    "name": "RS Editorial Shoot",
    "area": "Kam Studios",
    "stage": "In Progress",
    "nextAction": "Confirm crew and call sheet",
    "nextActionDue": "2026-04-06",
    "thisWeekTasks": 3,
    "isOverdue": false,
    "isStalled": false,
    "taskType": "creative",
    "contextRichness": "rich",
    "tasks": [
      {"title": "Confirm crew availability", "dueDate": "2026-04-05", "status": "In Progress"},
      {"title": "Finalize call sheet", "dueDate": "2026-04-05", "status": "Not started"},
      {"title": "Pack gear loadout", "dueDate": "2026-04-05", "status": "Not started"}
    ],
    "notes": "Viviane Feldman confirmed 2x Burano + FX9 + FX3. Eric Brouse: slog3/sgamut3.cine.",
    "researchFindings": ""
  },
  {
    "id": "proj-2",
    "name": "cmdshft Retainer",
    "area": "Kam Studios",
    "stage": "Pitching",
    "nextAction": "Follow up with Pierre on retainer terms",
    "nextActionDue": "2026-04-08",
    "thisWeekTasks": 1,
    "isOverdue": false,
    "isStalled": false,
    "taskType": "bizdev",
    "contextRichness": "thin",
    "tasks": [
      {"title": "Send retainer terms", "dueDate": "2026-04-08", "status": "Not started"}
    ],
    "notes": "",
    "researchFindings": "Found 3 email threads with Pierre from March. Last email (Mar 28): Pierre asked about 'monthly content packages.' No formal proposal sent yet."
  }
]
```

Fields:
- **id** — unique string identifier (e.g. `"proj-1"`, `"proj-2"`)
- **name** — project title from Notion
- **area** — the Area this project belongs to (e.g. "Kam Studios", "Personal")
- **stage** — current project stage (free text from Notion, e.g. "In Progress", "Planning", "Wrap")
- **nextAction** — the project's Next Action field from Notion (1 line, truncated if long)
- **nextActionDue** — `YYYY-MM-DD` or empty string if no due date
- **thisWeekTasks** — count of tasks for this project due or scheduled this week
- **isOverdue** — `true` if Next Action Due is past today
- **isStalled** — `true` if no activity in the last 21 days (from config `stale_project_threshold`)
- **taskType** — one of `creative | admin | bizdev | personal | errand` (maps to day type colors)
- **contextRichness** — `"rich"` | `"thin"` | `"new"` (from Step 5b classification)
- **tasks** — array of `{title, dueDate, status}` for this week's tasks. Shown in the Project Pulse detail modal.
- **notes** — project notes string (from Notion Notes field). Can be empty.
- **researchFindings** — summary of what the engine found during Step 5b research. Empty string for rich-context projects.

If no active projects exist, use an empty array `[]`. The dashboard handles the empty state.

---

**How to generate the dashboard file:** Follow **Step 10b-ii** above — that is the single source of truth for dashboard generation. Build the JSON arrays and objects from Steps 4–9, write them to the placeholders file, and run the Python substitution script. Do **not** read the template into the conversation; do **not** emit HTML yourself. (See the "DO NOT REBUILD" banner at the top of Step 10b.)

**After the script writes the file, immediately open it in the default browser:**
```
open {user_path}/dashboards/weekly-brief-{YYYY-MM-DD}.html
```

This is mandatory — never skip it. Kam (or the detected user) expects the dashboard to appear automatically.

**When Kam pastes back the `WEEKLY RHYTHM UPDATE — Week of...` output:**
- Parse `ADD TO GOOGLE CALENDAR` section → call `gcal_create_event` for each
- Parse `ADD / UPDATE IN APPLE REMINDERS` section → create/update each in Apple Reminders
- Parse `RESCHEDULED` section → call `gcal_update_event` for each
- Parse `UPDATED DAY TYPES` → store in memory for future planning context
- Parse `INBOX TRIAGE` section → for each approved triage item:
  - `Route: Create Notion Task` → create task in Notion Tasks DB (linked to named Project if specified), then complete the original Inbox reminder via `complete_reminder`
  - `Route: Move to [List]` → call `update_reminder(name, list_name="Inbox", new_list_name="[target list]")`
  - `Route: Complete` → call `complete_reminder`
  - `Route: Keep in Inbox` → no action needed, log only
- Parse `WEEKLY TRIAGE` section → for each approved triage item:
  - `RESCHEDULE` lines (overdue_task): update the Notion Task's Do Date via `notion-update-page`, and if a time block was accepted, create a Google Calendar event via `gcal_create_event`
  - `RSVP` lines (pending_invite): call `gcal_respond_to_event` with the user's decision (`accepted`, `tentative`, or `declined`) and the event's `calendarId` + `eventId`
  - `SCHEDULE` lines (needs_time_block): create a Google Calendar event via `gcal_create_event` for the accepted time block
  - If any triage item has a `Msg:` line, read it first — it may override the proposed action
- If any item has a `Msg:` line → read it before actioning that item; it may change what you do (e.g. "skip this week", "move to Thursday", "different list")
- Confirm all changes with Kam after processing

---

## Step 11 — Update Memory and Timestamp

After every run, perform both updates:

### 11a — Update `last_run` in config.md

Read `{icloud_path}/config.md`, set `last_run:` to the current ISO timestamp, write back.

```
last_run: 2026-03-28T08:42:00-06:00
```

This sets the window for the next Gmail pull (`since_last_run`).

**Fallback (when config.md is not writable — e.g. Cowork sandbox):** Store the timestamp in Memory MCP so it's not lost:

```
aim_memory_add_facts — entity: "Weekly_Rhythm_Config", entityType: "config"
- "last_run: 2026-04-13T12:00:00-05:00"
```

**On the next run (Step 5, before Gmail pull):** If `last_run` is missing or stale in config.md, check Memory MCP:
```
aim_memory_get — names: ["Weekly_Rhythm_Config"]
```
Parse the `last_run` fact and use it for the Gmail window. If found in both config.md and Memory MCP, use whichever is more recent.

### 11b — Update Kam Memory MCP

Call `aim_memory_add_facts` with meaningful, non-routine facts from this run. Memory MCP is the sole persistent memory destination — the shared state bus between the Weekly Engine and the upcoming Daily Brief system.

**Always store:**
- New clients or contacts encountered
- Goal progress updates (moved forward, stalled, blocked)
- Decisions made during this session (project direction chosen, items triaged)
- Patterns noticed (e.g., "Kam consistently moves admin tasks off Creative days")
- Inbox triage outcomes (what was routed where — helps calibrate future triage)
- Weekly triage outcomes (overdue reschedules, RSVP decisions, fusion blocks created — helps calibrate future triage)
- Completed milestones or deliveries

**Never store:**
- Routine calendar events already in Google Calendar
- The full brief contents
- Reminder items already in Apple Reminders
- Anything the engine can re-derive from source systems next run

**Date bracketing for time-sensitive facts:** Prefix with `[2026-04-11]` for day-specific items or `[Apr 2026]` for monthly context. This helps the Daily Brief system filter relevant vs stale facts.

Examples of good facts:
- "[2026-04-06] Rolling Stone Nashville cover shoot completed — Viviane Feldman contact, 10-hour 3-camera shoot"
- "[Apr 2026] cmdshft retainer goal: Pierre responded positively, formal proposal pending"
- "[2026-04-11] Inbox triage: 'FINN Partners follow-up' routed to Notion as project task; 'Onewheel contact' moved to Personal"
- "Retainer client goal (Q2 2026): no progress this week — outreach suggested"
- "[2026-04-11] Weekly triage: 3 overdue tasks rescheduled, 2 invites accepted (Design Review, Client Call), 1 task fused to calendar (proposal draft → Tue 9am)"

### 11b-ii — Triage History (dedup for future runs)

After the user confirms triage decisions, store a compact triage log in Memory MCP:

```
aim_memory_add_facts — entity: "Triage_History"
- "[2026-04-11] Accepted: 'Check pitch filter' rescheduled to Tue Apr 14 11:30am"
- "[2026-04-11] Accepted: 'Penske Media registration' scheduled Wed Apr 15 2:00pm"  
- "[2026-04-11] Dismissed: 'Chase Visa payment' — user handling separately"
- "[2026-04-11] Calendar created: 6 events for week of Apr 12"
```

**On every subsequent run (Step 5):** Before generating WEEKLY_TRIAGE_JSON, query Memory MCP for `Triage_History`. For each potential triage item:
1. Check if it was already triaged in a prior run (match by title + source)
2. If it was **accepted** and a calendar event was created → skip it (already handled)
3. If it was **dismissed** → skip it (user chose to ignore it)
4. If it was **accepted but the task is still incomplete** (overdue again) → re-surface with note: "Previously rescheduled on [date] — still incomplete"
5. If it's genuinely new → include it normally

This prevents the engine from re-proposing items the user already dealt with. It also enables efficiency tracking — over time, the engine can report: "You've rescheduled this item 3 times. Should we drop it or break it into something smaller?"

### 11b-iii — Efficiency Insights (progressive)

After 4+ weeks of runs, Memory MCP will have enough triage history to surface patterns:
- Items that get repeatedly rescheduled → suggest breaking them down or dropping them
- Day types that consistently get overridden → suggest changing the default schedule  
- Tasks that always get moved off Creative days → auto-propose on Admin days instead
- Average proposals accepted vs dismissed → calibrate how many to generate

Surface these as a "Rhythm Insights" section in the brief when meaningful patterns emerge (not every run).

**Graceful degradation:** If Memory MCP is unavailable, log a warning in the brief output: "Memory MCP was unreachable — facts from this run were not stored. They will be re-derived on next run." Do not fall back to memory.md.

---

## Step 11d — Process Location Intelligence Actions

When the user pastes the Confirm & Copy output back, check for these location-specific action sections:

### TRAVEL ITINERARY actions
If the output contains `TRAVEL ITINERARY:` with a confirmed itinerary:
1. Create an Apple Note using `add_note` with the `appleNoteTitle` and `appleNoteBody` from the itinerary object
2. If a pack/prep block was accepted, create the calendar event via `gcal_create_event`
3. Store the itinerary in Memory MCP: `aim_memory_add_facts(entity: "Travel_History", contents: ["[date] Travel: origin → destination, departed HH:MM"])`
4. **Family sync (if `family_sync_enabled` is true and the user checked `share_with_partner` on the itinerary card):** Write an outbound message to `{partner_icloud_path}/messages/inbox/{ISO}-{currentUser}-travel.md` with the itinerary summary, destination, dates, and R&B drop-off info. Frontmatter: `from: {currentUser}, category: travel, urgency: normal, subject: "{trip_name} itinerary"`. Body: human-readable itinerary (a markdown rendering of the steps array). Memory MCP log: `aim_memory_add_facts(entity: "Family_Message_Log", contents: ["[date] Sent travel itinerary to {partner}: {trip_name}"])`.

### LUNCH CHOICE actions
If the output contains `LUNCH CHOICE:` with a selected restaurant:
1. Optionally create a 1-hour calendar event: title = "Lunch — {restaurant_name}", location = restaurant address, time = 12:00–1:00pm (or user-specified)
2. This is informational — only create the event if the user explicitly checked "Add to calendar" on the lunch card

### ERRAND ROUTE actions
If the output contains `ERRAND ROUTE:` with a confirmed route:
1. Create a single calendar event for the full errand block: title = "Errands — {stop_count} stops", start = departTime, end = returnTime, description = ordered stop list with drive times
2. Mark each errand reminder as completed if the user checked them off

### COMMUTE WARNING actions
Commute warnings are informational only — no actions to process. They inform the user's scheduling decisions but don't create any events.

---

## Step 12 — Feedback Loop

> "Anything off? I can adjust."

Classify feedback: immediate vs persistent. Show proposed config/memory changes before applying. Log to Memory MCP under the relevant project entity.

---

## Step 12b — Compose and Send Family Messages

**Prerequisite:** `family_sync_enabled: true` in config.

When the user pastes back the dashboard output and it contains a `FAMILY MESSAGE COMPOSE:` section (emitted by the dashboard's compose UI or the proposed-messages accept flow), parse each queued message and write it to the partner's inbox.

**Format expected from dashboard:**
```
FAMILY MESSAGE COMPOSE:
  to: Tiera
  category: travel
  urgency: normal
  subject: Atlanta trip itinerary
  action_items:
    - Drop R&B at Mom's by 7:30am Thursday
  body: |
    Heads up — flying to Atlanta Thursday morning. R&B will go to Mom's at 7:30am.
```

**For each queued message:**
1. Determine the partner's iCloud path. Check `family_partners[].icloud_path` in config. If missing, fall back to `~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Weekly Rhythm/{partner_name}/`.
2. Ensure `{partner_path}/messages/inbox/` exists; create if needed.
3. Generate the filename: `{ISO-timestamp}-{currentUser}-{category}.md` (e.g. `2026-04-14T08:42:00-kam-travel.md`).
4. Write the file with frontmatter:
   ```markdown
   ---
   from: {currentUser}
   timestamp: {ISO-timestamp}
   category: {category}
   urgency: {urgency}
   subject: {subject}
   status: unread
   read_at: null
   action_items: {action_items_yaml_list}
   ---

   {body}
   ```
5. Log to Memory MCP:
   ```
   aim_memory_add_facts(entity: "Family_Message_Log", contents: [
     "[{date}] Sent to {partner}: {subject} ({category})"
   ])
   ```
6. If voice-triggered (the original prompt was spoken via Siri or a voice MCP), play a brief audio confirmation: "Message sent to {partner}."

**Voice trigger detection:** The dashboard's compose UI may emit a `voice_confirm: true` field per message. If true, attempt audio confirmation via the macOS `say` command or any TTS MCP available.

**Failure handling:** If the partner's inbox path is unwritable, store the message in Memory MCP under `Family_Message_Outbox` as a pending message and surface it in next run's brief: "1 family message couldn't be delivered last run — retry?"

---

## Step 13 — Write Run Report

**Prerequisite:** `diagnostics_enabled: true` in config (default `true`).

Throughout the pipeline, collect telemetry into a `runReport` accumulator. After Step 12 (feedback loop) completes, write the report to disk and emit it as `RUN_REPORT_JSON` for the dashboard's Run Health pill and diagnostics modal.

**Telemetry collected during the run:**
- `runId` — UUID generated at Step 1 start
- `user` — from `config.name`
- `timestamp` — ISO timestamp of run start
- `environment` — `"desktop" | "cowork" | "claude_code"` (detected from working dir / agent context)
- `versions` — all 5 version strings (drift detection compares them):
  - `engineSpec` — from line 1 header of this file
  - `dashboardTemplate` — from line 1 header of `dashboard-template.html`
  - `skillWrapper` — from skill wrapper file header (or `"unknown"` if not embedded)
  - `configTemplate` — from `template_version:` in config.md
  - `fortAbodeApp` — from `Fort_Abode_App_Version` in Memory MCP if available, else `"unknown"`
- `status` — `"ok" | "warning" | "error"`
- `durationSeconds` — wall-clock time from Step 1 start to Step 12 end
- `weekPlanned` — Sunday of the planned week, e.g. `"2026-04-12"`
- `mcpHealth` — array from Step 2a probes:
  ```json
  [
    {"name": "google-calendar", "status": "ok", "probeMs": 320},
    {"name": "google-maps", "status": "ok", "probeMs": 215},
    {"name": "imessage", "status": "missing", "probeMs": null}
  ]
  ```
- `dataPulled` — counts:
  ```json
  {
    "calendarEvents": 47,
    "reminders": 23,
    "gmailMessages": 18,
    "notionTasks": 31,
    "memoryFacts": 12,
    "mapsApiCalls": 14,
    "familyMessages": 3
  }
  ```
- `errors` — array of `{step, message, recoverable}` for any non-fatal errors during the run
- `warnings` — array of strings (e.g., "iMessages MCP unavailable — context enrichment skipped")

**Write to disk:**
1. `{icloud_path}/diagnostics/runs/{runId}.json` — full structured report
2. `{icloud_path}/diagnostics/runs/{runId}.md` — short human-readable summary (1 paragraph + version table)

Create `{icloud_path}/diagnostics/runs/` if it doesn't exist.

**Set `RUN_REPORT_JSON`** = the full JSON object above for template substitution. The dashboard's Run Health pill reads this and shows:
- Overall status (✓ green / ⚠ yellow / ✗ red)
- All 5 versions with drift detection (any mismatch → "Version drift detected")
- MCP health list
- Data counts
- Error / warning list

**Drift detection:** If any of the 5 versions don't match the latest released version (from Fort Abode bundle or Memory MCP `Fort_Abode_App_Version` entity), the pill shows a "Version drift detected" warning naming each out-of-sync string.

**Graceful degradation:** If `{icloud_path}/diagnostics/runs/` is not writable (Cowork sandbox), write the JSON to Memory MCP under `Run_Reports` entity instead. The dashboard still renders from `RUN_REPORT_JSON` regardless.

**Cleanup policy:** Keep the last 30 run reports. Delete older `.json` and `.md` files in `diagnostics/runs/` when count exceeds 30.

---

## Protected Day Output Format

```
━━━━━━━━━━━━━━━━━━━━━━
  [Weekday], [Date]
  Personal Day
━━━━━━━━━━━━━━━━━━━━━━

TODAY
  → [task due today]

OVERDUE
  → [overdue task] (due [day])

━━━━━━━━━━━━━━━━━━━━━━
```

If nothing on the list: "Rest up. Nothing on the list." — then stop.
