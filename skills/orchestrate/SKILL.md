---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute phases via per-phase worktrees on an integration branch. Dispatch phase dispatcher → implementation-review → advance. Workflow from plan.json controls ship behavior.

**Core principle:** Every level is a dispatcher — only the implementer subagent touches code.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./phase-dispatcher-prompt.md` | Dispatch phase dispatcher subagent |
| `./implementer-prompt.md` | Task implementer (phase dispatcher + post-review fixes) |
| `./task-reviewer-prompt.md` | Per-task reviewer (phase dispatcher) |
| `skills/implementation-review/reviewer-prompt.md` | Cross-task reviewer (orchestrate context) |

## Progress Tracking

Create task list for progress tracking:

1. **Read plan** — identify phases and task counts
2. **Build task list** — TaskCreate per step:
   - Per phase: "Phase {X}: Execute tasks ({N} tasks)", "Phase {X}: Implementation review", "Phase {X}: Ship PR"
   - Final: "Mark plan complete"
   Set dependencies with `addBlockedBy` so each phase blocks the next.
3. **Update as you go** — mark tasks `in_progress` / `completed`. After subagents, output progress note:
   - Dispatcher: `Phase A complete — [what was built]`
   - Review: `Phase A review — N issues, all resolved`
   - Ship: `Phase A PR — [URL]`
4. **Ship tasks** apply to both `create-pr` and `merge-pr` workflows — the difference is only whether the final PR is merged

## Setup

Before first phase:
- Read workflow: `WORKFLOW=$(jq -r '.workflow' plan.json)` — controls ship behavior (`create-pr`, `merge-pr`)
- `scripts/validate-plan --update-status plan.json --plan --status "In Development"`
- `PLAN_BASE_SHA=$(git rev-parse HEAD)` — saved for final cross-phase review
- Push integration branch: `git push -u origin integrate/<feature>`

## Phase DAG Construction

Build dependency graph from plan.json before dispatching:

```bash
jq -r '.phases[] | "\(.letter):\(.depends_on | join(","))"' plan.json
```

Initial wave: phases with empty `depends_on`. Sequential plans produce waves of size 1.

## Per-Phase Execution (Wave Loop)

```text
LOOP until all phases complete:
  a. Ready phases: depends_on all in completed set
  b. Reconciliation (non-root phases): run `git diff --name-only` against each completed dep; detect file overlap or semantic impacts vs this phase's tasks; skip declared depends_on; inject `## Reconciliation: Impact from Phase {X}` into affected task .md files; log injections
  c. Dispatch ready phases IN PARALLEL (one Agent per phase)
  d. Process completions SERIALLY: review → triage → rebase → ship → merge → mark complete
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
   - `PRIOR_COMPLETIONS` — concatenate `completion.md` from transitive `depends_on` closure. Phase D (deps: B, C) receives A+B+C. Empty if no dependencies.
   - `CROSS_PHASE_HANDOFF_TARGETS` — JSON mapping source task to target paths. Scan phases transitively depending on current phase (not positional — later-indexed phases may be siblings in DAG).
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
14. Ship phase PR: invoke ship with `--base integrate/<feature>`
15. Merge phase PR: `gh pr merge --squash`, then update integration worktree: `git pull` in `.claude/worktrees/<feature>/`
16. Clean up phase worktree:
    ```bash
    git worktree remove .claude/worktrees/<feature>-phase-{letter}
    git branch -D phase-{letter}
    ```

Single-phase plans: one iteration. Skip final cross-phase review.

## After All Phases

1. Run plan criteria: `scripts/validate-plan --criteria plan.json --plan`. If exit 1, do not mark complete.
2. Final cross-phase review (multi-phase only): dispatch implementation-review with `PLAN_BASE_SHA..HEAD`
3. Triage findings, fix issues
4. `scripts/validate-plan --update-status plan.json --plan --status Complete`
5. Route on workflow:
   - `"merge-pr"`: create final PR (`integrate/<feature>` → main), invoke merge-pr, clean up integration worktree
   - `"create-pr"`: create final PR but stop — user reviews and merges manually

**Continuity:** Execute all phases, reviews, and shipping continuously. Pause only for Rule 4 violations.

## Rule 4 Handling

When dispatcher reports Rule 4 violation, ask user. Present: what change, which task, why plan doesn't cover it. Wait for user decision.

## Permission Model

Subagents run in `auto` mode — Claude evaluates permissions with prompt injection safeguards. PreToolUse hook (`hooks/pretooluse-safe-commands.sh`) intercepts Bash commands and auto-approves those matching safe list prefixes, avoiding per-command AI evaluation. Hook uses `~/.claude/safe-commands.txt` if present (user override), else bundled `hooks/safe-commands.txt`. Non-safe commands fall through to auto mode. Phase dispatcher surfaces non-safe commands after each task for user to grow safe list.

## Key Constraints

| Constraint | Why |
|------------|-----|
| Record PLAN_BASE_SHA before first phase | Final cross-phase review needs total diff |
| Record PHASE_BASE_SHA per phase | Per-phase review needs exact phase start |
| Reconciliation before dispatch | Planner may miss deps even without deviations |
| Use validate-plan for all status updates | Keeps plan.json and plan.md in sync |

## Integration

**Workflow:** design (creates integration branch + worktree) → draft-plan → **this skill** → ship → merge-pr

**See:** `tdd.md` — TDD reference; content is embedded in implementer prompts
