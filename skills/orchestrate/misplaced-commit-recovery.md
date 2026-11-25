# Misplaced-Commit Recovery

Read this when Process Completions step 2 finds a misplaced commit, a count of 0, and no task merges listed: the implementer committed on the parent branch instead of its task branch. Three stages: capture, verify, rewind. Each is its own Bash call, so carry the printed values in as literals: `<PRE_TASK_SHA>` and `<PARENT_BRANCH>` from step 2, `<WRONG_HEAD>` from Stage 1. Start every call by re-deriving both paths, as Process Completions does: an unset `$TASK_WORKTREE` makes `git -C ""` run in the current directory, so Stage 1 would no-op on the parent, Stage 2 would pass, and Stage 3 would rewind the commit off every branch. **If any stage fails, stop and surface it to the user.**

```bash
PARENT_WORKTREE=<PARENT_WORKTREE>
TASK_WORKTREE="$PARENT_WORKTREE/.claude/worktrees/{TASK_ID_LOWER}"
```

**Stage 1: capture the misplaced commit on the task branch.** The count of 0 means the task tip is an ancestor of parent HEAD, so a fast-forward should succeed; if it fails, a branch moved after that check. Print `<WRONG_HEAD>`, then fast-forward the task branch to it:

```bash
git -C "$PARENT_WORKTREE" rev-parse HEAD
```

```bash
git -C "$TASK_WORKTREE" merge --ff-only <WRONG_HEAD>
```

If the merge failed, stop and surface `<WRONG_HEAD>`, `$TASK_WORKTREE` and `$PARENT_WORKTREE`; don't go on to Stage 2.

**Stage 2: verify the rewind's preconditions.** All four must hold: the first prints `<WRONG_HEAD>`, the second `<PARENT_BRANCH>`, the third `1`, the fourth exits 0:

```bash
git -C "$TASK_WORKTREE" rev-parse HEAD
git -C "$PARENT_WORKTREE" rev-parse --abbrev-ref HEAD
git -C "$PARENT_WORKTREE" worktree list --porcelain | grep -cFx "branch refs/heads/<PARENT_BRANCH>"
git -C "$PARENT_WORKTREE" diff --quiet && git -C "$PARENT_WORKTREE" diff --cached --quiet
```

In order: Stage 1 landed where expected; the parent is still on `<PARENT_BRANCH>` (a switch between the earlier separate calls would let Stage 3's `switch --detach` run before its compare-and-swap fails); no other worktree has `<PARENT_BRANCH>` checked out, or Stage 3's final `switch` fails (`grep -Fx` matches branch names like `feat/foo.bar` literally); and no modified or staged files would block `switch --detach`. If any check fails, stop and surface it; don't go on to Stage 3.

**Stage 3: rewind the parent with switch, atomic update-ref, switch.** No force flag (unlike `reset --hard`): `update-ref`'s `<old-value>` argument is a compare-and-swap that fails loudly if the branch moved. Run each line as its own call, so the final `switch` can't mask a failed `update-ref` with exit 0:

```bash
git -C "$PARENT_WORKTREE" switch --detach <PRE_TASK_SHA>
git -C "$PARENT_WORKTREE" update-ref refs/heads/<PARENT_BRANCH> <PRE_TASK_SHA> <WRONG_HEAD>
git -C "$PARENT_WORKTREE" switch <PARENT_BRANCH>
```

If `update-ref` failed (`<PARENT_BRANCH>` moved since Stage 2), still run the final `switch` to put the parent back on its branch, then stop and surface `<WRONG_HEAD>` and `<PARENT_BRANCH>`: the rewind didn't happen, and Stage 1 left the misplaced commit safe on the task branch.

On success, continue with Process Completions step 3.
