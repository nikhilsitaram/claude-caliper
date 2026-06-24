---
name: implementation-review
description: Use when a multi-task implementation is complete and ready for holistic review before merging, or asked to review the current branch/diff as a whole
---

# Implementation Review

Per-task reviews verify each piece works. This review verifies the pieces work **together**.

## Two Modes

| Mode | When | Source of truth |
|------|------|-----------------|
| **Caliper** | A caliper plan drove the work (orchestrate auto-dispatches, or the user points at a `plan.json`) | plan.json + phase/completion docs + design doc |
| **Standalone** | No caliper plan exists — manual `/implementation-review`, or "review the whole branch/diff" | The git diff alone |

Detect the mode: if a caller supplied a `PLAN_DIR`/`plan.json` (orchestrate context), or the user explicitly references one, run **caliper mode**. Otherwise run **standalone mode** — don't hunt for a stale plan to attach.

## When to Use

- After all tasks complete in orchestrate (caliper, auto-dispatched)
- Between phases of a multi-phase plan (caliper, auto-dispatched by orchestrate after each phase)
- Before merging any feature branch — with or without a plan
- When asked to "review the whole thing", "review everything", or "review the current diff"

Skip if: single-module change or purely additive work with no cross-component interactions.

## Pre-Flight Checks

Before dispatching the reviewer:

1. **Run integration tests** — broad acceptance tests and boundary tests at cross-component seams should pass. If any fail, fix before proceeding.
2. **Fill gaps** — if any cross-component boundary lacks an executable (non-mocking) test, write one now. Don't dispatch until it passes; the reviewer's category-7 non-dismissibility rule will flag the gap as Important and trigger a re-dispatch loop.

## Resolve the Diff Range

The reviewer needs `BASE_SHA..HEAD_SHA` covering **all** the work under review.

**Caliper mode:** `BASE_SHA` is the phase start (`PHASE_BASE_SHA` from orchestrate) for phase-scoped reviews, or `PLAN_BASE_SHA` for the final review — not `git merge-base`. `HEAD_SHA` is `git rev-parse HEAD`.

**Standalone mode:** derive the branch's merge-base with the default branch.

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
git fetch origin
BASE_SHA=$(git merge-base "origin/$DEFAULT_BRANCH" HEAD)
HEAD_SHA=$(git rev-parse HEAD)
```

If `git diff HEAD` is non-empty there are uncommitted changes the range won't cover — tell the user to commit (or stash) them first, since the reviewer reads committed history.

## How to Dispatch

Use `subagent_type: "claude-caliper:implementation-reviewer"` with the invocation template in `./reviewer-prompt.md`. The agent's static behavior (8-category cross-task checklist, output format) is in the agent definition.

**Use `model: "$IMPL_REVIEWER_MODEL"`** — review requires strong reasoning to catch subtle cross-component issues.

Fill the template variables:

| Variable | Caliper mode | Standalone mode |
|----------|--------------|-----------------|
| `{BASE_SHA}` / `{HEAD_SHA}` | Phase/plan range (above) | merge-base range (above) |
| `{REPO_PATH}` | Repository root path | Repository root path |
| `{FEATURE_SUMMARY}` | What the feature does (1-2 sentences) | What the branch does — infer from commits/diff, or ask the user |
| `{TASK_LIST}` | `jq '.phases[N].tasks[] \| .id + ": " + .name'` | Omit — the prompt drops this section |
| `{PLAN_DIR}` / `{PHASE_DIR}` | Plan and phase directory paths | Omit — the prompt drops these |
| `{PHASE_CONTEXT}` | Phase letter/name + downstream expectations (empty for final/single-phase) | Empty |
| `{DESIGN_DOC_PATH}` | Path from plan frontmatter (or "None") | "None" — disables success-criteria category 8 |

The reviewer's first 7 categories (cross-component consistency, duplication, dead code, docs, errors, integration gaps, test coverage) run identically in both modes against the diff. Only category 8 (success-criteria fulfillment) and plan-doc bookkeeping are caliper-only.

## What It Catches

| Category | Example |
|----------|---------|
| Cross-component inconsistency | Config says port 3000, README says 8080 |
| Duplicated constants | Same timeout defined in two modules |
| Code duplication | Identical function in two files |
| Dead code from iteration | Conditional where both branches are identical |
| Documentation gaps | Feature supported but undocumented |
| Inconsistent errors | Same generic error from multiple locations |
| Missing boundary tests | Components interact but no integration test |
| Unmet success criteria | Design says "users can X" but implementation doesn't deliver it (caliper only) |

## Triage & Fix

When the reviewer returns, **display what it found, then proceed straight to fixing — don't stop for confirmation.** This is a visibility step, not an approval gate: silently fixing and dismissing leaves the user blind to what was wrong, but waiting on a confirmation reply stalls the run. Present a compact summary — group by severity, and for each issue give its `file:line`, category, and the one-line problem — then immediately continue into the fixes below. Continuation flags don't change this: findings are always shown, fixing always proceeds without a pause.

Address each:

- **Fix** actionable findings — verify against the code first, since the reviewer can be wrong.
- **Dismiss** false positives with a stated technical reason. Findings marked `non_dismissible: true` (category-7 seam-mock gaps) can't be dismissed — fix them or re-dispatch.

Run the relevant tests after fixing, then apply the Re-Review Gate.

## Post-Review: Plan Doc Updates (caliper only)

After review passes, the **orchestrator** updates the plan document. Skip this entirely in standalone mode.

1. **Document fixups** — append `### Implementation Review Changes` to `phase-{letter}/completion.md` listing each change. Omit if no fixups needed.

2. **Handoff notes (multi-phase only)** — if future phases exist, the orchestrator writes inline handoff notes on downstream task files now (post-review), so notes reflect the shipped interface including any review-driven changes. See orchestrate's Phase Wrap-Up step for format and trigger conditions.

## Re-Review Gate

Applies in both modes. Read the threshold: `caliper-settings get re_review_threshold` (default: 5). If the reviewer finds more issues than this threshold: after all fixes are applied, dispatch a fresh reviewer subagent with the same full review scope. This catches reviewer hallucination from compounding and new issues introduced by bulk fixes.

At or under the threshold, verify fixes and proceed without re-review.

## Continue the Workflow

By default the skill stops once the review passes and fixes land. These flags chain the next steps automatically — but only after the review fully passes (re-review gate included) and the user has seen the findings:

| Flag | Effect |
|------|--------|
| `--pr-create` | Invoke the pr-create skill to commit, push, and open a PR. |
| `--pr-review` | Invoke pr-create, then the pr-review skill. Forward any pr-review flags placed after it — `--automated-fix`/`-A`, `--automated-merge`/`-M`, or `--deliberate`/`-D`. |
| `--pr-merge` | Invoke pr-create, then pr-review in `--automated-merge` mode (which fixes all actionable feedback, then invokes pr-merge). This is the full merge chain — pr-create → pr-review → pr-merge — so don't skip pr-review and jump straight to pr-merge. Equivalent to `--pr-review --automated-merge`. |

`--pr-review` with no forwarded mode flag lets pr-review select its mode the usual way (configured `review_mode`, else prompt). These flags are for manual `/implementation-review`; in caliper mode orchestrate already drives pr-create after the review.

When more than one of these is passed, the most complete chain wins: `--pr-merge` over `--pr-review` over `--pr-create` (each includes the steps before it). If the review can't be made to pass (unresolved `non_dismissible` findings, or fixes keep failing tests), stop before the continuation rather than opening a PR on a failing review.

## Integration

**Auto-dispatched by:** orchestrate (caliper mode, after all tasks complete)

**Invoked manually:** `/implementation-review` on any branch (standalone mode)

**Leads to:** pr-create (once review passes)
