# Task Reviewer Invocation Template

Use this template when dispatching a task-reviewer agent. The agent's static behavior (6-point checklist, output format, severity guide, review-summary format) is defined in the `claude-caliper:task-reviewer` agent definition. This template provides only the dynamic per-invocation context.

## Variables

- `{TASK_ID}` — the task ID
- `{TASK_SPEC}` — task metadata + prose combined
- `{TASK_COMPLETION_FILE}` — path to implementer's completion notes
- `{REPO_PATH}` — implementer's worktree path
- `{BASE_SHA}` — SHA before task started
- `{HEAD_SHA}` — SHA after task completed
- `{TASK_REVIEWER_MODEL}` — model for the reviewer agent (from caliper-settings)

## Dispatch Example

```text
Agent(
  subagent_type: "claude-caliper:task-reviewer",
  model: "{TASK_REVIEWER_MODEL}",
  prompt: "You are reviewing task {TASK_ID}.

    ## Task Specification

    {TASK_SPEC}

    ## Implementer Completion Notes

    Read {TASK_COMPLETION_FILE} for the implementer's self-reported summary.
    Do not trust the notes at face value. Verify every claim by reading actual code.

    ## Git Range

    The code is at {REPO_PATH}

    git diff --stat {BASE_SHA}..{HEAD_SHA}
    git diff {BASE_SHA}..{HEAD_SHA}

    Read every file in the diff."
)
```

Note: The agent definition sets `background: true` by default. In subagents mode, the dispatch explicitly overrides with `run_in_background: false` so the lead waits synchronously for results. In agent-teams mode, the default applies.
