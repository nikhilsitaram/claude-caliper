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
- **Design doc** — absolute path under `$MAIN_ROOT/.claude/claude-caliper/YYYY-MM-DD-topic/design-topic.md` (main repo, not worktree)
- **Repo root** — the worktree the design targets

Dispatch with `model: "$DESIGN_REVIEWER_MODEL"` — review requires strong reasoning to catch blind spots the designer and user converged past.

Use `subagent_type: "claude-caliper:design-reviewer"`. **See:** reviewer-prompt.md for invocation template.

## 9-Point Checklist

1. **Problem Clarity** — specific problem, who is affected, consequences of not solving
2. **Success Criteria Quality** — human-verifiable, implementation-independent, collectively complete, individually necessary
3. **Architecture-Problem Fit** — architecture addresses stated problem, feasibility risks identified
4. **Alternative Assessment** — considers more effective or efficient approaches
5. **Scope Alignment** — solves stated problem and not more, non-goals correctly scoped
6. **Decision Justification** — key decisions include trade-off analysis
7. **Internal Consistency** — names, paths, concepts consistent across sections
8. **Test Strategy Coverage** — Test Strategy section names a non-mocking integration test for every cross-module data flow, or explains why none exists
9. **Handoff Quality** — plan drafter with zero context can produce correct plan from doc alone

## Output

Reviewer produces:
- Issues Found (category, problem, fix with specific text suggestions)
- Assessment table (PASS/FAIL per check)
- "Ready for planning?" verdict

**Pass:** Zero issues, or all issues fixed and confirmed clean
**Fail:** Return to design skill to fix, then re-run design-review

**Review loop (two-pass cap):** The design skill controls the loop: pass 1 is discovery. The lead fixes all findings and verifies each fix inline (grep/read). A delta pass 2 is dispatched only if pass 1 found critical or high issues; after pass 2, any remaining findings are fixed inline and the loop records pass — never a third dispatch. Delta dispatches receive the prior pass's issues with resolution status, enabling verify-then-scan instead of full re-discovery.

Note: Plan-review runs the same two-pass cap (see `skills/plan-review/SKILL.md`).

## Integration

**Auto-dispatched by:** design (after design doc written)

**Leads to:** draft-plan (once review passes)
