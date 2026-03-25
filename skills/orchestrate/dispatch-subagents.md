# Dispatch Protocol: Subagents Mode

Parallel task execution via Agent tool dispatches with worktree isolation. No experimental env var needed.

## Dispatch Implementers

For each task with no unmet dependencies (verified via `scripts/validate-plan --check-deps`), dispatch an implementer subagent:

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  isolation: "worktree",
  run_in_background: true,
  prompt: "<substitute implementer-prompt.md with all {VARIABLES}>"
)
```

The `isolation: "worktree"` parameter gives each subagent its own git worktree automatically. Track each agent's ID mapped to its task ID.

**Note:** `--check-base` runs at orchestrate startup and before each phase dispatch (multi-phase). No separate dispatch-level base check is needed.

## Process Completions

When a background agent completes (push notification — do not poll):

1. Read the agent's return message for completion notes and task summary
2. Note the agent's worktree path and branch from the result (needed for review and fix cycles)
3. Dispatch a reviewer subagent (synchronous, not background):

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "<substitute task-reviewer-prompt.md with all {VARIABLES}
    Use the worktree path from the implementer agent's result.>"
)
```

4. Extract the last `json review-summary` block from reviewer output
5. Triage issues: "fix" or "dismiss" (with reasoning)

## Review Fix Cycle

If fixes needed, dispatch a **new** implementer subagent (subagents have no mailbox — the original agent is gone). Do NOT use `isolation: "worktree"` — that creates a new worktree from HEAD, which doesn't have the original implementation. Instead, pass the original agent's worktree path so the fix agent works on the same branch with the existing code.

Include in the prompt:
- Original task context (metadata + prose)
- Reviewer findings to address
- The worktree path from the original implementer agent

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Working directory: <original worktree path>
    <original task context + reviewer findings>"
)
```

Re-dispatch reviewer after fixes. Repeat until review passes (max 3 cycles, then escalate to user).

## After Review Passes

1. Mark task complete: `scripts/validate-plan --update-status plan.json --task {TASK_ID} --status complete`
2. Validate criteria: `scripts/validate-plan --criteria plan.json --task {TASK_ID}`
3. Merge the task's worktree branch into the feature/integration branch
4. Check if dependent tasks are now unblocked (`scripts/validate-plan --check-deps`)
5. Dispatch newly unblocked tasks (same pattern as above)

## Key Differences from Agent Teams

- No push-based idle notifications — use `run_in_background` completion events instead
- No mailbox messaging — review fixes require a fresh agent with the original context
- Worktrees are managed by the `isolation: "worktree"` parameter, not auto-provisioned by the teammate API
- Fix agents reuse the original worktree path (no `isolation: "worktree"`) to preserve implementation context
