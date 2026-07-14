---
name: plan-review
description: Use when a plan has been written and before execution begins
---

# Plan Review

Dispatch a reviewer subagent to validate a plan before execution. Catches issues that are cheap to fix in a plan but expensive to fix mid-implementation.

**Core principle:** Plans are hypotheses. Validate before running the experiment.

## When to Use

- After draft-plan produces a plan directory
- Before orchestrate begins
- When resuming work on an idle plan (context may have drifted)

**Skip for:** Single-task plans, hotfix plans, trivially small plans (no design doc needed).

## Dispatch

Two-stage review:

**Stage 1: Structural validation** — Run `validate-plan --schema {PLAN_DIR}/plan.json`. If errors, report them and stop. No point dispatching LLM reviewer for structurally invalid plans.

**Stage 2: Prose + design review** — If schema passes, dispatch reviewer subagent.

Gather inputs:
- **Plan directory** — absolute path under `$MAIN_ROOT/.claude/claude-caliper/YYYY-MM-DD-topic/` (containing plan.json; main repo, not worktree)
- **Design doc** — if one exists (or "None")
- **Repo root** — the worktree the plan targets

Dispatch with `model: "$PLAN_REVIEWER_MODEL"` — consistency checking requires strong reasoning.

Use `subagent_type: "claude-caliper:plan-reviewer"`. The agent's static behavior (7-point checklist, output format) is in the agent definition. The invocation prompt contains only the plan dir, design doc path, and codebase root.

**See:** reviewer-prompt.md

## What It Catches

### Structural Validation (schema check)

Handled by `validate-plan --schema`:
- Schema version is 2 (schema-1 plans are rejected with a clear message)
- Missing required fields (goal, architecture, tech_stack, phases, tasks)
- Per-task fields present: id, name, status, depends_on, files (create/modify/test), verification, done_when, complexity, intent, avoid (array of {rule, why})
- Invalid status values (plan/phase/task status)
- Duplicate task IDs or phase letters
- Dependency cycles and forward dependencies
- Duplicate file paths in creates lists
- Empty success_criteria run commands
- Missing expect fields
- File-set overlap within a phase (create, modify, test paths must be disjoint per task)

### Prose + Design Review (LLM reviewer)

| Category | Example | Why Planners Miss It |
|----------|---------|---------------------|
| Artifact drift | Creates `utils.ts`, imports from `helpers.ts` | Renamed during planning without updating refs |
| Design mismatch | Design says REST, plan implements GraphQL | Diverged during decomposition |
| Missing tasks | Design specifies auth middleware, no auth task | Lost during decomposition |
| Ambiguous intent | `intent` says "modify the handler" without naming a file, so a fresh Claude reading the codebase can't tell which | Planner has context the executor won't |
| Missing fields | No verification command or measurable done_when | Assumes executor will figure it out |
| Avoid without reason | `avoid` entry states a rule but the `why` is empty or non-explanatory | Assumes executor will infer the constraint |
| Phase boundary issues | 9 tasks in single phase, no verification gates | Didn't apply complexity gates |
| Orphaned criteria | Design says "users can X" but no task's done_when covers it | Lost during decomposition |
| Mock-stacking at cross-task seam | Two tasks both mock `auth_middleware`; no task exercises the real middleware | LLM judgment from task intent, not schema |

## 7-Point Checklist

Plans carry `intent` and `avoid`, not pasted code. The reviewer's job is to confirm each task's `intent` is unambiguous for a fresh Claude reading the codebase, and that every design criterion is covered — this intent-quality check is the compensating control for the retired zero-context per-task ambiguity pass.

1. **Dependency Ordering** — *(schema validates graph; LLM checks semantic coherence)*
2. **Artifact Consistency** — Same file/function/variable referenced with same name across every task's `intent` and the codebase *(LLM focus)*
3. **Design Doc Alignment** — Scope, architecture, tech stack match design (skip if no design doc) *(LLM focus)*
4. **Intent Clarity (Different Claude Test)** — Each task's `intent` names concrete artifacts (paths, symbols) so a fresh Claude with zero conversation history can execute it against the codebase; `done_when` is measurable; `verification` is runnable *(LLM focus)*
5. **Avoid Quality** — Each `avoid` entry pairs a rule with a `why` that explains the constraint (schema checks both fields are non-empty; LLM checks the `why` actually reasons, not just "don't do X") *(LLM focus)*
6. **Success Criteria Coverage** — Every criterion in the design doc maps to at least one task's `done_when` field (skip if no design doc) *(LLM focus)*
7. **Cross-Task Seam Coverage** — For each seam in the design's Test Strategy section and each cross-task `depends_on` link, at least one task's `done_when`/`verification` exercises the seam without mocking the producer (skip if no Test Strategy section and no cross-task deps) *(LLM focus)*

**For multi-phase plans:**
- Phase boundaries at meaningful verification points
- Complexity gates respected (8+ tasks → needs phasing, 7+ per phase → examine cut points)
- Interface-first ordering (contracts defined before implementations)

## Output

Reviewer produces:
- Issues Found (category, tasks involved, what's wrong, suggested fix)
- Assessment (issue count, severity breakdown, ready for execution?)

**Pass:** Zero issues, or all issues fixed and confirmed clean
**Fail:** Return to draft-plan to fix, then re-run plan-review

## Review Loop Protocol (two-pass cap)

Pass 1 is discovery. The lead fixes all findings and verifies each fix inline (grep/read). A delta pass 2 is dispatched only if pass 1 found critical or high issues; after pass 2, any remaining findings are fixed inline and the loop records pass — never a third dispatch. Residual leakage is caught by the next downstream gate (implementation-review), not by additional same-gate passes.

**Pass 1:** Dispatch the reviewer, extract its `json review-summary` block, display all findings, then triage (fix vs dismiss with reasoning) and apply every fix in a single editing pass, verifying each inline (grep/read). If zero critical/high issues were found: done.

**Pass 2 (only if pass 1 found critical or high):** Re-dispatch a fresh reviewer of the same type with the same full scope, appending a `## Prior Issues` section listing the pass-1 issues each enriched with its resolution (`fixed`/`dismissed`, with dismissal reason when dismissed). Repeat triage + inline fix/verify for any newly reported issues, then record pass — no further dispatch regardless of what remains.

## Integration

**Auto-dispatched by:** draft-plan (after plan saved)

**Leads to:** orchestrate (once review passes)
