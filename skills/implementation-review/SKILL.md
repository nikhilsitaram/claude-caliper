---
name: implementation-review
description: Use when a multi-task implementation is complete and ready for holistic review before merging
---

# Implementation Review

Per-task reviews verify each piece works. This review verifies the pieces work **together**.

## When to Use

- After all tasks complete in orchestrate (auto-dispatched)
- Before merging any multi-task feature branch
- Between phases of a multi-phase plan (auto-dispatched by orchestrate after each phase)
- When asked to "review the whole thing" or "review everything"

## Pre-Flight Checks

Before dispatching the reviewer:

1. **Run integration tests** — The first task's broad acceptance tests and boundary tests at cross-task seams should all pass. If any fail, fix before proceeding.
2. **Fill gaps** — if any cross-task boundary lacks a test, write one now.

Skip if: single-module change or purely additive tasks with no interactions.

## How to Dispatch

Use `subagent_type: "claude-caliper:implementation-reviewer"` with the invocation template in `./reviewer-prompt.md`. The agent's static behavior (8-category cross-task checklist, output format) is in the agent definition.

Template variables:

| Variable | Value |
|----------|-------|
| `{BASE_SHA}` | Phase start SHA (`PHASE_BASE_SHA` from orchestrate) — scopes diff to current phase only |
| `{HEAD_SHA}` | `git rev-parse HEAD` — current tip |
| `{FEATURE_SUMMARY}` | What the feature does (1-2 sentences) |
| `{TASK_LIST}` | Extract from plan.json: `jq '.phases[N].tasks[] \| .id + ": " + .name'` |
| `{PLAN_DIR}` | Path to plan directory |
| `{PHASE_DIR}` | Path to current phase directory |
| `{REPO_PATH}` | Repository root path |
| `{PHASE_CONTEXT}` | Phase letter and name (e.g., "Phase A of C: Core API"), and what downstream phases expect (interfaces, config, APIs). Empty string for final/single-phase reviews. |
| `{DESIGN_DOC_PATH}` | Path to design doc (from plan frontmatter, or "None") |

**Use `model: "$IMPL_REVIEWER_MODEL"`** — review requires strong reasoning to catch subtle cross-task issues.

**Use the full diff range** — `BASE_SHA..HEAD_SHA` must cover ALL tasks, not just the last one.

**Phase-scoped reviews:** For inter-phase reviews, `BASE_SHA` is the commit before the phase's first task — not `git merge-base origin/main`. This scopes the diff to only the current phase's changes.

## What It Catches

| Category | Example |
|----------|---------|
| Cross-task inconsistency | Config says port 3000, README says 8080 |
| Duplicated constants | Same timeout defined in two modules |
| Code duplication | Identical function in two files |
| Dead code from iteration | Conditional where both branches are identical |
| Documentation gaps | Feature supported but undocumented |
| Inconsistent errors | Same generic error from multiple locations |
| Missing boundary tests | Components interact but no integration test |
| Unmet success criteria | Design says "users can X" but implementation doesn't deliver it |

## Post-Review: Plan Doc Updates

After review passes, the **orchestrator** updates the plan document:

1. **Document fixups** — append `### Implementation Review Changes` to `phase-{letter}/completion.md` listing each change. Omit if no fixups needed.

2. **Handoff notes (multi-phase only)** — if future phases exist, the orchestrator writes inline handoff notes on downstream task files now (post-review), so notes reflect the shipped interface including any review-driven changes. See orchestrate's Phase Wrap-Up step for format and trigger conditions.

## Re-Review Gate

Read the threshold: `caliper-settings get re_review_threshold` (default: 5). If the reviewer finds more issues than this threshold: after all fixes are applied, dispatch a fresh reviewer subagent with the same full review scope. This catches reviewer hallucination from compounding and new issues introduced by bulk fixes.

At or under the threshold, the orchestrator verifies fixes and proceeds without re-review.

## Integration

**Auto-dispatched by:** orchestrate (after all tasks complete)

**Leads to:** pr-create (once review passes)
