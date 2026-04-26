# Dashboard JSON shape — engine ↔ Fort Abode contract

This document specifies the JSON file the Weekly Rhythm engine emits each run alongside its existing `dashboard-{ISODate}.html`. The Fort Abode Mac app reads this file via `FileBackedWeeklyRhythmDataSource` to render the Weekly Rhythm tab.

**Status:** spec-first. Fort Abode v4.1's Phase 5a ships the consumer side. The engine doesn't emit JSON yet — adding it is a separate task on the `weekly-rhythm` repo.

---

## File path

```
~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Weekly Flow/{userName}/dashboards/dashboard-{ISODate}.json
```

- `userName` is the same folder the engine writes its config + dashboard HTML to (e.g. `Kamren`, `Tiera`).
- `ISODate` is the **Monday** of the week the dashboard covers, in `yyyy-MM-dd` format (e.g. `dashboard-2026-04-21.json` for the week of Apr 21–27).
- Write atomically: emit `dashboard-{ISODate}.json.tmp` first, then `mv` to the final filename. This avoids the app reading a half-written file.

The engine should write the JSON file in lock-step with its HTML output — same trigger, same data. The HTML is for cross-Mac/web preview; the JSON is for native consumption.

---

## Fallback behavior

If the JSON file is missing, unreadable, or fails to decode, the Fort Abode app silently falls back to its mock data and logs the reason via `ErrorLogger`. The user never sees an error sheet. This is by design — on Tiera's machine (where no engine has run yet), the app shows the same UI Kam's machine shows.

The moment a valid JSON file appears at the expected path, the app picks it up on the next view appearance with no code change or user action.

---

## Top-level shape

The file is a single JSON object matching `WeeklyRhythmSnapshot` (`FortAbodeUtilityCentral/Models/WeeklyRhythm.swift`). Every field is required unless noted otherwise; JSONDecoder is configured with `.iso8601` date decoding.

```json
{
  "weekMetadata": { ... },
  "todaysBrief": { ... } | null,
  "pulseProjects": [ ... ],
  "alerts": [ ... ],
  "weekDays": [ ... ],
  "triage": [ ... ],
  "proposals": [ ... ],
  "errands": [ ... ],
  "dayBreakdown": [ ... ],
  "runHealth": { ... },
  "generatedAt": "2026-04-25T12:00:00Z"
}
```

---

## Field by field

### `weekMetadata`

```json
{ "eyebrow": "Week 17", "title": "April 21 — 27" }
```

- `eyebrow` — short label for the editorial header eyebrow row. Engine-derived from week-of-year.
- `title` — date range string for the editorial title. Engine-formatted; the app does not parse this.

### `todaysBrief` (nullable)

```json
{
  "dayType": "move",
  "label": "Today · Thursday April 24",
  "narrative": "Ship pass 3 of Braxton edit, then prep for Tiera's birthday window.",
  "weekGoalsComplete": 3,
  "weekGoalsTotal": 5
}
```

- `dayType` — one of `"make" | "move" | "recover" | "admin" | "open"`. Today's day-type.
- `label` — display string the app shows above the narrative.
- `narrative` — single-paragraph orientation for the day. The engine generates this; the app does not summarize.
- `weekGoalsComplete` / `weekGoalsTotal` — for the progress bar. Engine derives from week goals + completion state.
- Set to `null` when the requested week is not the current week.

### `pulseProjects`

Array of project cards in the horizontal Project Pulse strip.

```json
{
  "id": "proj-braxton",
  "status": "review",
  "statusLabel": "In review",
  "title": "Braxton edit",
  "touched": "Touched 4h ago",
  "action": "Pass 3 → client today"
}
```

- `id` — stable across regenerations so the app can preserve selection state.
- `status` — one of `"scheduled" | "draft" | "review" | "error" | "neutral"`. Drives the status dot color.
- `statusLabel` — display label for the status (e.g. "Blocked" maps to `error`).
- `title` — project name.
- `touched` — relative recency string. App displays verbatim.
- `action` — next-action one-liner. App displays verbatim.

### `alerts`

```json
{
  "id": "alert-saturday-travel",
  "kind": "travel",
  "day": "Saturday",
  "title": "Gallery drop-off — 12 PM downtown",
  "detail": "18 min drive each way. Plan a 30 min buffer for parking + load-in.",
  "actionLabel": "View itinerary"
}
```

- `kind` — one of `"travel" | "commuteConflict" | "errandBatch" | "lunch"`. Drives the icon and the urgent-vs-warm underglow color (commuteConflict → urgent rust glow; others → warm amber).
- `actionLabel` — optional. When present, renders an outlined button on the alert card.

### `weekDays`

Seven entries, Mon→Sun. Each:

```json
{
  "id": "wd-thu",
  "name": "Thu · today",
  "num": "24",
  "dayTypes": ["move", "recover"],
  "isToday": true,
  "events": [ ... ],
  "nowLineHour": 13.5
}
```

- `dayTypes` — array (the app stores as a Set). Determines which day-type pills render.
- `events` — array of events on the week-grid timeline (see below).
- `nowLineHour` — only set when `isToday: true`. Decimal hour (e.g. `13.5` = 1:30 PM) of the "now" line position.

### `weekDays[].events`

```json
{
  "id": "ev-thu-braxton3",
  "startHour": 10.0,
  "endHour": 12.0,
  "time": "10 AM — 12 PM",
  "title": "Braxton edit · pass 3",
  "kind": "regular"
}
```

- `startHour` / `endHour` — decimal hours, **not pixels**. The app multiplies by `hourScale` (configurable via the zoom slider) to compute pixel positions.
- `time` — optional display label inside the event block. App falls back to its own formatter if absent.
- `kind` — one of `"regular" | "accent" | "errand"`. Drives fill color and styling.

### `triage`

```json
{
  "id": "tri-marisol",
  "status": "error",
  "title": "Re: Downtown Gallery — proof timing?",
  "meta": "Marisol · client · 2h ago"
}
```

- Same `status` enum as `pulseProjects.status`.
- `meta` — sender · category · recency.

### `proposals`

```json
{
  "id": "prop-move-sync",
  "title": "Move Braxton sync from Tue to Fri",
  "reasoning": "You asked earlier today. Same call link, same duration."
}
```

- Engine generates these from changes since the last run + Claude's plan.
- App shows Accept/Decline. Acceptance state flows back via the **pending mutations file** documented below; the engine drains it on its next run.

### `errands`

```json
{
  "id": "err-amazon",
  "title": "Return Amazon package",
  "location": "Downtown · 12 min",
  "daysPending": 2,
  "routedTo": "Mon · post office",
  "isDone": false
}
```

- `daysPending` ≥ 14 triggers the brand-rust nudge pill.
- `routedTo` is null for unrouted errands; the app shows "Unrouted" in that case.
- `isDone` toggle is queued via the pending mutations file — engine should mark the matching Apple Reminder complete on next drain.

### `dayBreakdown`

Seven entries, Mon→Sun. The "blocks + focus bar" pattern.

```json
{
  "id": "db-thu",
  "weekday": "Thu",
  "dateLabel": "Apr 24",
  "dayType": "move",
  "headline": "Ship day",
  "summary": "2h · 1 sync",
  "blocks": [ ... ],
  "isToday": true,
  "isPast": false
}
```

**New engine work required:**

- `headline` — short verb-phrase summarizing the day. Possible heuristic: "longest focus block's title" trimmed + verb-form. The user-facing name for the day (~3-6 words). Optional but strongly encouraged.
- `summary` — short string for the focus-bar's right gutter. Possible format: total focus hours + count of secondary items, e.g. `"3h · 1 sync"`, `"light · 1 err"`, `"—"` for empty days.

### `dayBreakdown[].blocks`

```json
{
  "id": "blk-thu-ship",
  "title": "Ship Braxton pass 3",
  "kind": "focus",
  "startHour": 10.0,
  "endHour": 12.0,
  "durationLabel": "10–12 · 2h",
  "timeLabel": null,
  "tag": "move",
  "dim": false
}
```

**New engine work required:**

- `kind` — one of `"focus" | "errand" | "sync" | "admin" | "recover" | "note"`. Drives the focus-bar segment style (full-height vs half-height, color).
- `tag` — one of `"admin" | "make" | "move" | "errand" | "sync"` or null. Drives the small uppercase chip. Note: the tag taxonomy and the dayType taxonomy share names but have different semantics — a Make day can have a Sync block.
- `dim: true` — for soft notes like `"No errands routed"` (block-row title renders in onSurfaceVariant).
- `startHour` / `endHour` — only required for blocks that should render on the focus bar. Notes/admin without a time can omit them.
- `durationLabel` vs `timeLabel` — `durationLabel` for spans (`"45m"`, `"10–1 · 3h"`); `timeLabel` for point-in-time entries (`"3:00 PM"`). At most one.

### `runHealth`

One of:

```json
"allGood"
```

```json
{ "warning": "Drift in component versions" }
```

```json
{ "error": "iCloud not reachable" }
```

The app pill renders status icon + label.

### `generatedAt`

ISO-8601 timestamp. The app shows "real" or "mock" status keyed off this; freshness checks (e.g. "stale snapshot, regenerate") are deferred to Phase 5c.

---

## Heuristics for the new engine fields

The engine already computes most of the inputs. The new fields (`headline`, `summary`, `kind`, `tag`) need light derivation logic. Suggested:

- **`block.kind`**:
  - Block came from a `proposedBlocks` entry with `taskType: "creative"` → `focus`
  - Block came from a `proposedBlocks` entry with `taskType: "admin"` → `admin`
  - Block came from `existingEvents` and category contains "sync"/"meeting"/"call" → `sync`
  - Block came from `allReminders` with `category: "Errand"` → `errand`
  - Block came from `dayNarratives` text-only items → `note`
  - Otherwise → `admin`

- **`block.tag`**: usually mirrors `kind` capitalized except `focus` blocks split into `make`/`move` based on the day's `dayType`:
  - Day is `make` + block kind `focus` → tag `make`
  - Day is `move` + block kind `focus` → tag `move`
  - Otherwise tag matches kind (admin/sync/errand)

- **`headline`**: if the day has exactly one focus block, use a verb-form of its title (e.g. "Ship pass 3 of Braxton" → "Ship day"). Two-or-more focus blocks → "Deep block + {short noun for the second item}". Recover days → describe the recovery activity. Open days → "No scheduled blocks".

- **`summary`**: total focus hours + counts. Examples:
  - 3h focus + 1 sync → `"3h · 1 sync"`
  - 2h focus + 1 errand → `"2h · 1 err"`
  - Recover day with one errand → `"light · 1 err"`
  - Open day → `"—"`

These heuristics are starting points — the engine team can iterate without breaking the consumer.

---

## What's NOT in this shape (yet)

- **Full month view**: the 30-day grid currently uses a separate mocked path. JSON shape for that is Phase 5d.
- **Run-Health detail**: today the app shows a single pill. Detailed component-by-component health (versions, MCP up/down) lives in `ComponentListViewModel` and isn't part of this snapshot.

---

## Pending mutations file (Phase 5b — write-back)

When the user mutates state in the app — drag-reschedule an event, mark an errand done, accept or decline a proposal — Fort Abode persists that mutation immediately so it survives across app restarts and engine runs that haven't drained yet. Mutations route to one of three destinations depending on kind:

| Mutation | Destination | Why |
|----------|-------------|-----|
| `dayTypeChange` | `{user}/config.md` (surgical edit to the `## Day Types` section) | Day-types are user config. Engine reads config.md on every run already. |
| `errandReorder` | App-local `~/Library/Application Support/FortAbodeUtilityCentral/weekly-rhythm-ui-state.json` | Pure UI sort order. Engine has no concept of errand ordering. Never crosses the iCloud boundary. |
| `errandDoneToggle`, `eventMove`, `proposalAccept`, `proposalDecline` | Sibling `dashboard-{ISODate}-pending.json` (this file) | Engine owns the durable state — Apple Reminders for errands, Google Calendar for events, Memory MCP + Notion/GCal for proposals. |

### File path

```
~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Weekly Flow/{userName}/dashboards/dashboard-{ISODate}-pending.json
```

Sibling of the engine's `dashboard-{ISODate}.json`. Same `userName` and `ISODate` (Monday of the target week).

### File shape

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
    },
    {
      "id": "FE7A1B22-...",
      "appliedAt": "2026-04-26T14:32:01Z",
      "mutation": {
        "kind": "eventMove",
        "eventID": "ev-thu-braxton3",
        "newDayIndex": 4,
        "newStartHour": 14.0,
        "newEndHour": 16.0
      }
    },
    {
      "id": "27B5C903-...",
      "appliedAt": "2026-04-26T14:33:55Z",
      "mutation": {
        "kind": "proposalAccept",
        "proposalID": "prop-move-sync"
      }
    }
  ]
}
```

- `schemaVersion` — currently `1`. Bump on breaking changes; the engine should refuse to drain a file with an unknown version and log a warning.
- `weekISODate` — Monday of the target week. Must match the sibling `dashboard-{ISODate}.json`.
- `createdAt` — when the file was first written. Useful for staleness detection.
- `mutations[]` — ordered append-only list. Each entry has a stable `id` (UUID, app-generated), an `appliedAt` timestamp (when the user took the action), and a `mutation` payload tagged with `kind`.

### Mutation kinds

#### `errandDoneToggle`

```json
{ "kind": "errandDoneToggle", "errandID": "err-amazon", "isDone": true }
```

Engine action: locate the matching Apple Reminder (by ID or by title match if the engine's internal ID space differs from the dashboard JSON's), mark it complete (or incomplete if `isDone: false`).

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

- `newDayIndex` — column index in the snapshot's `weekDays` array (0..6, in the engine's emitted order).
- `newStartHour` / `newEndHour` — decimal hours, snapped to half-hour grid by the app.

Engine action: call `gcal_update_event` with the new start/end. Compute the absolute date by anchoring to the week's Monday + adding `newDayIndex` days.

#### `proposalAccept` / `proposalDecline`

```json
{ "kind": "proposalAccept", "proposalID": "prop-move-sync" }
```

Engine action:
- Write `Family_Message_Calibration` Memory MCP fact (engine-spec.md §11d) so future runs weight similar proposals.
- For `proposalAccept`: execute the side-effect described in the proposal's `proposedBlock` (Notion task update via `notion-update-page`, GCal event creation via `gcal_create_event`, etc. — whatever the engine spec §10c calls for).
- For `proposalDecline`: just record the decision, no side-effect.

### Engine drain protocol

At the start of each run, the engine should:

1. Glob for `{user}/dashboards/dashboard-*-pending.json`.
2. For each file:
   - Decode. Refuse on unknown `schemaVersion` (log a warning, skip).
   - For each mutation entry, apply to the appropriate destination.
   - On success: rename the file to `dashboard-{ISODate}-pending.applied-{ISO_TIMESTAMP}.json` (do NOT delete — leaves a 30-day audit breadcrumb).
   - On any per-entry failure: leave the file in place, log the failure with the entry's `id` so subsequent runs can retry. Don't block the rest of the run.
3. Continue with the normal run, now reading the updated source-of-truth (Reminders, GCal, Memory MCP).

### Atomicity

The app writes via `Data.write(options: .atomic)` which does `.tmp` + rename under the hood. The engine should drain the file after reading the entire contents (no partial-read concerns) and rename atomically too.

### What the app does with this file on load

To make optimistic UX survive app restarts and engine runs that haven't drained yet, `FileBackedWeeklyRhythmDataSource.fetch(weekOffset:)` runs:

1. Read engine JSON → base snapshot (or fall back to mock if missing).
2. Read pending file. For each mutation, replay onto the base snapshot via `MutationApplier.apply(_:to:)`.
3. Read app-local UI state (errand sort order). Apply.
4. Return the composed snapshot.

So:
- App applies a mutation → snapshot mutates immediately + pending file gets the entry → next load re-applies the same mutation on top of whatever the engine is emitting → user-visible state is consistent.
- Engine drains pending file → renames to `…-pending.applied-{ISO}.json` → next app load doesn't replay anything (file is gone) → new engine snapshot is the source of truth.
- Engine fails to drain (Reminders MCP down, GCal API hiccup) → pending file stays → app keeps replaying → user keeps seeing their intent.

### Until the engine adopts this protocol

Mutations queue indefinitely in the pending file and stay visually applied (correct UX). The user can clear stale mutations manually by deleting the file — the app doesn't expose this in the UI yet (advanced operation, deferred to Phase 5d).

---

## Testing the contract

Until the engine emits real JSON, you can hand-craft a file matching this shape and drop it at the expected path to test the wire. Fort Abode's `MockWeeklyRhythmDataSource` is a useful reference — its `static let` arrays are the same shape, just hardcoded.
