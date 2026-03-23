---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute phases via worktrees. Multi-phase uses an integration branch with per-phase worktrees; single-phase works directly on the feature branch. Dispatch phase dispatcher → implementation-review → advance.

**Core principle:** Every level is a dispatcher — only implementer subagents touch code.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./phase-dispatcher-prompt.md` | Dispatch phase dispatcher subagent |
| `./implementer-prompt.md` | Task implementer (phase dispatcher + post-review fixes) |
| `./task-reviewer-prompt.md` | Per-task reviewer (phase dispatcher) |
| `skills/implementation-review/reviewer-prompt.md` | Cross-task reviewer (orchestrate context) |

## Progress Tracking

1. **Read plan** — identify phases and task counts
2. **Build task list** — TaskCreate per phase: "Execute tasks ({N})", "Implementation review", "Create PR". Final: "Mark plan complete". Set `addBlockedBy` so phases block the next.
3. **Update as you go** — mark `in_progress` / `completed`. After subagents, output progress note.

## Setup

Before first phase:
- Read workflow: `WORKFLOW=$(jq -r '.workflow' plan.json)`
- Count phases: `PHASE_COUNT=$(jq '.phases | length' plan.json)`
- `scripts/validate-plan --update-status plan.json --plan --status "In Development"`
- `PLAN_BASE_SHA=$(git rev-parse HEAD)`
- Push branch: `git push -u origin HEAD`

## Phase DAG Construction

Build dependency graph from plan.json:

```bash
jq -r '.phases[] | "\(.letter):\(.depends_on | join(","))"' plan.json
```

Initial wave: phases with empty `depends_on`. Sequential plans: waves of size 1.

## Per-Phase Execution (Wave Loop)

```text
LOOP until all phases complete:
  a. Ready phases: depends_on all in completed set
  b. Reconciliation (non-root phases): `git diff --name-only` vs each completed dep; detect file overlaps with this phase's tasks; inject `## Reconciliation: Impact from Phase {X}` into affected task .md files
  c. Dispatch ready phases IN PARALLEL (one Agent per phase)
  d. Process completions SERIALLY: review → triage → rebase → create-pr → poll checks → review-pr → merge → mark complete
  e. Repeat
```

For each phase being dispatched:

1. Create phase worktree from integration branch:
   ```bash
   git worktree add .claude/worktrees/<feature>-phase-{letter} -b phase-{letter} integrate/<feature>
   ```
2. `PHASE_BASE_SHA=$(git rev-parse HEAD)` in phase worktree
3. **Bootstrap dependencies** in the phase worktree. **See:** skills/design/dependency-bootstrap.md
4. Extract context from plan.json:
   - `PHASE_TASKS_JSON=$(jq '.phases[N].tasks' plan.json)`
   - `PLAN_DIR=$(dirname "$(realpath plan.json)")`
   - `PHASE_DIR=${PLAN_DIR}/phase-{letter_lower}`
   - `PRIOR_COMPLETIONS` — concatenate `completion.md` from transitive `depends_on` closure (Phase D with deps B,C receives A+B+C). Empty if none.
   - `CROSS_PHASE_HANDOFF_TARGETS` — JSON mapping source task to target paths (scan transitive dependents — later-indexed phases may be DAG siblings).
5. Dispatch phase dispatcher (`./phase-dispatcher-prompt.md`) with: `PHASE_LETTER`, `PHASE_NAME`, `PHASE_TASKS_JSON`, `PLAN_DIR`, `PHASE_DIR`, `PRIOR_COMPLETIONS`, `CROSS_PHASE_HANDOFF_TARGETS`, `REPO_PATH` (phase worktree path)
6. After dispatcher returns:
   - Rule 4 violation → ask user, pause (see Rule 4 Handling)
   - Otherwise → dispatch implementation-review with `PHASE_BASE_SHA`, `HEAD`, `PLAN_DIR`, `PHASE_DIR`
     - DESIGN_DOC_PATH = `design-doc` from plan.json (or "None")
7. Triage: dispatch implementer for Rule 1-3; Rule 4 → ask user and pause
8. Re-Review Gate: >5 issues → re-review after fixes
9. Append review changes to `${PHASE_DIR}/completion.md`
10. Run phase criteria: `scripts/validate-plan --criteria plan.json --phase {LETTER}`. If exit 1, pause and report failing criteria — do not advance.
11. Emit phase summary: "Phase {LETTER} complete. [N tasks]. Review: X issues. [Status]."
12. Update status: `scripts/validate-plan --update-status plan.json --phase {LETTER} --status "Complete (YYYY-MM-DD)"`
13. Rebase on latest integration:
    ```bash
    git -C .claude/worktrees/<feature>-phase-{letter} fetch origin integrate/<feature>
    git -C .claude/worktrees/<feature>-phase-{letter} rebase origin/integrate/<feature>
    ```
    Clean → run tests → continue. Conflicts → `git rebase --abort`, escalate. First to merge: no-op.
14. Create phase PR: invoke create-pr with `--base integrate/<feature>`
15. External review gate (skip steps 15-16 if `review_wait_minutes` is 0): Poll `gh pr checks <NUMBER> --json bucket --jq '[.[] | select(.bucket == "pending")] | length'` every 60s. Max wait: `jq -r '.review_wait_minutes // 10' plan.json` minutes. Timeout → warn and proceed.
16. Review feedback: invoke review-pr to read and address all reviewer comments
17. Merge phase PR: `gh pr merge --squash`, then update integration worktree: `git pull` in `.claude/worktrees/<feature>/`
18. Clean up phase worktree:
    ```bash
    git worktree remove .claude/worktrees/<feature>-phase-{letter}
    git branch -D phase-{letter}
    ```

## Single-Phase Plans

Skip the wave loop, phase worktrees, and integration branch entirely. The design skill already created a feature branch (not `integrate/`):

1. Work directly in the feature worktree (`.claude/worktrees/<feature>`)
2. Dispatch phase dispatcher with `REPO_PATH` = feature worktree
3. Implementation review, triage, fix
4. Run plan criteria: `scripts/validate-plan --criteria plan.json --plan`
5. `scripts/validate-plan --update-status plan.json --plan --status Complete`
6. Route on workflow:
   - `"create-pr"`: invoke create-pr (targets main), stop
   - `"merge-pr"`: invoke create-pr, poll checks + review-pr (skip if `review_wait_minutes` is 0), then merge-pr with `--squash`

## After All Phases (Multi-Phase Only)

1. Run plan criteria: `scripts/validate-plan --criteria plan.json --plan`. If exit 1, do not mark complete.
2. Final cross-phase review: dispatch implementation-review with `PLAN_BASE_SHA..HEAD`
3. Triage findings, fix issues
4. `scripts/validate-plan --update-status plan.json --plan --status Complete`
5. Route on workflow:
   - `"merge-pr"`: `cd "$MAIN_REPO"` first, then create final PR (`integrate/<feature>` → main), poll checks, invoke review-pr, then merge-pr with `--rebase`, clean up integration worktree
   - `"create-pr"`: create final PR but stop — user reviews and merges manually

**Continuity:** Run continuously. Pause only for Rule 4 violations and merge confirmation in merge-pr.

## Rule 4 Handling

When dispatcher reports Rule 4 violation, ask user. Present: what change, which task, why plan doesn't cover it. Wait for user decision.

## Permission Model

Subagents run in `auto` mode. PreToolUse hook (`hooks/pretooluse-safe-commands.sh`) auto-approves Bash commands matching safe list prefixes. Phase dispatcher surfaces non-safe commands after each task for user to grow safe list.

## Key Constraints

| Constraint | Why |
|------------|-----|
| Record PLAN_BASE_SHA before first phase | Final cross-phase review needs total diff |
| Record PHASE_BASE_SHA per phase | Per-phase review needs exact phase start |
| Reconciliation before dispatch | Planner may miss deps even without deviations |
| Use validate-plan for all status updates | Keeps plan.json and plan.md in sync |

## Integration

**Workflow:** design (creates feature or integration branch + worktree) → draft-plan → **this skill** → create-pr → review-pr → merge-pr

**See:** `tdd.md` — TDD reference; content is embedded in implementer prompts
