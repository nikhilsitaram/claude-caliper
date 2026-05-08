# Dispatch Protocol: Subagents Mode

Parallel task execution via Agent tool dispatches with worktree isolation. No experimental env var needed.

## Dispatch Implementers

For each task in the phase, check deps: `validate-plan --check-deps "$PLAN_JSON" --task {TASK_ID}`. Collect all tasks that pass. For each ready task, create a worktree nested under the parent (feature or phase) worktree and extract metadata (strip `status` — orchestrator state not needed by implementer):

```bash
PARENT_WORKTREE="$(git rev-parse --show-toplevel)"
MAIN_ROOT="$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
[[ "$PARENT_WORKTREE" == "$MAIN_ROOT" ]] && { echo "ERROR: orchestrator CWD is the main repo; dispatching from here creates sibling task worktrees that trigger silent permission denials in background subagents. cd into the feature or phase worktree before dispatching." >&2; exit 1; }
PRE_TASK_SHA=$(git -C "$PARENT_WORKTREE" rev-parse HEAD)
git -C "$PARENT_WORKTREE" worktree add .claude/worktrees/{TASK_ID_LOWER} -b {TASK_ID_LOWER} HEAD
TASK_WORKTREE="$PARENT_WORKTREE/.claude/worktrees/{TASK_ID_LOWER}"
TASK_METADATA=$(jq -c --arg id "{TASK_ID}" '[.phases[].tasks[] | select(.id == $id)][0] | del(.status)' "$PLAN_JSON")
TASK_COMPLEXITY=$(echo "$TASK_METADATA" | jq -r '.complexity')
REVIEWER_NEEDED=$(echo "$TASK_METADATA" | jq -r '.reviewer_needed')
case "$TASK_COMPLEXITY" in
  low)    COMPLEXITY_GUIDANCE="Be efficient -- minimal implementation, avoid over-engineering." ;;
  medium) COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
  high)   COMPLEXITY_GUIDANCE="Think carefully -- consider edge cases, failure modes, and long-term maintainability." ;;
  *)      COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
esac
```

`TASK_COMPLEXITY` and `COMPLEXITY_GUIDANCE` are substituted into `{TASK_COMPLEXITY}` and `{COMPLEXITY_GUIDANCE}` in the implementer and reviewer prompts. `REVIEWER_NEEDED` gates reviewer dispatch in "Process Completions".

Then dispatch **all ready implementers in a single message** with multiple Agent tool calls — one per task. Splitting them across turns breaks parallelism and forces cache reloads for each agent.

```text
Agent(name: "impl-{TASK_ID_LOWER}", subagent_type: "claude-caliper:task-implementer", model: "{TASK_IMPLEMENTER_MODEL}", mode: "acceptEdits", prompt: "<substitute implementer-prompt.md, filling {TASK_COMPLEXITY}, {COMPLEXITY_GUIDANCE}, and all other {VARIABLES}>")
Agent(name: "impl-{TASK_ID_LOWER}", subagent_type: "claude-caliper:task-implementer", model: "{TASK_IMPLEMENTER_MODEL}", mode: "acceptEdits", prompt: "<substitute implementer-prompt.md, filling {TASK_COMPLEXITY}, {COMPLEXITY_GUIDANCE}, and all other {VARIABLES}>")
... (one per ready task)
```

The agent runs in background automatically (defined in agent frontmatter). Track each agent's name mapped to its task ID and worktree path.

**Note:** `--check-base` runs at orchestrate startup and before each phase dispatch (multi-phase). No separate dispatch-level base check is needed.

## Process Completions

When a background agent completes (push notification — do not poll):

1. Read the agent's return message for completion notes and task summary
2. Verify the commit landed on the task branch — not the parent worktree's branch. The real check is whether the parent HEAD is still at `PRE_TASK_SHA`:
    ```bash
    git -C "$TASK_WORKTREE" log --oneline -3 --decorate
    git -C "$PARENT_WORKTREE" rev-parse HEAD
    ```
    Parent HEAD must still equal `$PRE_TASK_SHA`. If it has advanced, the implementer committed to the parent branch instead. Correct via a 3-stage recovery — capture, verify, rewind. **Each stage's exit code matters: stop and surface to the user if any stage fails.**

    **Stage 1 — capture the rogue commit on the task branch.** FF-only fails loudly if `WRONG_HEAD` isn't a descendant of the task branch's tip (a more confused state than a single misplaced commit):

    ```bash
    WRONG_HEAD=$(git -C "$PARENT_WORKTREE" rev-parse HEAD)
    PARENT_BRANCH=$(git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD)
    git -C "$TASK_WORKTREE" merge --ff-only "$WRONG_HEAD"
    ```

    If the `merge --ff-only` failed, **stop and surface to the user with `$WRONG_HEAD`, `$TASK_WORKTREE`, and `$PARENT_WORKTREE`** — do NOT proceed to Stage 2.

    **Stage 2 — verify preconditions for the rewind.** Both checks must return exit code 0:

    ```bash
    [ "$(git -C "$TASK_WORKTREE" rev-parse HEAD)" = "$WRONG_HEAD" ]
    [ "$(git -C "$PARENT_WORKTREE" worktree list --porcelain | grep -c "branch refs/heads/$PARENT_BRANCH$")" -eq 1 ]
    ```

    The first confirms task HEAD is exactly `$WRONG_HEAD` — i.e., Stage 1's FF-merge landed where expected and nothing has interleaved another commit. The second confirms `$PARENT_BRANCH` is checked out only in `$PARENT_WORKTREE` — Stage 3's final `switch` would fail if any other worktree has it checked out.

    If either check failed, **stop and surface to the user** — do NOT proceed to Stage 3.

    **Stage 3 — rewind parent via switch + atomic update-ref + switch.** No force flag (unlike `reset --hard`); the `<old-value>` arg to `update-ref` is an atomic compare-and-swap that fails loudly on TOCTOU:

    ```bash
    git -C "$PARENT_WORKTREE" switch --detach "$PRE_TASK_SHA"
    git -C "$PARENT_WORKTREE" update-ref "refs/heads/$PARENT_BRANCH" "$PRE_TASK_SHA" "$WRONG_HEAD"
    git -C "$PARENT_WORKTREE" switch "$PARENT_BRANCH"
    ```
3. Check `REVIEWER_NEEDED`:
   - If `"false"`: record a skip in reviews.json (`"verdict":"skip","reason":"reviewer_needed: false"`) and proceed directly to step 2 of "After Review Passes" (skip step 1 — verdict already recorded). Skip steps 4-5.
   - If `"true"`: dispatch a reviewer (synchronous — override background with `run_in_background: false` so the lead waits for results):

```text
Agent(
  name: "review-{TASK_ID_LOWER}",
  subagent_type: "claude-caliper:task-reviewer",
  model: "{TASK_REVIEWER_MODEL}",
  mode: "acceptEdits",
  run_in_background: false,
  prompt: "<substitute task-reviewer-prompt.md, filling {TASK_COMPLEXITY}, {COMPLEXITY_GUIDANCE}, and all other {VARIABLES}>"
)
```

4. Extract the last `json review-summary` block from reviewer output
5. Triage issues: "fix" or "dismiss" (with reasoning)

## Review Fix Cycle

If fixes needed, dispatch a new `claude-caliper:task-implementer` agent (with `mode: "acceptEdits"`) into the same worktree to apply fixes — the lead coordinates, implementers touch code.

1. Read the reviewer's findings
2. Dispatch a fix agent with the reviewer's findings and the task context, targeting the existing worktree path
3. When the fix agent completes, re-dispatch reviewer with updated HEAD_SHA
4. Repeat until review passes (max 3 cycles, then escalate to user)

## After Review Passes (or Skip)

When `REVIEWER_NEEDED` was `"false"`, skip step 1 — the skip verdict was already recorded in step 2 of Process Completions. Start at step 2.

1. Record the task-review in `reviews.json` (in the plan directory alongside plan.json):
   ```bash
   jq '. += [{"type":"task-review","scope":"{TASK_ID}","verdict":"pass","remaining":0}]' "$PLAN_DIR/reviews.json" > "$PLAN_DIR/reviews.json.tmp" && mv "$PLAN_DIR/reviews.json.tmp" "$PLAN_DIR/reviews.json"
   ```
   If `reviews.json` doesn't exist yet, create it: `echo '[]' > "$PLAN_DIR/reviews.json"` first.
2. Mark task complete: `validate-plan --update-status plan.json --task {TASK_ID} --status complete`
3. Validate criteria: `validate-plan --criteria plan.json --task {TASK_ID}`
4. Merge and clean up the agent's worktree:
   - Never `cd` into an agent worktree — always use `git -C <agent-worktree-path>` for inspection commands (`git log`, `git status`, `git diff`). This prevents CWD from pointing at a path that gets deleted during cleanup.
   - Guard before merge: `PARENT_BRANCH=$(git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD)` — then `[[ "$PARENT_BRANCH" == integrate/* ]] && { echo "ERROR: PARENT_WORKTREE is on the integration branch. Task branches must merge into the phase branch; integration happens only in Phase Wrap-Up step 7." >&2; exit 1; }`. This catches state drift from the wrong-worktree recovery path where the phase branch was reset to integration HEAD.
   - Merge: `git -C "$PARENT_WORKTREE" merge {TASK_ID_LOWER}` (task branch into the phase branch, never directly into integration)
   - Clean up: `git worktree remove <agent-worktree-path>` then `git branch -d <agent-branch>`
   - Reset CWD after removal: `cd <feature-worktree-path> && pwd` — run this after every worktree removal even if you believe CWD hasn't drifted
5. Check if dependent tasks are now unblocked (`validate-plan --check-deps`)
6. Dispatch newly unblocked tasks (same pattern as above)

## Key Differences from Agent Teams

- No mailbox idle notifications (agent-teams concept) — use background agent completion events instead
- No mailbox messaging — lead dispatches fix agents into the existing worktree
- Worktrees are created by the orchestrator via `git worktree add` from the feature branch
- Fix agents are dispatched into existing worktrees — the lead coordinates, implementers touch code
- Task worktrees must nest **inside** the parent (feature or phase) worktree — anchor `git worktree add` with `git -C "$PARENT_WORKTREE"` so CWD drift never produces siblings under the main repo. Background subagents writing into a sibling worktree get silent permission denials because Claude Code scopes write permission to the parent session's project root, and they cannot answer the cross-directory prompt.
