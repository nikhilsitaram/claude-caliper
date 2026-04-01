# Dispatch Protocol: Subagents Mode

Parallel task execution via Agent tool dispatches with worktree isolation. No experimental env var needed.

## Dispatch Implementers

For each task with no unmet dependencies (verified via `scripts/validate-plan --check-deps`), create a worktree from the feature branch and dispatch an implementer:

```bash
git worktree add .claude/worktrees/{TASK_ID_LOWER} -b {TASK_ID_LOWER} HEAD
```

Then dispatch the agent, passing the worktree path in the prompt:

```text
Agent(
  subagent_type: "claude-caliper:task-implementer",
  model: "{TASK_IMPLEMENTER_MODEL}",
  prompt: "<substitute implementer-prompt.md with all {VARIABLES}, including {WORKTREE_PATH}>"
)
```

The agent runs in background automatically (defined in agent frontmatter). Track each agent's name mapped to its task ID and worktree path.

**Note:** `--check-base` runs at orchestrate startup and before each phase dispatch (multi-phase). No separate dispatch-level base check is needed.

## Process Completions

When a background agent completes (push notification — do not poll):

1. Read the agent's return message for completion notes and task summary
2. Dispatch a reviewer (synchronous — override background with `run_in_background: false` so the lead waits for results):

```text
Agent(
  subagent_type: "claude-caliper:task-reviewer",
  model: "{TASK_REVIEWER_MODEL}",
  run_in_background: false,
  prompt: "<substitute task-reviewer-prompt.md with all {VARIABLES}>"
)
```

3. Extract the last `json review-summary` block from reviewer output
4. Triage issues: "fix" or "dismiss" (with reasoning)

## Review Fix Cycle

If fixes needed, the lead fixes directly in the task worktree using absolute paths — no fix agent needed. The orchestrator created the worktree and tracked the mapping, so it already knows the path.

1. Read the reviewer's findings
2. Fix the code directly in the task worktree using absolute paths: `{WORKTREE_PATH}/path/to/file`
3. Commit fixes in the worktree
4. Re-dispatch reviewer with updated HEAD_SHA
5. Repeat until review passes (max 3 cycles, then escalate to user)

## After Review Passes (or Skip)

For trivial tasks (one-liner, config change, rename) where a full reviewer dispatch is overhead, you may skip the review and record a skip with justification instead. The consistency check accepts both `pass` and `skip` verdicts.

1. Record the task-review in `reviews.json` (in the plan directory alongside plan.json):
   ```bash
   jq '. += [{"type":"task-review","scope":"{TASK_ID}","verdict":"pass","remaining":0}]' "$PLAN_DIR/reviews.json" > "$PLAN_DIR/reviews.json.tmp" && mv "$PLAN_DIR/reviews.json.tmp" "$PLAN_DIR/reviews.json"
   ```
   To skip review: use `"verdict":"skip","reason":"<justification>"` instead of `"verdict":"pass"`.
   If `reviews.json` doesn't exist yet, create it: `echo '[]' > "$PLAN_DIR/reviews.json"` first.
2. Mark task complete: `scripts/validate-plan --update-status plan.json --task {TASK_ID} --status complete`
3. Validate criteria: `scripts/validate-plan --criteria plan.json --task {TASK_ID}`
4. Merge and clean up the agent's worktree:
   - Never `cd` into an agent worktree — always use `git -C <agent-worktree-path>` for inspection commands (`git log`, `git status`, `git diff`). This prevents CWD from pointing at a path that gets deleted during cleanup.
   - Merge: `git -C <your worktree path> merge <agent-branch>`
   - Clean up: `git worktree remove <agent-worktree-path>` then `git branch -d <agent-branch>`
   - Reset CWD after removal: `cd <feature-worktree-path> && pwd` — run this after every worktree removal even if you believe CWD hasn't drifted
5. Check if dependent tasks are now unblocked (`scripts/validate-plan --check-deps`)
6. Dispatch newly unblocked tasks (same pattern as above)

## Key Differences from Agent Teams

- No push-based idle notifications — use background agent completion events instead
- No mailbox messaging — lead fixes directly using absolute paths
- Worktrees are created by the orchestrator via `git worktree add` from the feature branch
- Lead fixes directly in the task worktree using absolute paths — no fix agent needed
