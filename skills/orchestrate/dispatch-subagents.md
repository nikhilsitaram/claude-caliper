# Dispatch Protocol: Subagents Mode

Parallel task execution via Agent tool dispatches with worktree isolation. No experimental env var needed.

## Dispatch Implementers

For each task in the phase, check deps: `validate-plan --check-deps "$PLAN_JSON" --task {TASK_ID}`. Collect all tasks that pass. For each ready task, create a worktree and extract metadata (strip `status` — orchestrator state not needed by implementer):

```bash
git worktree add .claude/worktrees/{TASK_ID_LOWER} -b {TASK_ID_LOWER} HEAD
TASK_METADATA=$(jq -c --arg id "{TASK_ID}" '[.phases[].tasks[] | select(.id == $id)][0] | del(.status)' "$PLAN_JSON")
```

Then dispatch **all ready implementers in a single message** with multiple Agent tool calls — one per task. Splitting them across turns breaks parallelism and forces cache reloads for each agent.

```text
Agent(name: "impl-{TASK_ID_LOWER}", subagent_type: "claude-caliper:task-implementer", mode: "acceptEdits", model: "{TASK_IMPLEMENTER_MODEL}", prompt: "...")
Agent(name: "impl-{TASK_ID_LOWER}", subagent_type: "claude-caliper:task-implementer", mode: "acceptEdits", model: "{TASK_IMPLEMENTER_MODEL}", prompt: "...")
... (one per ready task)
```

The agent runs in background automatically (defined in agent frontmatter). Track each agent's name mapped to its task ID and worktree path.

**Note:** `--check-base` runs at orchestrate startup and before each phase dispatch (multi-phase). No separate dispatch-level base check is needed.

## Process Completions

When a background agent completes (push notification — do not poll):

1. Read the agent's return message for completion notes and task summary
2. Dispatch a reviewer (synchronous — override background with `run_in_background: false` so the lead waits for results):

```text
Agent(
  name: "review-{TASK_ID_LOWER}",
  subagent_type: "claude-caliper:task-reviewer",
  model: "{TASK_REVIEWER_MODEL}",
  mode: "acceptEdits",
  run_in_background: false,
  prompt: "<substitute task-reviewer-prompt.md with all {VARIABLES}>"
)
```

3. Extract the last `json review-summary` block from reviewer output
4. Triage issues: "fix" or "dismiss" (with reasoning)

## Review Fix Cycle

If fixes needed, dispatch a new `claude-caliper:task-implementer` agent (with `mode: "acceptEdits"`) into the same worktree to apply fixes — the lead coordinates, implementers touch code.

1. Read the reviewer's findings
2. Dispatch a fix agent with the reviewer's findings and the task context, targeting the existing worktree path
3. When the fix agent completes, re-dispatch reviewer with updated HEAD_SHA
4. Repeat until review passes (max 3 cycles, then escalate to user)

## After Review Passes (or Skip)

For trivial tasks (one-liner, config change, rename) where a full reviewer dispatch is overhead, you may skip the review and record a skip with justification instead. The consistency check accepts both `pass` and `skip` verdicts.

1. Record the task-review in `reviews.json` (in the plan directory alongside plan.json):
   ```bash
   jq '. += [{"type":"task-review","scope":"{TASK_ID}","verdict":"pass","remaining":0}]' "$PLAN_DIR/reviews.json" > "$PLAN_DIR/reviews.json.tmp" && mv "$PLAN_DIR/reviews.json.tmp" "$PLAN_DIR/reviews.json"
   ```
   To skip review: use `"verdict":"skip","reason":"<justification>"` instead of `"verdict":"pass"`.
   If `reviews.json` doesn't exist yet, create it: `echo '[]' > "$PLAN_DIR/reviews.json"` first.
2. Mark task complete: `validate-plan --update-status plan.json --task {TASK_ID} --status complete`
3. Validate criteria: `validate-plan --criteria plan.json --task {TASK_ID}`
4. Merge and clean up the agent's worktree:
   - Never `cd` into an agent worktree — always use `git -C <agent-worktree-path>` for inspection commands (`git log`, `git status`, `git diff`). This prevents CWD from pointing at a path that gets deleted during cleanup.
   - Merge: `git -C <your worktree path> merge <agent-branch>`
   - Clean up: `git worktree remove <agent-worktree-path>` then `git branch -d <agent-branch>`
   - Reset CWD after removal: `cd <feature-worktree-path> && pwd` — run this after every worktree removal even if you believe CWD hasn't drifted
5. Check if dependent tasks are now unblocked (`validate-plan --check-deps`)
6. Dispatch newly unblocked tasks (same pattern as above)

## Key Differences from Agent Teams

- No mailbox idle notifications (agent-teams concept) — use background agent completion events instead
- No mailbox messaging — lead dispatches fix agents into the existing worktree
- Worktrees are created by the orchestrator via `git worktree add` from the feature branch
- Fix agents are dispatched into existing worktrees — the lead coordinates, implementers touch code
