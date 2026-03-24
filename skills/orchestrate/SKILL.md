---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute plans via agent teams. Phases run sequentially; tasks within each phase run in parallel as teammates. Push-based idle notifications replace polling.

**Core principle:** The lead dispatches teammates — only implementer teammates touch code.

## Requires

```bash
[ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "1" ] || { echo "Agent teams not enabled"; exit 1; }
```

If the environment variable is not set, stop and tell the user to enable it.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./implementer-prompt.md` | Task implementer teammate |
| `./task-reviewer-prompt.md` | Per-task reviewer teammate |
| `skills/implementation-review/reviewer-prompt.md` | Cross-task reviewer (lead dispatches) |

## Progress Tracking

TaskCreate per phase: "Execute tasks ({N})", "Implementation review", "Create PR". Final: "Mark plan complete". Set `addBlockedBy`. Mark `in_progress` / `completed` as you go.

## Setup

Before first phase:
- Read workflow: `WORKFLOW=$(jq -r '.workflow' plan.json)`
- Count phases: `PHASE_COUNT=$(jq '.phases | length' plan.json)`
- Validate schema: `scripts/validate-plan --schema plan.json`
- `scripts/validate-plan --update-status plan.json --plan --status "In Development"`
- `PLAN_BASE_SHA=$(git rev-parse HEAD)`
- `PLAN_DIR=$(dirname "$(realpath plan.json)")` and `[ -f "$PLAN_DIR/reviews.json" ] || echo '[]' > "$PLAN_DIR/reviews.json"`
- Push branch: `git push -u origin HEAD`

## Per-Phase Execution (Sequential)

Process phases in order (A, B, C...). For each phase:

### Prepare Phase

1. Create phase worktree from integration branch (multi-phase) or use feature worktree (single-phase)
2. `PHASE_BASE_SHA=$(git rev-parse HEAD)` in worktree
3. **Bootstrap dependencies** in the worktree. **See:** skills/design/dependency-bootstrap.md
4. Extract context: tasks JSON, plan dir, phase dir, prior completions (from depends_on closure)
5. Cross-phase handoff notes: lead writes handoff sections to task .md files for tasks consuming prior-phase output

### Spawn Implementer Teammates

Spawn one implementer teammate per task in the phase (parallel). Each teammate:
- Receives task metadata + prose from `./implementer-prompt.md`
- Gets its own auto-provisioned worktree
- Manages its own lifecycle (marks in-progress, writes completion notes, marks complete)

### Process Completions (Push-Based)

When an implementer teammate goes idle (push notification — no polling):

1. Read the teammate's completion notes (`{PHASE_DIR}/{task_id_lower}-completion.md`)
2. Dispatch a reviewer teammate (`./task-reviewer-prompt.md`) with `PHASE_BASE_SHA..HEAD`
3. When reviewer goes idle, extract the last `json review-summary` block
4. Triage issues: "fix" (send to implementer via mailbox) or "dismiss" (document reasoning)
5. If fixes needed: send review feedback to the *original implementer* via mailbox messaging — the implementer still has context and files. Implementer fixes and goes idle again. Repeat until review passes.
6. Validate with `scripts/validate-plan --criteria plan.json --task {TASK_ID}`
7. Kill teammate only after review passes and criteria met

**Phase completion gate:** Lead cannot advance until ALL teammates for this phase (implementers and reviewers) are terminated.

### Handle Escalations

Teammates send Rule 4 violations (architectural changes) to lead via mailbox. Lead presents to user: what change, which task, why plan doesn't cover it. Wait for user decision.

### Phase Wrap-Up

After all teammates killed:
1. Merge task branches into feature/integration branch
2. Dispatch implementation-review with `PHASE_BASE_SHA..HEAD`, run Review Loop Protocol (scope: `phase-{letter_lower}`)
3. `scripts/validate-plan --check-review plan.json --type impl-review --scope phase-{letter_lower}`
4. Append review changes to `${PHASE_DIR}/completion.md`
5. Run phase criteria: `scripts/validate-plan --criteria plan.json --phase {LETTER}`
6. Update status: `scripts/validate-plan --update-status plan.json --phase {LETTER} --status "Complete (YYYY-MM-DD)"`
7. (Multi-phase) Create phase PR, external review gate, merge, clean up worktree

## Review Loop Protocol

After each impl-review dispatch:

1. Extract last `json review-summary` fenced block from response. Missing/malformed -> verdict:fail, re-dispatch.
2. Triage issues: "fix" (dispatch implementer) or "dismiss" (with reasoning)
3. actionable == 0 -> write reviews.json record with verdict:pass, advance
4. actionable 1-5 -> fix all, verify, write record verdict:pass, advance
5. actionable > 5 -> fix all, write record verdict:fail, re-dispatch (max 3 iterations, then escalate via AskUserQuestion)

Append record to `{PLAN_DIR}/reviews.json`:
`{"type":"impl-review","scope":"{SCOPE}","iteration":N,"issues_found":N,"severity":{...},"actionable":N,"dismissed":N,"dismissals":[...],"fixed":N,"remaining":0,"verdict":"pass|fail","timestamp":"ISO8601"}`

## Single-Phase Plans

Skip integration branch and phase worktrees. Work directly in the feature worktree:

1. Spawn implementer teammates, process completions, wrap up (same protocol as above)
2. Dispatch implementation-review, run Review Loop Protocol (scope: `phase-a`)
3. `scripts/validate-plan --check-review plan.json --type impl-review --scope phase-a`
4. Run plan criteria: `scripts/validate-plan --criteria plan.json --plan`
5. `scripts/validate-plan --update-status plan.json --plan --status Complete`
6. Route on workflow:
   - `"create-pr"`: invoke create-pr (targets main), `scripts/validate-plan --check-workflow plan.json`, stop
   - `"merge-pr"`: invoke create-pr, poll checks + review-pr --automated (skip if `review_wait_minutes` is 0), then merge-pr with `--squash`, `scripts/validate-plan --check-workflow plan.json`

## After All Phases (Multi-Phase Only)

1. Run plan criteria: `scripts/validate-plan --criteria plan.json --plan`. If exit 1, do not mark complete.
2. Final review: dispatch implementation-review with `PLAN_BASE_SHA..HEAD`, run Review Loop Protocol (scope: `final`)
3. `scripts/validate-plan --check-review plan.json --type impl-review --scope final`
4. `scripts/validate-plan --update-status plan.json --plan --status Complete`
5. Route on workflow:
   - `"merge-pr"`: create final PR, poll checks, review-pr --automated, merge-pr with `--rebase`, `scripts/validate-plan --check-workflow plan.json`, clean up
   - `"create-pr"`: create final PR, `scripts/validate-plan --check-workflow plan.json`, stop

**Continuity:** Run continuously. Pause only for Rule 4 violations and merge confirmation in merge-pr.

## Key Constraints

| Constraint | Why |
|------------|-----|
| Check `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` | Feature flag required for teammate API |
| Validate schema before execution | Catches file-set overlap and structural issues early |
| Record PLAN_BASE_SHA before first phase | Final cross-phase review needs total diff |
| Record PHASE_BASE_SHA per phase | Per-phase review needs exact phase start |
| Use validate-plan for all status updates | Keeps plan.json and plan.md in sync |
| Kill all teammates before advancing phase | Phase completion gate prevents unresolved work |

## Integration

**Workflow:** design -> draft-plan -> **this skill** -> create-pr -> review-pr -> merge-pr
**See:** `tdd.md` -- TDD reference embedded in implementer prompts
