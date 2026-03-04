---
name: orchestrating
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrating

Execute plan by dispatching fresh subagent per task, with two-stage review after each: spec compliance review first, then code quality review.

**Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration

## When to Use

- Have an implementation plan with mostly independent tasks
- Tasks can be dispatched one at a time to fresh subagents
- Don't use for tightly coupled tasks or when no plan exists

## The Process

**Per task:** Dispatch implementer → spec compliance review → code quality review → mark complete

**After all tasks (per phase for multi-phase):** Write completion report → verify Task 0 integration tests → implementation review → handoff notes (if more phases) → next phase or ship

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./implementer-prompt.md` | Dispatch implementer subagent |
| `./spec-reviewer-prompt.md` | Spec compliance reviewer |
| `./code-quality-reviewer-prompt.md` | Code quality reviewer |
| `skills/implementation-review/reviewer-prompt.md` | Final implementation reviewer |

## Example Workflow

```text
[Read plan once, extract all tasks, create TaskCreate for each]

Task 0: Broad integration tests
[Dispatch implementer] → Creates failing tests + stubs, commits
[Spec + code review pass] → Mark complete

Task 1: Hook installation
[Dispatch implementer]
Implementer: "Should hook be user or system level?"
You: "User level (~/.config/)"
Implementer: Implemented, 5/5 tests pass, committed
[Spec review: ✅] → [Code review: ✅] → Mark complete

Task 2: Recovery modes
[Dispatch implementer] → Implemented, 8/8 tests pass
[Spec review: ❌ Missing progress reporting, extra --json flag]
[Implementer fixes] → [Spec review: ✅]
[Code review: ❌ Magic number]
[Implementer extracts constant] → [Code review: ✅]
Mark complete

[After all tasks]
[Write completion report into plan doc]
[Verify Task 0 tests now GREEN]
[Implementation review] → Found duplicated constant
[Fix] → [Implementation review: ✅]
[Auto-invoke ship → PR created]
```

**Integration test levels:** Task 0 provides broad acceptance tests (Level 1). Implementers write boundary tests at cross-task seams (Level 2). Implementation-review verifies coverage (Level 3).

## Completion Report

After all tasks complete, before implementation review, append to the plan doc:

```markdown
## Completion Report

**Date:** YYYY-MM-DD
**Status:** Complete

### Summary
[2-4 sentences describing what was built across all tasks]

### Deviations
[List each deviation with rule applied — or "None" if plan was followed exactly]
- Task N: [what changed] — Rule [1-3]: [one-line reason] / Rule 4: [user approved on YYYY-MM-DD]
```

This is not optional. Skipping it loses the record of what actually shipped vs. what was planned, which makes debugging regressions and reviewing PRs significantly harder.

## Multi-Phase Execution

For plans with multiple phases, the per-task flow runs within each phase. Between phases:

1. Record `PHASE_BASE_SHA` — commit before the phase's first task
2. Run full Task 0 test suite — failures in current phase scope are real issues; failures targeting future phases are expected (note and continue)
3. Dispatch implementation-review with phase-scoped diff (`PHASE_BASE_SHA..HEAD`) and `PHASE_CONTEXT` describing what downstream phases expect
4. Triage findings through deviation rules — dispatch fresh implementer for Rule 1-3 fixes, escalate Rule 4 to user
5. Verify cross-phase boundary tests exist for interface contracts downstream phases depend on (from reviewer handoff notes) — dispatch implementer to write missing ones
6. Write handoff notes into plan doc before next phase's checklist (see format below)
7. Update phase status: `Complete (YYYY-MM-DD)`

After the final phase: write completion report (summary + deviations across all phases), then ship.

Single-phase plans skip this loop entirely — existing behavior unchanged.

### Handoff Notes Format

Insert before the next phase's task checklist:

```markdown
### Phase N Handoff Notes

**Interface contracts:** [Function signatures, API shapes, config keys that Phase N+1 depends on — copy exact signatures]
**Integration test status:** [Which tests pass, which are xfail for future phases, any flaky ones]
**Known issues:** [Anything deferred, workarounds applied, tech debt taken on]
**Decisions made:** [Any plan deviations approved by user or auto-fixed, with rationale]
```

Handoff notes must reflect the post-fix state of the phase, not the reviewer's suggestions before fixes were applied. A Phase 2 implementer who reads these should have everything they need to build on Phase 1's output without re-reading the full conversation.

## Re-Review Gate

Applies to all review stages (spec, code quality, implementation review, plan review):

If a reviewer finds **more than 5 fix-needed issues**, after all fixes are applied, dispatch a fresh subagent with the same full review scope to confirm clean. Bulk fixes risk introducing new issues or incomplete resolution — a fresh reviewer catches what the fixer missed.

Under 5 issues: orchestrator verifies fixes and proceeds.

## Deviation Rules

When reality diverges from the plan:

| Rule | Trigger | Action |
|------|---------|--------|
| **Rule 1: Auto-fix bugs** | Code doesn't work as intended | Fix inline, document |
| **Rule 2: Auto-add critical** | Missing error handling, validation, auth | Fix inline, document |
| **Rule 3: Auto-fix blockers** | Missing dep, broken import, wrong types | Fix inline, document |
| **Rule 4: STOP** | New DB table, library swap, breaking API | **Ask user first** |

**Scope:** Only auto-fix issues caused by current task. Pre-existing issues go to a deferred list.

**Limit:** After 3 fix attempts on same issue, stop and document.

**Documentation:** Every Rule 1-3 deviation must include: what deviated, what was done, which rule applied.

## Plan Doc Updates

| When | Update |
|------|--------|
| First task starts | Frontmatter: `status: In Development` |
| Task completes | Change `- [ ] Task N` to `- [x] Task N` |
| Phase completes (multi-phase) | Insert handoff notes before next phase's checklist |
| Phase review passes | Phase status: `Complete (YYYY-MM-DD)` |
| All phases done | Append `## Completion Report` with summary + deviations |

## Implementation Review

After completion report written and Task 0 tests pass GREEN:

1. Get `BASE_SHA` (merge-base) and `HEAD_SHA`
2. Dispatch reviewer using `skills/implementation-review/reviewer-prompt.md`
3. If issues found → fix → re-dispatch until clean
4. Update phase status to Complete

## Key Constraints

| Constraint | Why |
|------------|-----|
| One implementer at a time | Parallel implementers cause git conflicts |
| Provide full task text | Reading plan wastes subagent context |
| Spec compliance before code quality | Code review is wasted if spec is wrong |
| Answer questions before proceeding | Assumptions produce rework |

## Integration

**Workflow:** using-git-worktrees (before) → writing-plans (creates plan) → **this skill** → implementation-review → ship → merge-pr (after CodeRabbit)

**Subagents use:** test-driven-development
