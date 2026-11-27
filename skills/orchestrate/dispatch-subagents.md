# Dispatch Protocol

## Dispatch Implementers

`validate-plan --ready "$PLAN_JSON" --phase {LETTER}` prints one dispatchable task ID per line: `pending`, every dependency `complete`/`skipped`, no open `gated_on` (`in_progress` tasks are never re-listed). Tasks held only by a gate go to stderr as `GATED: <id> — <input>`. For each ready task, one call per task, with `<PARENT_WORKTREE>` written in as a literal absolute path: the feature worktree (`$MAIN_ROOT/.claude/worktrees/<feature>`, single-phase) or the task's own phase worktree (`PHASE_WORKTREE` from Prepare Phase step 1):

```bash
caliper-phase-dispatch "$PLAN_JSON" <PARENT_WORKTREE> {TASK_ID}
```

It adds the task worktree at `<PARENT_WORKTREE>/.claude/worktrees/{TASK_ID_LOWER}` on branch `{TASK_ID_LOWER}`, seeds agent memory into it, claims the task `in_progress` (so the next `--ready` can't re-list it), and prints the worktree path. Task worktrees nest inside the parent because background subagents writing into a sibling under the main repo get silent permission denials they can't answer. It refuses the main checkout, a parent on another phase's branch, a task that isn't `pending`, and a surviving task branch or directory (settle those per Resuming In-Flight Tasks). A refusal creates nothing. A failure before the claim lands rolls back what it created and leaves the task `pending`; if it reports `rollback incomplete`, settle the leftover per Resuming In-Flight Tasks. If validate-plan writes the claim and then exits non-zero (`validate-plan failed after claiming …`), nothing is undone: the task is `in_progress` with its worktree kept, which Resuming In-Flight Tasks settles as `in_progress` with a branch.

Then extract the task's metadata, without the lead-only `status`:

```bash
TASK_METADATA=$(jq -c --arg id "{TASK_ID}" '[.phases[].tasks[] | select(.id == $id)][0] | del(.status)' "$PLAN_JSON")
TASK_COMPLEXITY=$(echo "$TASK_METADATA" | jq -r '.complexity')
case "$TASK_COMPLEXITY" in
  low)    COMPLEXITY_GUIDANCE="Be efficient -- minimal implementation, avoid over-engineering." ;;
  medium) COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
  high)   COMPLEXITY_GUIDANCE="Think carefully -- consider edge cases, failure modes, and long-term maintainability." ;;
  *)      COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
esac
```

Dispatch **all ready implementers in a single message**, one Agent call per task: splitting them across turns breaks parallelism and reloads the cache for each agent.

```text
Agent(name: "impl-{TASK_ID_LOWER}", subagent_type: "caliper:task-implementer", model: "{TASK_IMPLEMENTER_MODEL}", mode: "acceptEdits", prompt: "<implementer-prompt.md with every {VARIABLE} filled>")
... (one per ready task)
```

The agent runs in the background (set in its frontmatter). Track each agent's name against its task ID and worktree path.

## Process Completions

When a background agent completes (you're notified; don't poll):

Shell variables don't persist between Bash calls, and with parallel tasks a leftover `$TASK_WORKTREE` names whichever task was dispatched last, so checks would run against the wrong worktree. Start each command below, and each in After Completion that uses them, by re-deriving both paths from the completing task's ID. `<PARENT_WORKTREE>` is the literal from Dispatch Implementers: the isolation guard accepts a variable assigned a literal, but refuses one assigned `$(git …)` and then passed to git.

```bash
PARENT_WORKTREE=<PARENT_WORKTREE>
TASK_WORKTREE="$PARENT_WORKTREE/.claude/worktrees/{TASK_ID_LOWER}"
```

1. Read the agent's return message for completion notes and task summary.
2. Verify the commit landed on the task branch, not the parent's. Everything comes from git, so no dispatch-time state is needed and sibling merges can't pass for a misplaced commit:
    ```bash
    git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD
    git -C "$PARENT_WORKTREE" merge-base {TASK_ID_LOWER} HEAD
    ```
    Line 1 is `<PARENT_BRANCH>`, line 2 `<PRE_TASK_SHA>`; carry both into later calls as literals (`<PRE_TASK_SHA>` can't be re-derived once recovery moves the task branch). List how the parent moved since the fork (reflog, newest first) and count the task-branch commits the parent lacks:
    ```bash
    git -C "$PARENT_WORKTREE" log -g --format='%H %gs' refs/heads/<PARENT_BRANCH> | awk -v pre=<PRE_TASK_SHA> '$1 == pre {exit} {print}'
    git -C "$PARENT_WORKTREE" rev-list --count HEAD..{TASK_ID_LOWER}
    ```
    Reflog subjects starting `merge ` or `commit (merge):` are your own task merges (the latter from a hand-resolved conflict). Any other line, typically `commit: …`, is a commit made directly on the parent: a misplaced commit.
    - No misplaced commit, count ≥ 1 → the work is on the task branch; go to step 3.
    - No misplaced commit, count 0 → the implementer committed nothing; send the task back to it.
    - Misplaced commit, count 0, no task merges listed → recover it. **See:** `./misplaced-commit-recovery.md`
    - Misplaced commit otherwise → stop and surface it to the user. With task merges listed, the recovery's rewind to `<PRE_TASK_SHA>` would strip them off the parent; with count ≥ 1, the work is split across both branches and can't be fast-forwarded.
3. Go to After Completion; the phase implementation-review is the review gate.

## After Completion

Never `cd` into a task worktree, even to inspect it or run criteria: step 3 removes it, and once the session's CWD is deleted every later tool call is refused (Bash, Edit, even `EnterWorktree`) until the user restarts the session. Use `git -C "$TASK_WORKTREE"` to inspect and `--cwd` for criteria.

1. `validate-plan --criteria "$PLAN_JSON" --task {TASK_ID} --cwd "$TASK_WORKTREE"`: criteria `run` commands are repo-relative and the task branch isn't merged yet, so they run in the task worktree. A failed criterion means the task isn't done; send it back to the implementer.
2. `validate-plan --update-status "$PLAN_JSON" --task {TASK_ID} --status done` (stored as `complete`; spelled `done` because worktree-isolated sessions refuse any command containing a bare `complete` word, read as the shell builtin).
3. Merge and clean up:
   - Guard: `git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD` must print `phase-{letter_lower}`, the task's own phase, in a multi-phase plan. On `integrate/*`, stop: task branches merge into the phase branch, and only Phase Wrap-Up step 7 touches integration (this catches drift from the misplaced-commit recovery). On another phase's branch, the CWD belongs to a sibling phase (**See:** `./parallel-phases.md`): `cd` into this task's phase worktree, re-derive the paths, and retry.
   - Merge: `git -C "$PARENT_WORKTREE" merge {TASK_ID_LOWER}`
   - Clean up: `clear-worktree-scratch "$TASK_WORKTREE"` (syncs the implementer's `memory: project` writes to `$MAIN_ROOT`, backing up the `SubagentStop` hook, then deletes the seeded memory, which blocks the remove in repos that don't ignore `.claude/`), then `git worktree remove "$TASK_WORKTREE"`, then `git branch -d {TASK_ID_LOWER}`. If the clear fails, stop and surface the path: its memory may be unsynced, and where `.claude/` is ignored the remove would still delete it.
   - After every removal, even if you think the CWD hasn't drifted: `cd "$PARENT_WORKTREE" && pwd`. Return to the phase worktree, not the integration worktree, because the next `git branch -d` checks merges against the CWD's branch.
4. Re-run `validate-plan --ready "$PLAN_JSON" --phase {LETTER}` for newly unblocked tasks.
5. Dispatch them as above. If nothing is ready, no implementer is in flight, and the phase still has `pending` tasks, they're waiting on gates; see Gated Tasks. (No `GATED:` lines on stderr means a dependency is stuck `in_progress`; surface it to the user.)

## Resuming In-Flight Tasks

A stopped run can strand task work anywhere between dispatch and cleanup: an `in_progress` task with no live implementer (`--ready` never re-lists it), a `pending` task whose worktree was created just before the claim, or a `complete` task whose branch was never merged (After Completion marks done before merging). Prepare Phase step 6 settles these before the dispatch loop starts. If the stopped session might still be running, ask the user before touching its tasks.

Work from the phase worktree (the feature worktree for a single-phase plan). Run `git rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir`. If lines 2 and 3 are equal, the CWD is the main checkout: stop and `cd` into the phase worktree. Otherwise use line 1 as the literal `<PARENT_WORKTREE>`, so a CWD left in a subdirectory (e.g. by dependency bootstrap) can't misplace a worktree. If `git rev-parse -q --verify MERGE_HEAD` succeeds, a task merge stopped mid-conflict: surface it to the user before settling anything. Then list task statuses and surviving task branches:

```bash
jq -r --arg l "{LETTER}" '.phases[] | select(.letter == $l) | .tasks[] | "\(.id) \(.status)"' "$PLAN_JSON"
git branch --list '{letter_lower}[0-9]*'
```

Settle every task that is `in_progress` or still has a branch. Where a branch survives without its worktree directory, `git worktree prune`, then re-attach it: `git worktree add <PARENT_WORKTREE>/.claude/worktrees/{TASK_ID_LOWER} {TASK_ID_LOWER}`. `$TASK_WORKTREE` is derived as in Process Completions. Run `clear-worktree-scratch` on a task worktree before any `status --porcelain` check or `git worktree remove` below: where `.claude/` isn't ignored, seeded memory reads as uncommitted changes and blocks a no-force remove (a re-dispatch re-seeds it). A failed clear stops settling that task, as in After Completion step 3. Only After Completion steps 1–3 apply here; steps 4–5 wait until every task is settled.

- **`complete` with a branch** → finished but not cleaned up. If `git merge-base --is-ancestor {TASK_ID_LOWER} HEAD` fails, it was never merged: run After Completion step 3. Otherwise run only step 3's clean-up.
- **`pending` with a branch** → the claim never landed, so no implementer ran. Remove it as in the count-0 case below.
- **`skipped` with a branch** → the user dropped the task; ask before discarding its worktree and branch.
- **`in_progress` with no branch** → nothing to recover: `validate-plan --update-status "$PLAN_JSON" --task {TASK_ID} --status pending`.
- **`in_progress` with a branch** → treat it as if its implementer just returned: Process Completions step 2, then After Completion steps 1–3. There's no implementer to send it back to and no return message vouching that it finished, so:
  - **No misplaced commit, count 0** (nothing committed) → `git worktree remove "$TASK_WORKTREE"`, `git branch -d {TASK_ID_LOWER}`, then `--status pending` so `--ready` lists it again. If the removal fails on uncommitted changes, surface the path rather than forcing it.
  - **Uncommitted changes** (`git -C <PARENT_WORKTREE>/.claude/worktrees/{TASK_ID_LOWER} status --porcelain` prints anything; check before criteria) → the implementer died mid-edit, and criteria would judge edits the merge won't carry. Ask the user as for a criteria failure.
  - **Criteria pass** → After Completion steps 2–3. But if `--criteria` printed `no criteria defined`, nothing vouches for the commits: ask the user as for a failure, adding "merge as done" as an option.
  - **Criteria fail** → ask the user: re-dispatch into the existing worktree (skip `caliper-phase-dispatch`, re-seed with `seed-agent-memory "$TASK_WORKTREE"`, and tell the implementer the branch carries partial work and which criteria failed), or discard (`git worktree remove`, adding `--force` only for uncommitted changes the user chose to drop, then `git branch -D`, `--status pending`).

## Gated Tasks

A task's `gated_on` names outside inputs (another team's PR, reviewer-supplied data, an access grant) you can't verify, so the user decides. Dispatch everything else first; ask only once the phase is otherwise stuck.

1. Ask one AskUserQuestion with `multiSelect: true`, "Which of these inputs now exist?": one option per `GATED:` task from `--ready`'s stderr, labeled with its task ID and input, plus "None yet" (2–4 options per question, up to 4 questions per call; spread larger sets across questions).
2. For each selected task → `validate-plan --clear-gate "$PLAN_JSON" --task {TASK_ID}`, then re-run `--ready` and dispatch.
3. Only "None yet" → stop: report the gated tasks with the phase worktree path, leaving the worktrees in place. Resuming, in this session or a fresh orchestrate run, re-enters this loop. (To drop a task instead, `--update-status --status skipped` is allowed while gated.)
