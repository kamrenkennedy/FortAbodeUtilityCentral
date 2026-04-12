---
name: weekly-rhythm-engine
description: >
  The strategic engine for Kam's week — work and personal life in one unified rhythm. Runs on Fridays to plan the full coming week, and on-demand anytime something changes. Synthesizes all Google Calendars, Apple Reminders, and Gmail into a clean weekly brief shaped by day types, goals, errands, and milestone awareness.

  Trigger this skill for: "run my weekly rhythm", "set up my week", "what's my plan for the week", "run the rhythm engine", "plan my week", "what do I have going on this week", "update my week", or any variation of wanting a structured weekly planning view. Also trigger for first-time setup when no user config exists.
---

# Weekly Rhythm Engine — Skill Wrapper

This is a thin wrapper. The full engine specification lives in a shared iCloud folder managed by Fort Abode, enabling soft updates without reinstalling the skill.

## Step 0 — Load Engine Spec

Before doing anything else, read the full engine specification:

```
Read: ~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Claude/Weekly Flow/engine-spec.md
```

If the file is not found, check alternate paths:
```
Glob: ~/Library/Mobile Documents/com~apple~CloudDocs/*/Claude/Weekly Flow/engine-spec.md
```

If still not found, fall back to the bundled spec in this skill's directory:
```
Read: {skill_root}/engine-spec-fallback.md
```

Once the spec is loaded, follow all steps in it exactly. The spec contains:
- Step 1: User detection + setup state
- Step 2: Smart first-run + incremental setup
- Steps 3-12: Full engine pipeline (calendar, reminders, Gmail, Notion, triage, proposals, dashboard generation, memory updates)

## Quick Reference

| What | Where |
|------|-------|
| Engine spec | `~/...iCloud.../Kennedy Family Docs/Claude/Weekly Flow/engine-spec.md` |
| Dashboard template | `~/...iCloud.../Kennedy Family Docs/Claude/Weekly Flow/dashboard-template.html` |
| User config | `~/...iCloud.../Kennedy Family Docs/Claude/Weekly Flow/{UserName}/config.md` |
| User memory | `~/...iCloud.../Kennedy Family Docs/Claude/Weekly Flow/{UserName}/memory.md` |
| Generated dashboards | `~/...iCloud.../Kennedy Family Docs/Claude/Weekly Flow/{UserName}/weekly-brief-*.html` |

All files in the shared iCloud folder are synced across machines. Fort Abode manages `engine-spec.md` and `dashboard-template.html` (updates them on new versions). User files (`config.md`, `memory.md`, dashboards) are never overwritten.
