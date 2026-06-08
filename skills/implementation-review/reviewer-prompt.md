# Implementation Reviewer Invocation Template

Use this template when dispatching an implementation-reviewer agent. The agent's static behavior (8-category cross-task checklist, integration test coverage, output format, review-summary format) is defined in the `claude-caliper:implementation-reviewer` agent definition. This template provides only the dynamic per-invocation context.

The template works for both **caliper mode** (a plan drove the work) and **standalone mode** (diff-only review of a branch). In standalone mode, omit the caliper-only sections — see "Standalone mode" below.

## Variables

- `{FEATURE_SUMMARY}` — what the feature/branch does (1-2 sentences)
- `{TASK_LIST}` — extracted from plan.json: `jq '.phases[N].tasks[] | .id + ": " + .name'` (caliper only)
- `{REPO_PATH}` — repository root path
- `{BASE_SHA}` — caliper: phase/plan start SHA. Standalone: `git merge-base origin/<default> HEAD`
- `{HEAD_SHA}` — current tip (`git rev-parse HEAD`)
- `{PLAN_DIR}` — path to plan directory (caliper only)
- `{PHASE_DIR}` — path to current phase directory (caliper only)
- `{PHASE_CONTEXT}` — phase letter/name and downstream expectations (empty for final/single-phase; caliper only)
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

When no caliper plan drove the work, drop the plan-derived sections — the diff is the only source of truth. The prompt collapses to:

```text
Agent(
  subagent_type: "claude-caliper:implementation-reviewer",
  model: "{IMPL_REVIEWER_MODEL}",
  prompt: "Review the complete branch implementation.

    ## Summary

    {FEATURE_SUMMARY}

    ## Git Range

    The code is at {REPO_PATH}

    git diff --stat {BASE_SHA}..{HEAD_SHA}
    git diff {BASE_SHA}..{HEAD_SHA}

    Read every file in the diff.

    ## Design Doc

    None.

    ## Phase Context

    (none — single standalone review)"
)
```

The reviewer runs categories 1–7 against the diff. Category 8 (success-criteria fulfillment) self-skips because the design doc is "None".
