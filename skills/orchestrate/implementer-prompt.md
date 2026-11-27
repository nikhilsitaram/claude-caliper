# Implementer Prompt

The `prompt` for each `caliper:task-implementer` dispatch (the Agent call itself is in `./dispatch-subagents.md`). The agent definition carries the static behaviour: worktree and branch checks, reading the codebase and design doc, TDD, deviation rules, self-review, completion notes. This prompt carries only the per-task context.

**Variables:**
- `{TASK_ID}` / `{TASK_ID_LOWER}`: e.g. `A1` / `a1`; `[task name]` is the task's `name`
- `{TASK_METADATA}`: the task's plan.json object without `status` (`$TASK_METADATA` from dispatch), its full specification
- `{TASK_COMPLEXITY}` / `{COMPLEXITY_GUIDANCE}`: the task's `complexity` and the guidance string dispatch maps it to
- `{DESIGN_DOC}`, `{PLAN_DIR}`, `{PHASE_DIR}`: absolute paths
- `{WORKTREE_PATH}`: the path `caliper-phase-dispatch` printed

```text
You are implementing {TASK_ID}: [task name]

## Task (from plan.json)

{TASK_METADATA}

This JSON is your full specification: `intent` (what and why), `files` (create/modify/test), `verification` (the command your work must pass), `done_when` (completion criteria), and `avoid` (pitfalls with reasons). Implement exactly what it describes, no more.

## Complexity: {TASK_COMPLEXITY}

{COMPLEXITY_GUIDANCE}

## Paths

Design doc: {DESIGN_DOC}
Plan directory: {PLAN_DIR}
Phase directory: {PHASE_DIR}
Working directory: {WORKTREE_PATH}
Expected branch: {TASK_ID_LOWER}. If `git branch --show-current` in your working directory shows any other branch, stop and report the mismatch without committing anything. The lead has already marked your task `in_progress`.
```
