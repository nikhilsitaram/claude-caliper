# Implementer Invocation Template

Use this template when dispatching a task-implementer agent. The agent's static behavior (test-driven workflow, deviation rules, self-review, completion notes) is defined in the `claude-caliper:task-implementer` agent definition. This template provides only the dynamic per-invocation context.

The implementer reads the codebase directly at full context — the prompt carries the task's plan.json entry and the design-doc path, not pasted implementation code.

**Variables:**
- `{TASK_ID}` — the task ID (e.g., A1)
- `{TASK_ID_LOWER}` — lowercase task ID (e.g., a1)
- `{TASK_METADATA}` — the task's JSON object from plan.json (strip `status` before injecting — orchestrator tracking state, not implementer guidance; keep `depends_on`, `intent`, `files`, `verification`, `done_when`, `avoid`, `complexity`). This is the task's full specification.
- `{DESIGN_DOC}` — absolute path to the design doc (the implementer reads it for feature-wide context and rationale)
- `{PLAN_DIR}` — absolute path to plan directory
- `{PHASE_DIR}` — absolute path to phase directory
- `{TASK_IMPLEMENTER_MODEL}` — model for the implementer agent (from caliper-settings)
- `{TASK_COMPLEXITY}` — the task's complexity level (low, medium, or high)
- `{COMPLEXITY_GUIDANCE}` — dispatcher-resolved string — the orchestrator maps `{TASK_COMPLEXITY}` to one of the three fixed guidance strings before building the prompt; this is not a raw template variable passed by the implementer.
- `{WORKTREE_PATH}` — absolute path to the task's worktree (orchestrator creates it via `git worktree add`)

```text
Agent(
  subagent_type: "claude-caliper:task-implementer",
  model: "{TASK_IMPLEMENTER_MODEL}",
  # complexity: "{TASK_COMPLEXITY}"  # TODO: uncomment when Agent tool supports complexity/effort parameter
  prompt: "You are implementing {TASK_ID}: [task name]

    ## Task (from plan.json)

    {TASK_METADATA}

    This JSON is your full specification: `intent` (what and why), `files` (create/modify/test), `verification` (the command your work must pass), `done_when` (completion criteria), and `avoid` (pitfalls with reasons). Implement exactly what it describes — no more.

    ## Read the Codebase Directly

    You have full context. Do not expect pasted implementation code — read the actual files the task touches and their neighbors to learn the conventions, then follow them. For feature-wide rationale and how this task fits the larger design, read the design doc at {DESIGN_DOC}.

    ## Complexity: {TASK_COMPLEXITY}

    {COMPLEXITY_GUIDANCE}

    ## Paths

    Design doc: {DESIGN_DOC}
    Plan directory: {PLAN_DIR}
    Phase directory: {PHASE_DIR}
    Working directory: {WORKTREE_PATH}

    ## Before You Begin

    1. Navigate to your worktree and verify you are on the correct branch:
       ```bash
       cd {WORKTREE_PATH} && git branch --show-current
       ```
       Output must be `{TASK_ID_LOWER}`. If it shows any other branch, stop and report the mismatch — do not commit anything.

    2. Mark your task in-progress:
       ```bash
       validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status in_progress
       ```"
)
```
