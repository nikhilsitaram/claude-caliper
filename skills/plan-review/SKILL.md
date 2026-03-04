---
name: plan-review
description: Use when a plan has been written and before execution begins
---

# Plan Review

Dispatch an Opus subagent to validate a plan before execution. Catches issues that are cheap to fix in a plan but expensive to fix mid-implementation.

**Core principle:** Plans are hypotheses. Validate before running the experiment.

## When to Use

- After writing-plans produces a plan document
- Before orchestrating begins
- When resuming work on an idle plan (context may have drifted)

**Skip for:** Single-task plans, hotfix plans, trivially small plans (no design doc needed).

## Dispatch

Gather inputs:
- **Plan file** — `docs/plans/YYYY-MM-DD-topic/plan-topic.md`
- **Design doc** — if one exists (or "None")
- **Repo root** — the worktree the plan targets

Dispatch with `model: "opus"` — consistency checking requires strong reasoning.

**See:** reviewer-prompt.md

## What It Catches

| Category | Example | Why Planners Miss It |
|----------|---------|---------------------|
| Dependency ordering | Task 4 imports util created in Task 6 | Thinks about tasks as units, not sequence |
| Artifact drift | Creates `utils.ts`, imports from `helpers.ts` | Renamed during planning without updating refs |
| Design mismatch | Design says REST, plan implements GraphQL | Diverged during decomposition |
| Missing tasks | Design specifies auth middleware, no auth task | Lost during decomposition |
| Implied context | "Modify the handler" without specifying file | Planner has context executor won't |
| Missing fields | No verification command or measurable done | Assumes executor will figure it out |
| Phase boundary issues | 9 tasks in single phase, no verification gates | Didn't apply complexity gates |

## 6-Point Checklist

1. **Dependency Ordering** — Everything a task USES is CREATED by a prior task or exists in codebase
2. **Artifact Consistency** — Same file/function/variable referenced with same name everywhere
3. **Design Doc Alignment** — Scope, architecture, tech stack match design (skip if no design doc)
4. **Test-Implementation Coherence** — TDD structure intact, Task 0 present (or justified skip), signatures match
5. **Completeness** — All 5 task fields present (Files, Verification, Done, Avoid+WHY, Steps), commands runnable
6. **Different Claude Test** — Each task executable by fresh Claude with zero context

**For multi-phase plans, also verify:**
- Phase boundaries at meaningful verification points
- Complexity gates respected (8+ tasks → needs phasing, 7+ per phase → examine cut points)
- Interface-first ordering (contracts defined before implementations)

## Output

Reviewer produces:
- Issues Found (category, tasks involved, what's wrong, suggested fix)
- Assessment (issue count, severity breakdown, ready for execution?)

**Pass:** Zero issues, or all issues fixed and confirmed clean
**Fail:** Return to writing-plans to fix, then re-run plan-review

**Re-review gate:** If the reviewer finds more than 5 issues, after all fixes, dispatch a fresh reviewer with the same full scope to confirm clean. Under 5 issues, verify fixes and proceed.

## Integration

**Auto-dispatched by:** superpowers:writing-plans (after plan saved)

**Leads to:** superpowers:orchestrating (once review passes)
