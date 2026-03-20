---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute plan phase by phase using per-phase worktrees and an integration branch. Dispatch a fresh phase dispatcher subagent per phase, then dispatch implementation-review from the orchestrate context, and advance. Workflow routing from plan.json controls ship behavior.

**Core principle:** Every level is a dispatcher. Orchestrate dispatches phase dispatchers. Phase dispatchers dispatch implementers and reviewers. No level writes application code itself — only the implementer subagent touches code.

## When to Use

- Have an implementation plan with mostly independent tasks
- Don't use for tightly coupled tasks or when no plan exists

## Subagent Hierarchy

```text
Orchestrate (you)           — 1 per plan
├── Phase Dispatcher        — 1 per phase (dispatches implementers + reviewers, never writes code)
│   ├── Implementer         — 1 per task (fresh context, writes code via TDD)
│   └── Task Reviewer       — 1 per task (evaluates code cold, single-pass)
└── Implementation Review   — 1 per phase (cross-task holistic, dispatched by you)
```

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./phase-dispatcher-prompt.md` | Dispatch phase dispatcher subagent |
| `./implementer-prompt.md` | Dispatch individual task implementer (used inside phase dispatcher and for post-review fixes) |
| `./task-reviewer-prompt.md` | Per-task reviewer (used inside phase dispatcher) |
| `skills/implementation-review/reviewer-prompt.md` | Holistic cross-task reviewer (dispatched from orchestrate context) |

## Progress Tracking

Before executing, create a visible task list so the user can track progress:

1. **Read the plan** — identify phases and task counts
2. **Build task list** — TaskCreate for each major step:
   - Per phase: "Phase {X}: Execute tasks ({N} tasks)", "Phase {X}: Implementation review", "Phase {X}: Ship PR"
   - Final: "Mark plan complete"
   Set dependencies with `addBlockedBy` so each phase blocks the next.
3. **Update as you go** — mark tasks `in_progress` before starting, `completed` when done. After each subagent returns, output a one-line progress note:
   - Dispatcher: `Phase A complete — [what was built]`
   - Review: `Phase A review — N issues, all resolved`
   - Ship: `Phase A PR — [URL]`
4. **Skip ship tasks** if workflow is `review-only` — omit "Ship PR" tasks from the list entirely

## Setup

Before first phase:
- Read workflow: `WORKFLOW=$(jq -r '.workflow' plan.json)` — controls ship behavior (`ship`, `review-only`)
- `scripts/validate-plan --update-status plan.json --plan --status "In Development"`
- `PLAN_BASE_SHA=$(git rev-parse HEAD)` — saved for final cross-phase review
- Push integration branch: `git push -u origin integrate/<feature>`

## Phase DAG Construction

Build the dependency graph from plan.json before dispatching any phases:

```bash
jq -r '.phases[] | "\(.letter):\(.depends_on | join(","))"' plan.json
```

Identify the initial wave: phases with empty `depends_on`. Sequential plans (A→B→C) produce waves of size 1 — no special-casing needed.

## Per-Phase Execution (Wave Loop)

```text
LOOP until all phases complete:
  a. Ready phases: depends_on all in completed set
  b. Dispatch ready phases IN PARALLEL (one Agent per phase)
  c. Process completions SERIALLY: review → triage → rebase → ship → merge → mark complete
  d. Repeat
```

For each phase being dispatched:

1. Create phase worktree from integration branch:
   ```bash
   git worktree add .claude/worktrees/<feature>-phase-{letter} -b phase-{letter} integrate/<feature>
   ```
2. `PHASE_BASE_SHA=$(git rev-parse HEAD)` in the phase worktree
3. Extract context from plan.json:
   - `PHASE_TASKS_JSON=$(jq '.phases[N].tasks' plan.json)`
   - `PLAN_DIR=$(dirname "$(realpath plan.json)")`
   - `PHASE_DIR=${PLAN_DIR}/phase-{letter_lower}`
   - `PRIOR_COMPLETIONS` — concatenate `completion.md` from the transitive `depends_on` closure. Phase D (deps: B, C) receives A+B+C. Empty when no dependencies.
   - `CROSS_PHASE_HANDOFF_TARGETS` — JSON mapping source task to target paths. Scan: `jq '.phases[(N+1):][].tasks[] | select(.depends_on[]?)'`.
4. Dispatch phase dispatcher (`./phase-dispatcher-prompt.md`) with: `PHASE_LETTER`, `PHASE_NAME`, `PHASE_TASKS_JSON`, `PLAN_DIR`, `PHASE_DIR`, `PRIOR_COMPLETIONS`, `CROSS_PHASE_HANDOFF_TARGETS`, `REPO_PATH` (= phase worktree path)
5. After dispatcher returns:
   - Rule 4 violation → ask user, pause (see Rule 4 Handling)
   - Otherwise → dispatch implementation-review with: `PHASE_BASE_SHA`, `HEAD`, `PLAN_DIR`, `PHASE_DIR`
     - DESIGN_DOC_PATH = `design-doc` from plan.json (or "None")
6. Triage: dispatch implementer for Rule 1-3; Rule 4 → ask user and pause
7. Re-Review Gate: >5 issues → re-review after fixes
8. Append review changes to `${PHASE_DIR}/completion.md`
9. Run phase criteria: `scripts/validate-plan --criteria plan.json --phase {LETTER}`. If exit 1, pause and report failing criteria to user — do not advance.
10. Emit phase summary: "Phase {LETTER} complete. [N tasks]. Review: X issues — [brief list]. [Status]."
11. Update status: `scripts/validate-plan --update-status plan.json --phase {LETTER} --status "Complete (YYYY-MM-DD)"`
12. Rebase on latest integration:
    ```bash
    git -C .claude/worktrees/<feature>-phase-{letter} rebase origin/integrate/<feature>
    ```
    Clean → run tests → continue. Conflict markers → `git rebase --abort`, escalate to user. First to merge: no-op.
13. Ship phase PR: invoke ship with `--base integrate/<feature>`
14. Merge phase PR: `gh pr merge --squash`, then update integration worktree: `git pull` in `.claude/worktrees/<feature>/`
15. Clean up phase worktree:
    ```bash
    git worktree remove .claude/worktrees/<feature>-phase-{letter}
    git branch -D phase-{letter}
    ```

Single-phase plans: one iteration. Skip final cross-phase review.

## After All Phases

1. Run plan criteria: `scripts/validate-plan --criteria plan.json --plan`. If exit 1, do not mark complete.
2. Final cross-phase review (multi-phase only): dispatch implementation-review with `PLAN_BASE_SHA..HEAD` on integration branch
3. Triage findings, fix issues
4. `scripts/validate-plan --update-status plan.json --plan --status Complete`
5. Route on workflow:
   - `"ship"`: create final PR (`integrate/<feature>` → main), merge, clean up integration worktree
   - `"review-only"`: create final PR but stop — user reviews and merges manually

**Continuity:** Execute all phases, reviews, and shipping in one continuous flow. Do not pause between phases or wait for user confirmation unless a Rule 4 violation occurs. The only human touchpoints are Rule 4 escalations.

## Example Workflow (Diamond: A→B+C→D)

```text
Wave 1: A (no deps)          → dispatch phase-a
Wave 2: B (dep: A), C (dep: A) → dispatch phase-b + phase-c IN PARALLEL
         phase-b returns first → process serially: review, rebase, merge
         phase-c returns next  → process serially: rebase on updated integration, merge
Wave 3: D (dep: B, C)        → dispatch phase-d

Setup: PLAN_BASE_SHA=$(git rev-parse HEAD); git push -u origin integrate/<feature>
Each phase: git worktree add .claude/worktrees/<feature>-phase-{x} -b phase-{x} integrate/<feature>
           PHASE_BASE_SHA=$(git rev-parse HEAD)  # in phase worktree
           Dispatch with REPO_PATH=.claude/worktrees/<feature>-phase-{x}
           Review, ship --base integrate/<feature>, gh pr merge, git pull in integration worktree
           git worktree remove + git branch -D phase-{x}
Final: cross-phase review PLAN_BASE_SHA..HEAD; if workflow==ship: gh pr create → main
```

## Rule 4 Handling

When a phase dispatcher reports a Rule 4 violation, ask the user directly — orchestrate runs in the main agent context. Present: what change is needed, which task triggered it, why the plan doesn't cover it. Options: update the plan or adjust task scope. Do not proceed until the user decides.

## Key Constraints

| Constraint | Why |
|------------|-----|
| Record PLAN_BASE_SHA before first phase | Final cross-phase review needs total diff |
| Record PHASE_BASE_SHA per phase | Per-phase implementation-review needs exact phase start |
| Pass only current phase's tasks | Context isolation prevents overload |
| Fix review issues before next phase | Phase N bugs compound into Phase N+1 |
| Use validate-plan for all status updates | Keeps plan.json and plan.md in sync |
| Escalate Rule 4 immediately | Architectural changes need human judgment |

## Integration

**Workflow:** design (creates integration branch + worktree) → draft-plan → **this skill** → ship (per-phase + final) → merge-pr

**See:** `tdd.md` — TDD reference; content is embedded in implementer prompts
