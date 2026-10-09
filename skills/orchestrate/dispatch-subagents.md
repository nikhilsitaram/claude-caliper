# Dispatch Protocol

Parallel task execution via Agent tool dispatches with worktree isolation.

## Dispatch Implementers

List the dispatchable tasks: `validate-plan --ready "$PLAN_JSON" --phase {LETTER}` prints one task ID per line — `pending`, every dependency `complete`/`skipped`, no open `gated_on` (in-flight `in_progress` tasks are never re-listed). Tasks held only by a gate are reported on stderr as `GATED: <id> — <input>`. For each ready task, create a worktree nested under the parent (feature or phase) worktree and extract metadata (strip `status` — orchestrator state not needed by implementer). Use plain git calls and carry their printed values forward as literals — the worktree-isolation guard refuses git arguments built from `$(git …)` (**See:** `skills/design/worktree-isolation.md`). First:

```bash
git rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir
```

Line 1 is `PARENT_WORKTREE`. If lines 2 and 3 are equal, the CWD is the main repo — stop: dispatching from there creates sibling task worktrees that trigger silent permission denials in background subagents; `cd` into the feature or phase worktree first. Otherwise, with that literal:

```bash
git worktree add <PARENT_WORKTREE>/.claude/worktrees/{TASK_ID_LOWER} -b {TASK_ID_LOWER} HEAD
```

```bash
TASK_WORKTREE=<PARENT_WORKTREE>/.claude/worktrees/{TASK_ID_LOWER}
# Claim the task before dispatch: --ready lists only `pending` tasks, so a task
# still `pending` while its implementer starts up would be re-listed — and
# dispatched twice — after the next completion.
validate-plan --update-status "$PLAN_JSON" --task {TASK_ID} --status in_progress
seed-agent-memory "$TASK_WORKTREE"  # copy $MAIN_ROOT/.claude/agent-memory into the task worktree as a real dir so memory: project subagents read accumulated memory and write locally; step-3 cleanup + the SubagentStop hook sync writes back (symlinks are blocked under worktree isolation, issue #244)
TASK_METADATA=$(jq -c --arg id "{TASK_ID}" '[.phases[].tasks[] | select(.id == $id)][0] | del(.status)' "$PLAN_JSON")
TASK_COMPLEXITY=$(echo "$TASK_METADATA" | jq -r '.complexity')
case "$TASK_COMPLEXITY" in
  low)    COMPLEXITY_GUIDANCE="Be efficient -- minimal implementation, avoid over-engineering." ;;
  medium) COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
  high)   COMPLEXITY_GUIDANCE="Think carefully -- consider edge cases, failure modes, and long-term maintainability." ;;
  *)      COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
esac
```

`TASK_COMPLEXITY` and `COMPLEXITY_GUIDANCE` are substituted into `{TASK_COMPLEXITY}` and `{COMPLEXITY_GUIDANCE}` in the implementer prompt.

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

Shell variables don't persist between Bash calls, and with parallel tasks a leftover `$TASK_WORKTREE` names whichever task was dispatched last — checks and criteria would silently run against the wrong worktree. Re-derive both paths from the completing task's ID at the start of each command below and in After Completion that uses them (under worktree isolation, assign `PARENT_WORKTREE` its literal path — the guard refuses git arguments built from `$(…)`):

```bash
PARENT_WORKTREE=$(git rev-parse --show-toplevel)
TASK_WORKTREE="$PARENT_WORKTREE/.claude/worktrees/{TASK_ID_LOWER}"
```

1. Read the agent's return message for completion notes and task summary
2. Verify the commit landed on the task branch — not the parent worktree's branch. Find the task's fork point, list how the parent branch moved since then (its reflog, newest first), and count the task-branch commits the parent lacks. All of it comes from git, so no dispatch-time state is needed and sibling merges can't be mistaken for a misplaced commit:
    ```bash
    PARENT_BRANCH=$(git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD)
    PRE_TASK_SHA=$(git -C "$PARENT_WORKTREE" merge-base {TASK_ID_LOWER} HEAD)
    echo "PRE_TASK_SHA=$PRE_TASK_SHA PARENT_BRANCH=$PARENT_BRANCH"
    git -C "$PARENT_WORKTREE" log -g --format='%H %gs' "refs/heads/$PARENT_BRANCH" | awk -v pre="$PRE_TASK_SHA" '$1 == pre {exit} {print}'
    git -C "$PARENT_WORKTREE" rev-list --count HEAD..{TASK_ID_LOWER}
    ```
    Reflog lines whose subject starts `merge ` or `commit (merge):` are your own task merges (the latter when you resolved a conflict by hand). Any other line — typically `commit: …` — is a commit made directly on the parent: a misplaced commit.
    - No misplaced commit, count ≥ 1 → the work is on the task branch; go to step 3.
    - No misplaced commit, count 0 → the implementer committed nothing; send the task back to it.
    - Misplaced commit, count 0, no task merges listed → correct via the 3-stage recovery below — capture, verify, rewind. **Each stage's exit code matters: stop and surface to the user if any stage fails.**
    - Misplaced commit otherwise → stop and surface to the user. With task merges listed, Stage 3's rewind to `$PRE_TASK_SHA` would strip them off the parent; with count ≥ 1, the work is split across both branches and Stage 1 can't fast-forward.

    Each stage is its own Bash call and shell variables don't carry across, so substitute the printed `$PRE_TASK_SHA`, `$WRONG_HEAD`, and `$PARENT_BRANCH` values into later stages as literals — `$PRE_TASK_SHA` can't be re-derived once Stage 1 moves the task branch.

    **Stage 1 — capture the misplaced commit on the task branch.** The count of 0 above means the task tip is an ancestor of parent HEAD, so FF-only should succeed; if it fails, a branch moved after that check:

    ```bash
    WRONG_HEAD=$(git -C "$PARENT_WORKTREE" rev-parse HEAD)
    PARENT_BRANCH=$(git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD)
    echo "WRONG_HEAD=$WRONG_HEAD PARENT_BRANCH=$PARENT_BRANCH"
    git -C "$TASK_WORKTREE" merge --ff-only "$WRONG_HEAD"
    ```

    If the `merge --ff-only` failed, **stop and surface to the user with `$WRONG_HEAD`, `$TASK_WORKTREE`, and `$PARENT_WORKTREE`** — do NOT proceed to Stage 2.

    **Stage 2 — verify preconditions for the rewind.** All three must hold — the first prints `$WRONG_HEAD`, the second prints `1`, the third exits 0:

    ```bash
    git -C "$TASK_WORKTREE" rev-parse HEAD
    git -C "$PARENT_WORKTREE" worktree list --porcelain | grep -cFx "branch refs/heads/$PARENT_BRANCH"
    git -C "$PARENT_WORKTREE" diff --quiet && git -C "$PARENT_WORKTREE" diff --cached --quiet
    ```

    The first confirms task HEAD is exactly `$WRONG_HEAD` — Stage 1's FF-merge landed where expected. The second confirms `$PARENT_BRANCH` is checked out in exactly one worktree (we know it's `$PARENT_WORKTREE` from Stage 1's `PARENT_BRANCH=$(...)` derivation, so a count of 1 implies that one worktree) — Stage 3's final `switch` would fail if any other worktree had it checked out. `grep -Fx` matches the line literally (no regex meta-character interpretation in branch names like `feat/foo.bar`). The third confirms `$PARENT_WORKTREE` has no modified or staged files — Stage 3's `switch --detach` would fail if local changes blocked the working-tree update.

    If any check failed, **stop and surface to the user** — do NOT proceed to Stage 3.

    **Stage 3 — rewind parent via switch + atomic update-ref + switch.** No force flag (unlike `reset --hard`); the `<old-value>` arg to `update-ref` is an atomic compare-and-swap that fails loudly on TOCTOU:

    ```bash
    git -C "$PARENT_WORKTREE" switch --detach "$PRE_TASK_SHA"
    git -C "$PARENT_WORKTREE" update-ref "refs/heads/$PARENT_BRANCH" "$PRE_TASK_SHA" "$WRONG_HEAD"
    git -C "$PARENT_WORKTREE" switch "$PARENT_BRANCH"
    ```
3. Proceed directly to "After Completion" — there is no per-task review. The phase implementation-review (orchestrate Phase Wrap-Up) is the review gate over the integrated diff.

## After Completion

Never `cd` into a task worktree — not for inspection, not for criteria. Step 3 removes it, and once the session's own CWD is deleted every later tool call is refused (Bash, Edit, even `EnterWorktree`) until the user restarts the session — the post-removal CWD reset never gets to run. Use `git -C "$TASK_WORKTREE"` for inspection and `--cwd` for criteria.

1. Validate criteria: `validate-plan --criteria "$PLAN_JSON" --task {TASK_ID} --cwd "$TASK_WORKTREE"` — criteria `run` commands are repo-relative and the task branch isn't merged yet, so they must run against the task worktree; `--cwd` runs them there without moving your shell. A failed criterion means the task is not done; send it back to the implementer instead of advancing status
2. Mark task complete: `validate-plan --update-status "$PLAN_JSON" --task {TASK_ID} --status done` — `done` is stored as `complete`; spell it `done` because worktree-isolated sessions refuse any command containing a bare `complete` word (read as the shell builtin)
3. Merge and clean up the agent's worktree:
   - Guard before merge: `git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD` — if it prints `integrate/*`, stop: task branches must merge into the phase branch; integration happens only in Phase Wrap-Up step 7. This catches state drift from the wrong-worktree recovery path where the phase branch was reset to integration HEAD.
   - Merge: `git -C "$PARENT_WORKTREE" merge {TASK_ID_LOWER}` (task branch into the phase branch, never directly into integration)
   - Clean up: `clear-worktree-scratch "$TASK_WORKTREE"` (persists the task-implementer's `memory: project` writes to `$MAIN_ROOT` — belt-and-suspenders with the `SubagentStop` hook — then deletes the seeded memory, which in repos that don't ignore `.claude/` would block the remove), then `git worktree remove "$TASK_WORKTREE"` then `git branch -d {TASK_ID_LOWER}`. If the clear fails, stop and surface the path: its memory may be unsynced, and in repos that ignore `.claude/` the remove would still delete it
   - Reset CWD after removal: `cd "$PARENT_WORKTREE" && pwd` — run this after every worktree removal even if you believe CWD hasn't drifted. Return to the parent (phase) worktree, not the multi-phase feature/integration worktree: the next dispatch and completion derive `PARENT_WORKTREE` from CWD
4. Re-run `validate-plan --ready "$PLAN_JSON" --phase {LETTER}` for newly unblocked tasks
5. Dispatch them (same pattern as above). If nothing is ready, no implementer is in flight, and the phase still has `pending` tasks, they're waiting on gates — see Gated Tasks. (No `GATED:` lines on stderr means a dependency is stuck `in_progress`; surface it to the user.)

## Resuming In-Flight Tasks

A run that stopped mid-phase can strand task work at any point between dispatch and cleanup: an `in_progress` task with no live implementer (`--ready` never re-lists it), a `pending` task whose worktree was created just before the claim, or a `complete` task whose branch was never merged (After Completion marks done before it merges). Prepare Phase step 6 settles all of these before the dispatch loop starts. If the stopped session might still be running, ask the user before touching its tasks.

Work from the phase worktree (the feature worktree for a single-phase plan). Get its absolute path as in Dispatch Implementers — line 1 of `git rev-parse --path-format=absolute --show-toplevel` — and write it below as the literal `<PARENT_WORKTREE>`, so a CWD left in a subdirectory (e.g. by dependency bootstrap) can't misplace a worktree. If `git rev-parse -q --verify MERGE_HEAD` succeeds, a task merge stopped mid-conflict — surface it to the user before settling anything. Then list the phase's task statuses and the task branches still present:

```bash
jq -r --arg l "{LETTER}" '.phases[] | select(.letter == $l) | .tasks[] | "\(.id) \(.status)"' "$PLAN_JSON"
git branch --list '{letter_lower}[0-9]*'
```

Settle every task that is `in_progress` or still has a branch. Where a branch survives but its worktree directory doesn't, run `git worktree prune`, then re-attach it: `git worktree add <PARENT_WORKTREE>/.claude/worktrees/{TASK_ID_LOWER} {TASK_ID_LOWER}`. Steps borrowed from Process Completions and After Completion use `$TASK_WORKTREE` as derived there. Run `clear-worktree-scratch` on a task worktree before any `status --porcelain` check or `git worktree remove` below: in repos that don't ignore `.claude/`, its seeded agent memory reads as uncommitted changes and blocks a no-force remove (a re-dispatch re-seeds it). A failed clear stops settling that task, as in After Completion step 3. Only After Completion steps 1–3 apply here — re-running `--ready` and dispatching (steps 4–5) wait until every task is settled.

- **`complete` with a branch** → finished but not cleaned up. If `git merge-base --is-ancestor {TASK_ID_LOWER} HEAD` fails, it was never merged: run After Completion step 3 (merge, clean up). Otherwise run only step 3's clean-up.
- **`pending` with a branch** → the claim never landed, so no implementer ran. Remove it as in the count-0 case below.
- **`skipped` with a branch** → the user dropped the task; ask before discarding its worktree and branch.
- **`in_progress` with no branch** → nothing to recover: `validate-plan --update-status "$PLAN_JSON" --task {TASK_ID} --status pending`.
- **`in_progress` with a branch** → treat it as if its implementer had just returned: Process Completions step 2, then After Completion steps 1–3. There is no implementer to send it back to, and no return message vouching that it finished, so:
  - **No misplaced commit, count 0** (nothing committed) → `git worktree remove "$TASK_WORKTREE"`, `git branch -d {TASK_ID_LOWER}`, then `--status pending` so `--ready` lists it again. If the removal fails on uncommitted changes, surface the worktree path to the user rather than forcing it.
  - **Uncommitted changes** (`git -C <PARENT_WORKTREE>/.claude/worktrees/{TASK_ID_LOWER} status --porcelain` prints anything — check before criteria) → the implementer died mid-edit, and criteria would pass or fail on edits the merge won't carry. Ask the user as for a criteria failure.
  - **Criteria pass** → mark done, merge, clean up (After Completion steps 2–3). But if `--criteria` printed `no criteria defined`, nothing vouches for the commits — ask the user as for a failure, adding "merge as done" as an option.
  - **Criteria fail** → ask the user: re-dispatch into the existing worktree (skip `worktree add` and the status update; tell the implementer the branch carries partial work and which criteria failed), or discard (`git worktree remove`, adding `--force` only for uncommitted changes the user chose to drop, then `git branch -D`, `--status pending`).

## Gated Tasks

A task's `gated_on` names outside inputs (another team's PR, reviewer-supplied data, an access grant) that you can't verify yourself — so the user decides, not the lead. Dispatch everything else first; ask only once the phase is otherwise stuck.

1. Ask one AskUserQuestion with `multiSelect: true` — "Which of these inputs now exist?" — one option per `GATED:` task from `--ready`'s stderr, labeled with its task ID and input, plus a "None yet" option (questions take 2–4 options and a call up to 4 questions — spread larger sets across questions).
2. For each selected task → `validate-plan --clear-gate "$PLAN_JSON" --task {TASK_ID}`, then re-run `--ready` and dispatch.
3. Only "None yet" selected → stop: report the gated tasks with the phase worktree path, leaving the worktrees in place. Resuming — later in this session, or from a fresh orchestrate run — re-enters this loop: `--clear-gate` each input the user confirms exists and continue. (To drop a task instead, `--update-status --status skipped` is allowed while gated.)

## Worktree Placement

- Worktrees are created by the orchestrator via `git worktree add` from the parent (feature or phase) branch; the implementer works inside the worktree it is handed.
- Task worktrees must nest **inside** the parent (feature or phase) worktree — anchor `git worktree add` with the absolute `$PARENT_WORKTREE/.claude/worktrees/...` path so CWD drift never produces siblings under the main repo (and no `git -C` on a computed path, which the isolation guard refuses — **See:** `skills/design/worktree-isolation.md`). Background subagents writing into a sibling worktree get silent permission denials because Claude Code scopes write permission to the parent session's project root, and they cannot answer the cross-directory prompt.
