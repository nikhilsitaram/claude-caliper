# Design Reviewer Invocation Template

Use this template when dispatching a design-reviewer agent. The agent's static behavior (8-point design checklist, output format, severity mapping, review-summary format) is defined in the `claude-caliper:design-reviewer` agent definition. This template provides only the dynamic per-invocation context.

## Variables

- `{DESIGN_DOC_PATH}` — path to the design doc
- `{REPO_PATH}` — repository root path (for reading existing files to verify paths)
- `{DESIGN_REVIEWER_MODEL}` — model for the reviewer agent (from caliper-settings)

## Dispatch Example

```text
Agent(
  subagent_type: "claude-caliper:design-reviewer",
  model: "{DESIGN_REVIEWER_MODEL}",
  prompt: "Review the design doc at {DESIGN_DOC_PATH}

    Codebase root: {REPO_PATH}
    Read existing files to verify paths and check for existing patterns."
)
```

Note: No `run_in_background` — `background: true` is in the agent definition frontmatter.
