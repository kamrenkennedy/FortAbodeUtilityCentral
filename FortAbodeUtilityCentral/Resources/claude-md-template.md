<!-- Fort Abode Template v1.0 — Do not remove this line -->
# Claude Instructions

## Session Protocol

### Starting a Session
1. Check **Memory MCP** for the relevant project entity — has current status, recent decisions, what's next
2. Check **Deep Context** for the latest session summary (search by project name)
3. **Ask what to work on** — don't assume
4. If the project CLAUDE.md has additional session-start steps, follow those too

### Ending a Session (mandatory)
At the end of every session where meaningful work was done — any topic, any project — perform a session wrap before closing out:

1. **Memory MCP** (`aim_memory_store` or `aim_memory_add_facts`) — update the relevant project entity with current status, what was done, what's next, and key file locations. Remove stale observations that are no longer accurate.
2. **Deep Context** (`aim_deep_store`) — store a session summary with full narrative: what happened, decisions made, current state, how to resume.
3. Both systems must be current — they are the only things that follow you across machines.

Don't wait to be asked. After finishing the main work, proactively run the session wrap. If the session is being cut short, prioritize the memory update over finishing extra tasks.

**Note:** A settings.json hook enforces this — Claude will be prompted to run the session wrap at the end of every conversation automatically.

## Memory MCP Usage

- Memory MCP and Deep Context MCP are always available — use both
- Memory = quick facts, project status, current state (knowledge graph)
- Deep Context = session narratives, decision logs, detailed context (long-form)
- When starting a new session, search both if prior work is referenced
- Progressively build up context about preferences, patterns, and workflow habits — write to memory when you learn something reusable

## Decision-Making

- Present all viable options with tradeoffs — let the user choose
- Suggestions must be concrete, implementation-focused steps — never random time-fillers
- Every suggestion should tie to a real project, goal, or deliverable

## Notion

- Always use database templates (template_id) when creating Notion pages — never blank pages

## Add Your Own Sections Below

<!-- Add personal preferences, coding style, Notion template IDs, project-specific rules, etc. below this line -->
