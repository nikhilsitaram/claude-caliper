---
name: plan-review
description: Use when a plan has been written and before execution begins
---

# Plan Review

Dispatch an Opus subagent to validate a plan before execution. Catches issues that are cheap to fix in a plan but expensive to fix mid-implementation.

**Core principle:** Plans are hypotheses. Validate before running the experiment.

## When to Use

- After draft-plan produces a plan directory
- Before orchestrate begins
- When resuming work on an idle plan (context may have drifted)

**Skip for:** Single-task plans, hotfix plans, trivially small plans (no design doc needed).

## Dispatch

Two-stage review:

**Stage 1: Structural validation** — Run `scripts/validate-plan --schema {PLAN_DIR}/plan.json`. If errors, report them and stop. No point dispatching LLM reviewer for structurally invalid plans.

**Stage 2: Prose + design review** — If schema passes, dispatch Opus subagent.

Gather inputs:
- **Plan directory** — `docs/plans/YYYY-MM-DD-topic/` (containing plan.json + task .md files)
- **Design doc** — if one exists (or "None")
- **Repo root** — the worktree the plan targets

Dispatch with `model: "opus"` — consistency checking requires strong reasoning.

**See:** reviewer-prompt.md

## What It Catches

### Structural Validation (schema check)

Handled by `validate-plan --schema`:
- Missing required fields (goal, architecture, tech_stack, phases, tasks)
- Invalid status values (plan/phase/task status)
- Duplicate task IDs or phase letters
- Dependency cycles and forward dependencies
- Duplicate file paths in creates lists
- Task file existence (phase-{letter}/{task_id_lower}.md)
- H1 header matching task name
- Missing phase completion files
- Empty success_criteria run commands
- Missing expect fields

### Prose + Design Review (LLM reviewer)

| Category | Example | Why Planners Miss It |
|----------|---------|---------------------|
| Artifact drift | Creates `utils.ts`, imports from `helpers.ts` | Renamed during planning without updating refs |
| Design mismatch | Design says REST, plan implements GraphQL | Diverged during decomposition |
| Missing tasks | Design specifies auth middleware, no auth task | Lost during decomposition |
| Implied context | "Modify the handler" without specifying file | Planner has context executor won't |
| Missing fields | No verification command or measurable done | Assumes executor will figure it out |
| Prose completeness | Steps too vague or avoid sections missing reasoning | Assumes executor will fill gaps |
| Different Claude Test | Task references "the handler" without path | Planner has context executor won't |
| Phase boundary issues | 9 tasks in single phase, no verification gates | Didn't apply complexity gates |
| Orphaned criteria | Design says "users can X" but no task verifies it | Lost during decomposition |

## 7-Point Checklist

1. **Dependency Ordering** — *(schema validates graph; LLM checks semantic coherence)*
2. **Artifact Consistency** — Same file/function/variable referenced with same name everywhere *(LLM focus)*
3. **Design Doc Alignment** — Scope, architecture, tech stack match design (skip if no design doc) *(LLM focus)*
4. **Test-Implementation Coherence** — TDD structure intact, Task 0 present (or justified skip), signatures match *(LLM focus)*
5. **Completeness** — *(schema validates field presence; LLM checks prose quality)*
6. **Different Claude Test** — Each task executable by fresh Claude with zero context *(LLM focus)*
7. **Success Criteria Coverage** — Every criterion in the design doc maps to at least one task's "done when" field (skip if no design doc) *(LLM focus)*

**For multi-phase plans:**
- Phase boundaries at meaningful verification points *(schema validates completion.md exists)*
- Complexity gates respected (8+ tasks → needs phasing, 7+ per phase → examine cut points)
- Interface-first ordering (contracts defined before implementations)

## Output

Reviewer produces:
- Issues Found (category, tasks involved, what's wrong, suggested fix)
- Assessment (issue count, severity breakdown, ready for execution?)

**Pass:** Zero issues, or all issues fixed and confirmed clean
**Fail:** Return to draft-plan to fix, then re-run plan-review

**Re-review gate:** If the reviewer finds more than 5 issues, after all fixes, dispatch a fresh reviewer with the same full scope to confirm clean. Under 5 issues, verify fixes and proceed.

## Integration

**Auto-dispatched by:** draft-plan (after plan saved)

**Leads to:** orchestrate (once review passes)
