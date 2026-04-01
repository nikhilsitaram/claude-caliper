---
name: design-review
description: Use when a design doc has been written and before draft-plan is dispatched
---

# Design Review

Dispatch a reviewer subagent to validate a design doc before planning. Catches spec gaps that are cheap to fix in design but expensive to fix mid-implementation.

**Core principle:** Designs are hypotheses about what to build. Validate before committing to a plan.

## When to Use

- After the design skill writes a design doc (auto-dispatched)
- When asked to review any existing design doc
- Before draft-plan is dispatched (hard gate)

**Skip for:** Trivially small changes with no design doc.

## Dispatch

Gather inputs:
- **Design doc** — `.claude/claude-caliper/YYYY-MM-DD-topic/design-topic.md`
- **Repo root** — the worktree the design targets

Dispatch with `model: "$DESIGN_REVIEWER_MODEL"` — review requires strong reasoning to catch blind spots the designer and user converged past.

**See:** reviewer-prompt.md

## 8-Point Checklist

1. **Problem Clarity** — specific problem, who is affected, consequences of not solving
2. **Success Criteria Quality** — human-verifiable, implementation-independent, collectively complete, individually necessary
3. **Architecture-Problem Fit** — architecture addresses stated problem, feasibility risks identified
4. **Alternative Assessment** — considers more effective or efficient approaches
5. **Scope Alignment** — solves stated problem and not more, non-goals correctly scoped
6. **Decision Justification** — key decisions include trade-off analysis
7. **Internal Consistency** — names, paths, concepts consistent across sections
8. **Handoff Quality** — plan drafter with zero context can produce correct plan from doc alone

## Output

Reviewer produces:
- Issues Found (category, problem, fix with specific text suggestions)
- Assessment table (PASS/FAIL per check)
- "Ready for planning?" verdict

**Pass:** Zero issues, or all issues fixed and confirmed clean
**Fail:** Return to design skill to fix, then re-run design-review

**Re-review gate:** Read the threshold: `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get re_review_threshold` (default: 5). If the reviewer finds more issues than this threshold, after all fixes, dispatch a fresh reviewer with the same full scope to confirm clean.

## Integration

**Auto-dispatched by:** design (after design doc written)

**Leads to:** draft-plan (once review passes)
