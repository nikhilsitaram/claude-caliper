---
name: pr-merge
description: Use when a reviewed PR is ready to merge, or when triggered by "/pr-merge", "merge the PR", "merge it".
---

# Merge PR

Merge (squash or rebase) and clean up branches and worktrees.

**Prerequisite:** A PR that has been reviewed (via `/pr-review` or manually).

## Workflow

### Step 1: Setup

Detect if CWD is inside a worktree:

```bash
[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]
```

If inside a worktree, note `IN_WORKTREE=true` and capture paths for cleanup:

```bash
MAIN_REPO="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
WORKTREE_PATH="$(pwd)"
```

Stay in the worktree — `gh pr merge` is a GitHub API call that works from any directory.

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master)
- `IS_INTEGRATION` — true when `$BRANCH_NAME` matches `integrate/*`; extract `FEATURE=${BRANCH_NAME#integrate/}`

### Step 2: Merge

If branch protection requires human approval and the PR lacks it, tell the user and stop with the PR URL.

**Pre-merge rebase check:** Verify the PR branch is up-to-date with the base branch:

```bash
git fetch origin $DEFAULT_BRANCH
git merge-base --is-ancestor origin/$DEFAULT_BRANCH HEAD
```

If behind (non-zero exit): rebase onto default branch, resolve conflicts, run tests, push with `git push -u origin HEAD --force-with-lease`. Comment on PR with conflict resolution details. Complex conflicts → stop and ask user.

**Merge strategy:**
- Integration branches (`IS_INTEGRATION=true`): `gh pr merge $PR_NUMBER --rebase` — auto-detected, no flag needed
- Phase PRs (base is `integrate/*`): `gh pr merge $PR_NUMBER --squash` — auto-detected, no flag needed
- Explicit `--rebase` flag overrides for any non-auto-detected branch
- Otherwise: check `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get merge_strategy` — use the returned value (`squash` or `rebase`) as the merge method

Multi-phase plans produce one squash commit per phase on the integration branch. Rebase preserves this per-phase history on main. Single-phase plans use squash (one phase = one commit). Phase PRs (base is `integrate/*`) always use `--squash`.

Never use `--delete-branch` — branch cleanup is handled in Step 3.

### Step 3: Clean Up

**Integration branch** (`IS_INTEGRATION=true`):
1. If `IN_WORKTREE`: call `ExitWorktree` with `action: "remove"` — atomic exit + delete + CWD reset
   - If ExitWorktree is a no-op (cross-session): `cd "$MAIN_REPO" && git worktree remove "$WORKTREE_PATH"`, then prefix all subsequent commands with `cd "$MAIN_REPO" &&`
2. Remove remaining phase worktrees: `git worktree remove .claude/worktrees/$FEATURE-phase-*` for each
3. Delete phase branches: `git branch -D phase-a phase-b ...` (list from plan.json)
4. `git branch -D $BRANCH_NAME`
5. `git worktree prune && git pull --rebase && git remote prune origin`

**Standard worktree** (`IN_WORKTREE=true`):
1. Call `ExitWorktree` with `action: "remove"` — atomic exit + delete + CWD reset
   - If ExitWorktree is a no-op (cross-session): `cd "$MAIN_REPO" && git worktree remove "$WORKTREE_PATH"`, then prefix all subsequent commands with `cd "$MAIN_REPO" &&`
2. `git branch -D $BRANCH_NAME`
3. `git worktree prune && git pull --rebase && git remote prune origin`

**No worktree:** `git checkout $DEFAULT_BRANCH && git branch -D $BRANCH_NAME && git pull --rebase && git remote prune origin`

### Step 4: Summary

Report: PR number/URL, merge status, cleanup status.

## Arguments

| Arg | Effect |
|-----|--------|
| `<PR number>` | Target specific PR (`/pr-merge 42`) |
| *(none)* | Detect from current branch |
| `--rebase` | Use rebase merge instead of squash (for multi-phase final PRs) |

## Pitfalls

| Mistake | Why |
|---------|-----|
| Skipping `ExitWorktree` when it's available | `cd` doesn't persist across Bash tool calls — only `ExitWorktree` resets CWD at the session level. Always try `ExitWorktree` first; the `cd "$MAIN_REPO" &&` fallback is for cross-session worktrees where ExitWorktree returns a no-op. |
| Deleting branch before removing worktree | Git refuses. Remove worktree first. |
| Using `--delete-branch` on `gh pr merge` | Fails in worktree flows. Delete branch manually after. |

## Integration

**Preceded by:** pr-review (or manual review)

**Auto-invoked by:** orchestrate — in `pr-merge` workflow mode
