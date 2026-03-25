# Dispatch Protocol: Main Context Mode

Sequential task execution where the lead implements each task directly. No subagent dispatch for implementation, no teammates. Best for small plans (≤5 tasks).

## Execute Tasks

Process tasks in dependency order (use `scripts/validate-plan --check-deps` to verify). For each task:

1. Mark in-progress: `scripts/validate-plan --update-status plan.json --task {TASK_ID} --status in_progress`
2. Read the task .md file and metadata from plan.json
3. Implement the task directly — follow TDD discipline per **See:** `./tdd.md`
4. Run the task's verification command
5. Write completion notes to `{PHASE_DIR}/{TASK_ID_LOWER}-completion.md`
6. Commit the work
7. Mark complete: `scripts/validate-plan --update-status plan.json --task {TASK_ID} --status complete`

## Task Review

After each task, dispatch a synchronous reviewer subagent (fresh-eyes review requires a separate agent even in main context mode):

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "<substitute task-reviewer-prompt.md with all {VARIABLES}
    REPO_PATH is the current worktree.
    BASE_SHA and HEAD_SHA bracket this task's commits.>"
)
```

Extract the last `json review-summary` block. Triage issues: "fix" or "dismiss".

If fixes needed, the lead fixes directly (no dispatch needed — you are the implementer). Re-dispatch reviewer after fixes. Repeat until review passes (max 3 cycles, then escalate).

## After Review Passes

1. Validate criteria: `scripts/validate-plan --criteria plan.json --task {TASK_ID}`
2. Move to the next task in dependency order

## Key Differences from Other Modes

- No parallelism — tasks run one at a time
- Lead implements directly (no dispatch overhead)
- Review fixes are immediate (no fresh agent needed, no mailbox)
- Simplest mode: lowest token cost, easiest to debug, but slowest for multi-task plans
