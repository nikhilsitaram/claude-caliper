# Implementer Invocation Template

Use this template when dispatching a task-implementer agent. The agent's static behavior (test-driven workflow, deviation rules, self-review, completion notes) is defined in the `claude-caliper:task-implementer` agent definition. This template provides only the dynamic per-invocation context.

**Variables:**
- `{TASK_ID}` — the task ID (e.g., A1)
- `{TASK_ID_LOWER}` — lowercase task ID (e.g., a1)
- `{TASK_METADATA}` — JSON task object from plan.json (strip `status` before injecting — orchestrator tracking state, not implementer guidance; keep `depends_on` — implementer may need it for boundary integration tests)
- `{TASK_PROSE}` — content of the task .md file
- `{PLAN_DIR}` — absolute path to plan directory
- `{PHASE_DIR}` — absolute path to phase directory
- `{TASK_IMPLEMENTER_MODEL}` — model for the implementer agent (from caliper-settings)
- `{WORKTREE_PATH}` — absolute path to the task's worktree (subagents mode only — orchestrator creates via `git worktree add`). In agent-teams mode, omit this variable — the teammate uses its auto-provisioned CWD.

```text
Agent(
  subagent_type: "claude-caliper:task-implementer",
  model: "{TASK_IMPLEMENTER_MODEL}",
  prompt: "You are implementing {TASK_ID}: [task name]

    ## Task Metadata (from plan.json)

    {TASK_METADATA}

    ## Task Instructions (from task file)

    {TASK_PROSE}

    ## Paths

    Plan directory: {PLAN_DIR}
    Phase directory: {PHASE_DIR}
    Working directory: {WORKTREE_PATH}  <!-- subagents mode only — omit this line in agent-teams mode -->

    ## Before You Begin

    Mark your task in-progress:
    validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status in_progress"
)
```
