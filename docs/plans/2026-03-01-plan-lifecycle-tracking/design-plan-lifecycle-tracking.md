# Plan Lifecycle Tracking & Completion Reports

## Problem

The plan document is write-once today. After writing-plans creates it, it's never updated — the plan doesn't reflect what actually happened. When returning to a multi-phase project days later, there's no record of what was completed, what deviated, or what the next phase needs to know.

## Solution

Make the plan doc a **living document** with three additions:

1. **Frontmatter status** — overall status line and per-phase/task checklist with completion tracking
2. **Completion section** — written by the orchestrator after execution, summarizing what was done
3. **Implementation-review updates** — the reviewer reads the completion notes, appends its own changes, and writes handoff notes directly into future phase sections

All phases live in a single plan doc. The frontmatter checklist provides a scannable overview; agents read specific sections as needed. One doc avoids cross-referencing problems that splitting would create.

## Where Each Piece Gets Written

| Who | When | What they write |
|-----|------|----------------|
| **writing-plans** | Plan creation | Frontmatter with `status: Not Yet Started`, phase/task checklist |
| **Orchestrator** (subagent-driven-development) | During & after execution | Flips status to `In Development`, checks off tasks, appends `## Completion Report` section |
| **Implementation-review** | After review pass | Updates completion section with fixup changes, writes handoff notes into future phase sections |
| **Orchestrator** (at end) | After final review passes | Flips phase status to `Complete (YYYY-MM-DD)`, flips overall status if all phases done |

## Plan Doc Structure

```markdown
---
status: Not Yet Started | In Development | Complete (YYYY-MM-DD)
---

# Feature Name

## Phases

### Phase 1 — Core API
**Status:** Not Yet Started | In Development | Complete (YYYY-MM-DD)

- [ ] Task 1: Set up routes
- [ ] Task 2: Add validation

### Phase 2 — Frontend
**Status:** Not Yet Started

- [ ] Task 3: Build components
- [ ] Task 4: Wire up API

## Task Details
(existing plan content — specs, file paths, verification commands)
```

### After Phase 1 Execution and Review

```markdown
---
status: In Development
---

# Feature Name

## Phases

### Phase 1 — Core API
**Status:** Complete (2026-03-01)

- [x] Task 1: Set up routes
- [x] Task 2: Add validation

### Phase 2 — Frontend
**Status:** Not Yet Started

> **Handoff from Phase 1:**
> - API endpoints return `{data, meta}` not `{result}` — update fetch calls accordingly
> - Auth middleware was added in Phase 1; wire into Phase 2 routes

- [ ] Task 3: Build components
- [ ] Task 4: Wire up API

## Task Details
(existing plan content)

---

## Completion Report — Phase 1
**Completed:** 2026-03-01

### Summary
Brief narrative of what was built. 2-3 sentences covering the scope delivered.

### Deviations from Plan
- **Task 1 — Changed X to Y**: Reason why. Impact: affected files A, B.
- **Added Task 1b — Unplanned middleware**: Discovered during Task 1 that Z was needed. Impact: new file C.

### Implementation Review Changes
- Fixed inconsistent port config across modules (reviewer fixup)
- Extracted duplicated timeout constant to shared config
```

## Plan Doc Directory Convention

Plan documents are organized in per-topic folders under `docs/plans/`:

```
docs/plans/
  YYYY-MM-DD-topic/
    design-topic.md
    plan-topic.md
```

**File naming:** `{design|plan}-{topic}.md`

- `design-` prefix for design docs (output of brainstorming)
- `plan-` prefix for implementation plans (output of writing-plans)
- One plan doc per topic, containing all phases

**Skills affected:** brainstorming (writes design docs) and writing-plans (writes plan docs) need their output path conventions updated to use this structure.

## Skills Modified

### 1. brainstorming

Update output path convention:

- Create topic folder `docs/plans/YYYY-MM-DD-<topic>/` if it doesn't exist
- Write design doc as `design-<topic>.md` inside that folder
- Previously: `docs/plans/YYYY-MM-DD-<topic>-design.md` (flat)

### 2. writing-plans

Update output path convention and generate lifecycle frontmatter:

- Write plan doc into the topic folder created by brainstorming: `docs/plans/YYYY-MM-DD-<topic>/`
- Name as `plan-<topic>.md`
- All phases go in one document
- Previously: `docs/plans/YYYY-MM-DD-<feature-name>.md` (flat)
- Add `status: Not Yet Started` to frontmatter
- Add `**Status:** Not Yet Started` line under each phase heading
- Generate task checklist with unchecked boxes under each phase
- All statuses initialized to `Not Yet Started`

### 3. subagent-driven-development

Three new behaviors during execution:

- **On first task start:** Flip overall frontmatter status to `In Development`, flip current phase status to `In Development`
- **On each task completion:** Check off the task (`- [ ]` to `- [x]`) in the phase checklist
- **After all tasks complete:** Append a `## Completion Report — Phase N` section containing:
  - **Summary** — what was built (2-3 sentences)
  - **Deviations from Plan** — each deviation with what changed, why, and impact on files/scope

### 4. implementation-review (reviewer-prompt.md)

Two new behaviors after the review pass:

- **Document fixups:** Append an `### Implementation Review Changes` subsection to the completion report documenting what the reviewer changed during fixups
- **Write handoff notes:** For multi-phase plans, write handoff notes directly into the next phase's section as a blockquote before the task list — things the next phase's agent needs to know (API shape changes, new dependencies, scope adjustments)

## What This Does NOT Add

- No new skill file — changes are to four existing skills
- No new subagent — the orchestrator writes the completion section inline (it has the execution context)
- No separate completion document — everything lives in the plan doc
- No changes to plan-review or ship
