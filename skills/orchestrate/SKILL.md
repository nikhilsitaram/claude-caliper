---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute plan phase by phase: dispatch a fresh phase dispatcher subagent per phase, then dispatch implementation-review from the orchestrate context, report phase completion, and advance. After all phases, auto-invoke ship.

**Core principle:** Every level is a dispatcher. Orchestrate dispatches phase dispatchers. Phase dispatchers dispatch implementers and reviewers. No level writes application code itself — only the implementer subagent touches code.

## When to Use

- Have an implementation plan with mostly independent tasks
- Don't use for tightly coupled tasks or when no plan exists

## Subagent Hierarchy

```text
Orchestrate (you)           — 1 per plan
├── Phase Dispatcher        — 1 per phase (dispatches implementers + reviewers, never writes code)
│   ├── Implementer         — 1 per task (fresh context, writes code via TDD)
│   ├── Spec Reviewer       — 1 per task (evaluates code cold)
│   └── Code Quality Rev.   — 1 per task (evaluates code cold)
└── Implementation Review   — 1 per phase (cross-task holistic, dispatched by you)
```

Why separate subagents per task: each implementer starts with fresh context, preventing quality degradation as tasks accumulate. Each reviewer evaluates code without having seen the implementation rationale.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./phase-dispatcher-prompt.md` | Dispatch phase dispatcher subagent |
| `./implementer-prompt.md` | Dispatch individual task implementer (used inside phase dispatcher and for post-review fixes) |
| `./spec-reviewer-prompt.md` | Spec compliance reviewer (used inside phase dispatcher) |
| `./code-quality-reviewer-prompt.md` | Code quality reviewer (used inside phase dispatcher) |
| `skills/implementation-review/reviewer-prompt.md` | Holistic cross-task reviewer (dispatched from orchestrate context) |

## Per-Phase Execution

Before first phase: `scripts/validate-plan --update-status plan.json --plan --status "In Development"`

For each phase:

1. `PHASE_BASE_SHA=$(git rev-parse HEAD)` — before dispatching
2. Create phase branch: `git checkout -b phase-{letter}` (Phase A from HEAD, others from prior tip)
3. Extract context from plan.json:
   - `PHASE_TASKS_JSON=$(jq '.phases[N].tasks' plan.json)`
   - `PLAN_DIR=$(dirname "$(realpath plan.json)")`
   - `PHASE_DIR=${PLAN_DIR}/phase-{letter_lower}`
   - `PRIOR_COMPLETIONS` — concatenate only `completion.md` files for phases before the current one (indices `0..N-1`), in manifest order. Do not glob `phase-*/completion.md` — that includes the current/future phase stubs.
   - `CROSS_PHASE_HANDOFF_TARGETS` — JSON mapping source task to array of target paths, e.g. `{"A2": ["phase-b/b2.md", "phase-c/c1.md"]}`. Scan: `jq '.phases[(N+1):][].tasks[] | select(.depends_on[]? == "A2")'`. Arrays handle fan-out (multiple later tasks depending on the same source).
4. Dispatch phase dispatcher (`./phase-dispatcher-prompt.md`) with: `PHASE_LETTER`, `PHASE_NAME`, `PHASE_TASKS_JSON`, `PLAN_DIR`, `PHASE_DIR`, `PRIOR_COMPLETIONS`, `CROSS_PHASE_HANDOFF_TARGETS`, `REPO_PATH`
5. After dispatcher returns:
   - Rule 4 violation → ask user, pause (see Rule 4 Handling)
   - Otherwise → dispatch implementation-review with: `PHASE_BASE_SHA`, `HEAD`, `PLAN_DIR`, `PHASE_DIR`
6. Triage review findings via deviation rules — dispatch implementer for Rule 1-3; Rule 4 → ask user and pause
7. Re-Review Gate: >5 issues → re-review after fixes
8. Append review changes to `${PHASE_DIR}/completion.md`
9. Emit phase summary: "Phase A complete. [N tasks]. Review: X issues — [brief list]. [Status]."
10. Update status: `scripts/validate-plan --update-status plan.json --phase {LETTER} --status "Complete (YYYY-MM-DD)"`
11. Ship PR: invoke ship with `--base phase-{prior-letter}` (or `--base main` for Phase A)

Single-phase plans: one iteration of the same loop. Skip handoff notes.

After the final phase: `scripts/validate-plan --update-status plan.json --plan --status Complete`, then auto-invoke ship.

## Example Workflow

```bash
# Phase A
git checkout -b phase-a; PHASE_BASE_SHA=$(git rev-parse HEAD)
PHASE_TASKS_JSON=$(jq '.phases[0].tasks' plan.json)
# Dispatch with: PHASE_TASKS_JSON, PLAN_DIR, PHASE_DIR, no prior completions
# Implementation-review: pass PLAN_DIR, PHASE_DIR
scripts/validate-plan --update-status plan.json --phase A --status "Complete (2026-03-20)"
# Ship: --base main

# Phase B
git checkout -b phase-b; PHASE_BASE_SHA=$(git rev-parse HEAD)
PHASE_TASKS_JSON=$(jq '.phases[1].tasks' plan.json)
PRIOR_COMPLETIONS=$(cat "${PLAN_DIR}/phase-a/completion.md")
# Dispatch with: PHASE_TASKS_JSON, PLAN_DIR, PHASE_DIR, PRIOR_COMPLETIONS, CROSS_PHASE_HANDOFF_TARGETS
# Ship: --base phase-a

# All done
scripts/validate-plan --update-status plan.json --plan --status Complete
```

## Inline Handoff Notes

Handoff notes live in task .md files. When a task in a later phase has `depends_on: ["A2"]`, the dispatcher writes handoff details to `${PLAN_DIR}/phase-{letter}/{target_task_id_lower}.md`, inserting a `## Handoff from {TASK_ID}` section after the H1 header. The dispatcher fills in real function signatures, file paths, config keys — concrete details the target task needs. The orchestrator builds `CROSS_PHASE_HANDOFF_TARGETS` by scanning later phases' `depends_on` fields and passes this map to the dispatcher.

## Rule 4 Handling

When a phase dispatcher reports a Rule 4 violation, ask the user directly — orchestrate runs in the main agent context. Present:

- **What:** The architectural change needed
- **Where:** Phase X, Task XN — task title
- **Why:** What the implementer tried and why the plan doesn't cover it
- **Options:** Update the plan to include the change, or adjust task scope to avoid it

Do not attempt subsequent tasks or phases until the user decides.

## Key Constraints

| Constraint | Why |
|------------|-----|
| Record BASE_SHA before dispatcher | Implementation-review needs the exact phase start SHA |
| Pass only PHASE_TASKS_JSON for current phase | Context isolation prevents dispatcher from being overwhelmed by irrelevant phase details |
| Dispatch implementation-review from orchestrate context | Phase completion and any issues must be visible before advancing — prevents bugs compounding |
| Fix review issues before next phase | Phase N bugs compound into Phase N+1 complexity |
| Ship per-phase PR with stacked base | Each PR shows only its phase's diff, making review manageable |
| Call scripts/validate-plan for all status updates | Keeps plan.json and plan.md in sync; triggers automatic re-render |
| Escalate Rule 4 immediately | Ask the user — architectural changes need human judgment |

## Integration

**Workflow:** worktree setup (before) → draft-plan (creates plan) → **this skill** → ship (auto-invoked after final phase) → merge-pr (after CodeRabbit)

**See:** `tdd.md` — TDD reference (cycle, boundary tests, failure modes); content is embedded in implementer prompts
