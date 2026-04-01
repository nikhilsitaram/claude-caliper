---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute plans via the configured execution mode. Phases run sequentially; task dispatch within each phase depends on the mode.

**Core principle:** The lead coordinates — dispatched implementers touch code.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./implementer-prompt.md` | Task implementer |
| `./task-reviewer-prompt.md` | Per-task reviewer |
| `skills/implementation-review/reviewer-prompt.md` | Cross-task reviewer (lead dispatches) |
| `./dispatch-subagents.md` | Subagents dispatch protocol |
| `./dispatch-agent-teams.md` | Agent teams dispatch protocol |

## Progress Tracking

TaskCreate per phase: "Execute tasks ({N})", "Implementation review", "Create PR". Final: "Mark plan complete". Set `addBlockedBy`. Mark `in_progress` / `completed` as you go.

## Setup

Before first phase:
- Resolve absolute path: `PLAN_JSON=$(realpath plan.json)` and `PLAN_DIR=$(dirname "$PLAN_JSON")`
  Plan artifacts live under `.claude/claude-caliper/` (gitignored). Phase worktrees won't have these files, so all plan.json references must use the absolute `$PLAN_JSON` path — it points to the integration worktree where the plan was created.
- Read workflow: `WORKFLOW=$(jq -r '.workflow' "$PLAN_JSON")`
- Read execution mode: `EXEC_MODE=$(jq -r '.execution_mode' "$PLAN_JSON")`
Note: `workflow` and `execution_mode` are read from plan.json (set by the design skill based on user selection and caliper-settings defaults), not from caliper-settings at runtime. This avoids two sources of truth — the plan is the single source once created.
- Read task implementer model: `TASK_IMPLEMENTER_MODEL=$(${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get task_implementer_model)`
- Read task reviewer model: `TASK_REVIEWER_MODEL=$(${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get task_reviewer_model)`
- Read implementation reviewer model: `IMPL_REVIEWER_MODEL=$(${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get implementation_reviewer_model)`
Note: These model settings are substituted into dispatch template variables `{TASK_IMPLEMENTER_MODEL}`, `{TASK_REVIEWER_MODEL}`, and `{IMPL_REVIEWER_MODEL}` when dispatching implementers, reviewers, and fix-cycle agents.
- Count phases: `PHASE_COUNT=$(jq '.phases | length' "$PLAN_JSON")`
- Validate schema: `scripts/validate-plan --schema "$PLAN_JSON"`
- Validate entry gate: `scripts/validate-plan --check-entry "$PLAN_JSON" --stage execution`
- Validate base branch: `scripts/validate-plan --check-base "$PLAN_JSON"`
- Validate consistency: `scripts/validate-plan --consistency "$PLAN_JSON"`
- `scripts/validate-plan --update-status "$PLAN_JSON" --plan --status "In Development"`
- `PLAN_BASE_SHA=$(git rev-parse HEAD)`
- `[ -f "$PLAN_DIR/reviews.json" ] || echo '[]' > "$PLAN_DIR/reviews.json"`
- Push branch: `git push -u origin HEAD`
- Read the dispatch protocol for `EXEC_MODE`: **See:** `./dispatch-subagents.md` (subagents) or `./dispatch-agent-teams.md` (agent-teams) — read only the file matching `EXEC_MODE`

## Per-Phase Execution (Sequential)

Process phases in order (A, B, C...). For each phase:

### Prepare Phase

1. Create phase worktree from integration branch (multi-phase) or use feature worktree (single-phase)
2. Re-validate base branch: `scripts/validate-plan --check-base "$PLAN_JSON"` (multi-phase only — ensures dispatch happens from integration worktree, not main)
3. `PHASE_BASE_SHA=$(git rev-parse HEAD)` in worktree
4. **Bootstrap dependencies** in the worktree. **See:** skills/design/dependency-bootstrap.md
5. Extract context: tasks JSON, plan dir, phase dir, prior completions (from depends_on closure)
6. Cross-phase handoff notes: lead writes handoff sections to task .md files for tasks consuming prior-phase output

### Dispatch, Complete, and Review Tasks

Follow the dispatch protocol from the mode-specific file read during setup. Both modes share these invariants:
- Only dispatch tasks whose dependencies are met (`scripts/validate-plan --check-deps "$PLAN_JSON"`)
- Each task gets reviewed after implementation (reviewer always uses `./task-reviewer-prompt.md`)
- After review passes: validate criteria (`scripts/validate-plan --criteria "$PLAN_JSON" --task {TASK_ID}`), merge task branch, check for newly unblocked tasks

The dispatch file specifies how tasks are dispatched (teammates vs subagents), how completions are detected (push vs background notification), and how review fixes are communicated (mailbox vs fresh agent).

### Phase Wrap-Up

After all tasks complete and branches merged:
1. Dispatch implementation-review with `PHASE_BASE_SHA..HEAD` using `model: "$IMPL_REVIEWER_MODEL"`, run Review Loop Protocol (scope: `phase-{letter_lower}`)
2. `scripts/validate-plan --check-review "$PLAN_JSON" --type impl-review --scope phase-{letter_lower}`
3. Append review changes to `${PHASE_DIR}/completion.md`
4. Run phase criteria: `scripts/validate-plan --criteria "$PLAN_JSON" --phase {LETTER}`
5. Update status: `scripts/validate-plan --update-status "$PLAN_JSON" --phase {LETTER} --status "Complete (YYYY-MM-DD)"`
6. Re-validate consistency: `scripts/validate-plan --consistency "$PLAN_JSON"` (catches state drift after status updates)
7. (Multi-phase) Create phase PR, external review gate, merge, clean up worktree

## Review Loop Protocol

Read the re-review threshold: `RE_REVIEW_THRESHOLD=$(${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get re_review_threshold)` (default: 5).

After each impl-review dispatch:

1. Extract last `json review-summary` fenced block from response. Missing/malformed -> verdict:fail, re-dispatch.
2. Triage issues: "fix" (dispatch implementer) or "dismiss" (with reasoning)
3. actionable == 0 -> write reviews.json record with verdict:pass, advance
4. actionable 1-$RE_REVIEW_THRESHOLD -> fix all, verify, write record verdict:pass, advance
5. actionable > $RE_REVIEW_THRESHOLD -> fix all, write record verdict:fail, re-dispatch (max 3 iterations, then escalate via AskUserQuestion)

Append record to `{PLAN_DIR}/reviews.json`:
`{"type":"impl-review","scope":"{SCOPE}","iteration":N,"issues_found":N,"severity":{...},"actionable":N,"dismissed":N,"dismissals":[...],"fixed":N,"remaining":0,"verdict":"pass|fail","timestamp":"ISO8601"}`

## Single-Phase Plans

Skip integration branch and phase worktrees. Work directly in the feature worktree:

1. Dispatch tasks, process completions, wrap up (same dispatch protocol as above)
2. Dispatch implementation-review, run Review Loop Protocol (scope: `phase-a`)
3. `scripts/validate-plan --check-review "$PLAN_JSON" --type impl-review --scope phase-a`
4. Run plan criteria: `scripts/validate-plan --criteria "$PLAN_JSON" --plan`
5. `scripts/validate-plan --update-status "$PLAN_JSON" --plan --status Complete`
6. Re-validate consistency: `scripts/validate-plan --consistency "$PLAN_JSON"`
7. Route on workflow:
   - `"pr-create"`: invoke pr-create (targets main), `scripts/validate-plan --check-workflow "$PLAN_JSON"`, stop
   - `"pr-merge"`: invoke pr-create, read `REVIEW_WAIT=$(${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get review_wait_minutes)`, poll checks + pr-review --automated (skip if $REVIEW_WAIT is 0; if skipped, invoke pr-merge directly), `scripts/validate-plan --check-workflow "$PLAN_JSON"`

## After All Phases (Multi-Phase Only)

1. Run plan criteria: `scripts/validate-plan --criteria "$PLAN_JSON" --plan`. If exit 1, do not mark complete.
2. Final review: dispatch implementation-review with `PLAN_BASE_SHA..HEAD`, run Review Loop Protocol (scope: `final`)
3. `scripts/validate-plan --check-review "$PLAN_JSON" --type impl-review --scope final`
4. `scripts/validate-plan --update-status "$PLAN_JSON" --plan --status Complete`
5. Re-validate consistency: `scripts/validate-plan --consistency "$PLAN_JSON"`
6. Route on workflow:
   - `"pr-merge"`: create final PR, poll checks, pr-review --automated, `scripts/validate-plan --check-workflow "$PLAN_JSON"`, clean up
   - `"pr-create"`: create final PR, `scripts/validate-plan --check-workflow "$PLAN_JSON"`, stop

**Continuity:** Run continuously. Pause only for Rule 4 violations.

## Key Constraints

| Constraint | Why |
|------------|-----|
| Resolve `PLAN_JSON` as absolute path at setup | Plan artifacts are gitignored — phase worktrees won't have them. Absolute path ensures all agents access the same file. |
| Read `execution_mode` from plan.json at setup | Determines which dispatch protocol to follow |
| Validate schema before execution | Catches file-set overlap and structural issues early |
| Record PLAN_BASE_SHA before first phase | Final cross-phase review needs total diff |
| Record PHASE_BASE_SHA per phase | Per-phase review needs exact phase start |
| Use validate-plan for all status updates | Keeps plan.json and plan.md in sync |
| All tasks complete before advancing phase | Phase completion gate prevents unresolved work |
| Run gate checks at startup and after status changes | Entry gates prevent wasted work, base-branch checks prevent wrong-worktree dispatch, consistency checks catch state drift |

## Integration

**Workflow:** design → draft-plan → **this skill** → pr-create → pr-review → pr-merge
**See:** `tdd.md`
