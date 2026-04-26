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
- App shows Accept/Decline. (Phase 5b: write-back of acceptance state — out of scope for this round.)

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
- `isDone` toggle is local-only at v4.1.0 — Phase 5b will sync.

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

- **Write-back state**: when the user accepts a proposal or moves an event in the app, that mutation needs to flow back to the engine. Phase 5b adds a sibling `dashboard-{ISODate}-pending.json` written by the app and consumed by the engine on next run. Spec for that file lives in a follow-up doc.
- **Full month view**: the 30-day grid currently uses a separate mocked path. JSON shape for that is Phase 5d.
- **Run-Health detail**: today the app shows a single pill. Detailed component-by-component health (versions, MCP up/down) lives in `ComponentListViewModel` and isn't part of this snapshot.

---

## Testing the contract

Until the engine emits real JSON, you can hand-craft a file matching this shape and drop it at the expected path to test the wire. Fort Abode's `MockWeeklyRhythmDataSource` is a useful reference — its `static let` arrays are the same shape, just hardcoded.
