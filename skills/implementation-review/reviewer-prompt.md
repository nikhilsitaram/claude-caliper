# Implementation Reviewer Invocation Template

Use this template when dispatching an implementation-reviewer agent. The agent's static behavior (8-category cross-task checklist, integration test coverage, output format, review-summary format) is defined in the `claude-caliper:implementation-reviewer` agent definition. This template provides only the dynamic per-invocation context.

## Variables

- `{FEATURE_SUMMARY}` — what the feature does (1-2 sentences)
- `{TASK_LIST}` — extracted from plan.json: `jq '.phases[N].tasks[] | .id + ": " + .name'`
- `{REPO_PATH}` — repository root path
- `{BASE_SHA}` — phase start SHA (scopes diff to current phase)
- `{HEAD_SHA}` — current tip (`git rev-parse HEAD`)
- `{PLAN_DIR}` — path to plan directory
- `{PHASE_DIR}` — path to current phase directory
- `{PHASE_CONTEXT}` — phase letter/name and downstream expectations (empty for final/single-phase)
- `{DESIGN_DOC_PATH}` — path to design doc (or "None")
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
