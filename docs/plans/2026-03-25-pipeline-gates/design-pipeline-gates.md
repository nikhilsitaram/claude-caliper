# Design: Pipeline Enforcement Gates

## Problem

The orchestration pipeline has three enforcement gaps:

1. **State drift (#119):** Plan state can become logically inconsistent — a phase can show "Not Started" while its tasks are "complete", or a task can be "complete" while its dependency is still "pending". validate-plan catches some of this (complete phase with incomplete tasks) but misses the reverse direction and dependency ordering checks.

2. **Missing entry gates (#132):** Review gates exist as *exit gates* (can't mark plan Complete without reviews) but not *entry gates*. You can start execution without plan-review passing, wasting work that gets blocked later. draft-plan can run without design-review.

3. **Wrong worktree base (#133):** When orchestrate dispatches phase work, `isolation: "worktree"` branches from the current repo HEAD. If the lead runs from the main checkout instead of the integration worktree, phase worktrees silently branch from main — missing all prior-phase output.

**Who's affected:** Anyone using orchestrate for multi-task plans. State drift confuses automated consumers (plan.md rendering, status gates) and human readers. Missing entry gates cause wasted work. Wrong base branches cause silent implementation errors.

## Goal

Make the pipeline self-enforcing: invalid states are caught deterministically by validate-plan, entry prerequisites are checked before work begins, and dispatch happens from the correct branch.

## Success Criteria

1. `validate-plan --consistency plan.json` exits non-zero when phase status contradicts task statuses (either direction)
2. `validate-plan --consistency plan.json` exits non-zero when a "complete" task has a pending/in-progress dependency
3. `validate-plan --check-entry <plan-dir> --stage execution` exits non-zero when plan-review has not passed
4. `validate-plan --check-entry <plan-dir> --stage draft-plan` exits non-zero when design-review has not passed
5. `validate-plan --check-base plan.json` exits non-zero when current branch is `main`/`master` (single-phase) or doesn't match `integration_branch` (multi-phase)
6. Orchestrate skill calls all three gates at startup and fails fast on violations
7. All existing validate-plan tests continue to pass (no regressions)

## Architecture

Three new validate-plan modes, one schema addition:

### `--consistency plan.json`

Six rules, all hard errors:

| # | Rule | Direction |
|---|------|-----------|
| 1 | Phase "Not Started" but has tasks "in_progress" or "complete" | task → phase |
| 2 | Phase "Complete" but has tasks not "complete"/"skipped" | phase → task |
| 3 | Task "complete" but a dependency is "pending"/"in_progress" | dependency ordering |
| 4 | Plan "Not Yet Started" but has phases "In Progress"/"Complete" | phase → plan |
| 5 | Plan "Complete" but has phases not "Complete" | plan → phase |
| 6 | Phase "Complete" without passing impl-review record | status ↔ review |

Rules 2 and 5 currently live in `--schema`. They move to `--consistency` (state checks, not structural). `--schema` calls `--consistency` internally so existing callers aren't broken.

### `--check-entry <plan-dir> --stage <stage>`

| Stage | Prerequisites | Called by |
|-------|--------------|----------|
| `draft-plan` | design-review passed in reviews.json | draft-plan skill at startup |
| `execution` | design-review + plan-review passed | orchestrate skill at startup |

Reads `<plan-dir>/reviews.json` and calls existing `check_review_record` function. Fails with actionable message naming the missing review and how to fix it.

### `--check-base plan.json`

| Plan type | Check |
|-----------|-------|
| Multi-phase (`integration_branch` field present) | Current branch == `integration_branch` value |
| Single-phase (no `integration_branch`) | Current branch is NOT `main` or `master` |

### Schema addition: `integration_branch`

Optional string field in plan.json root. Set by the design skill when creating an integration worktree for multi-phase plans. `--schema` validates it's a non-empty string if present.

## Key Decisions

1. **Separate `--consistency` flag** (not folded into `--schema`): Structural validation and state validation serve different purposes. `--schema` answers "is this valid JSON structure?" while `--consistency` answers "are the runtime states logically coherent?" However, `--schema` calls `--consistency` internally so no existing caller loses coverage.

2. **`integration_branch` tracked in plan.json** (not derived from naming conventions): Explicit field is auditable and survives convention changes. The design skill writes it; validate-plan reads it.

3. **Entry gates in validate-plan** (not hooks): Skills call gates explicitly. If a skill forgets, exit gates in `--update-status` still catch it. Hook-based gating is fragile for skill interception.

4. **`--check-entry` takes plan-dir** (not plan.json): At the `draft-plan` stage, plan.json doesn't exist yet — only reviews.json does. Using the directory as the argument works for both stages.

5. **All consistency rules are hard errors** (no warnings): "All tasks done but phase In Progress" is not flagged — that's a normal transient state during review. Only clearly inconsistent states (phase "Not Started" with active tasks, complete task with pending dependency) are errors.

## Non-Goals

- **Retroactive enforcement on existing plans:** Old plans without `integration_branch` won't fail `--schema`; the field is optional.
- **Auto-fixing inconsistencies:** `--consistency` reports, doesn't repair. Orchestrate handles status updates; this catches bugs in that logic.
- **Hook-based auto-gating:** Skills call gates explicitly.

## Implementation Approach

Single phase. All changes target one script (validate-plan), three new test files, and minor skill doc additions. No dependency layers between the three features. ~10 tasks estimated.

### Skill changes

- **orchestrate/SKILL.md:** Add `--check-entry`, `--check-base`, and `--consistency` calls to setup. Re-run `--check-base` before each phase dispatch (multi-phase). Re-run `--consistency` after each status update.
- **draft-plan/SKILL.md:** Add `--check-entry $PLAN_DIR --stage draft-plan` at startup.
- **design/SKILL.md:** Write `integration_branch` to plan.json when creating integration worktree (multi-phase only).
- **dispatch-subagents.md / dispatch-agent-teams.md:** Document that `--check-base` runs at startup and before each phase — no separate dispatch-level checks needed.

### Test files

- `tests/validate-plan/test_consistency.sh` — All 6 consistency rules
- `tests/validate-plan/test_check_entry.sh` — Both stages, missing/present reviews
- `tests/validate-plan/test_check_base.sh` — Integration branch match, main rejection, single-phase
