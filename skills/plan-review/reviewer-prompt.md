# Plan Reviewer Invocation Template

Use this template when dispatching a plan-reviewer agent. The agent's static behavior (7-point plan checklist, output format, severity mapping, review-summary format) is defined in the `claude-caliper:plan-reviewer` agent definition. This template provides only the dynamic per-invocation context.

## Variables

- `{PLAN_DIR}` -- path to plan directory (contains plan.json + phase dirs)
- `{DESIGN_DOC_PATH}` -- path to design doc (or "None" to skip design checks)
- `{REPO_PATH}` -- repository root path (for reading existing files)
- `{PLAN_REVIEWER_MODEL}` -- model for the reviewer agent (from caliper-settings)

## Dispatch Example

```text
Agent(
  subagent_type: "claude-caliper:plan-reviewer",
  model: "{PLAN_REVIEWER_MODEL}",
  prompt: "Review the implementation plan at {PLAN_DIR}/plan.json

    Design doc: {DESIGN_DOC_PATH}
    Codebase root: {REPO_PATH}

    Read plan.json for structured metadata. Read individual task files
    in phase-{letter}/ directories for prose (steps, avoid, verification)."
)
```
