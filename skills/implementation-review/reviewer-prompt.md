# Implementation Reviewer Invocation Template

The per-invocation context for an implementation-reviewer dispatch; the `claude-caliper:implementation-reviewer` agent definition holds its static behavior (8-category checklist, output and review-summary formats). It serves **caliper mode** (a plan drove the work) and **standalone mode** (diff-only branch review; see Standalone Mode).

## Variables

- `{FEATURE_SUMMARY}` — what the feature/branch does (1-2 sentences)
- `{TASK_LIST}` — extracted from plan.json: `jq '.phases[N].tasks[] | .id + ": " + .name'` (caliper only)
- `{REPO_PATH}` — repository root path
- `{BASE_SHA}` — caliper: phase/plan start SHA. Standalone: `git merge-base origin/<default> HEAD`
- `{HEAD_SHA}` — current tip (`git rev-parse HEAD`)
- `{PLAN_DIR}` — path to plan directory (caliper only)
- `{PHASE_DIR}` — path to current phase directory (caliper only)
- `{PHASE_CONTEXT}` — phase letter/name and downstream expectations, plus sibling phases' review changes when siblings ran in parallel (orchestrate `parallel-phases.md` Reviews); empty for final/single-phase; caliper only
- `{DESIGN_DOC_PATH}` — path to design doc, or "None" (always "None" in standalone mode)
- `{IMPL_REVIEWER_MODEL}` — model for the reviewer agent (from caliper-settings)

## Dispatch Example

```text
Agent(
  subagent_type: "claude-caliper:implementation-reviewer",
  model: "{IMPL_REVIEWER_MODEL}",
  prompt: "Review the complete feature implementation.

    ## Feature Summary

    {FEATURE_SUMMARY}

    ## Tasks Implemented

    {TASK_LIST}

    ## Git Range

    The code is at {REPO_PATH}

    git diff --stat {BASE_SHA}..{HEAD_SHA}
    git diff {BASE_SHA}..{HEAD_SHA}

    Read every file in the diff.

    ## Design Doc

    {DESIGN_DOC_PATH}

    If not 'None', read ONLY the Goal and Success Criteria sections.

    ## Phase Context

    {PHASE_CONTEXT}

    ## Plan Context

    Read {PLAN_DIR}/plan.json for task metadata.
    Read {PHASE_DIR}/completion.md for completion summary and deviations."
)
```

## Standalone Mode

When no caliper plan drove the work, the diff is the only source of truth. Use the same call with three changes: the first line reads "Review the complete branch implementation." under a `## Summary` heading; drop the `## Tasks Implemented` and `## Plan Context` sections; set Design Doc to `None.` and Phase Context to `(none — single standalone review)`. The reviewer runs categories 1–7; category 8 (success-criteria fulfillment) self-skips on a "None" design doc.
