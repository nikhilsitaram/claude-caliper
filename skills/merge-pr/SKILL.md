---
name: merge-pr
description: Use when a reviewed PR is ready to merge, or when triggered by "/merge-pr", "merge the PR", "merge it".
---

# Merge PR

Confirm, merge (squash or rebase), and clean up branches and worktrees.

**Prerequisite:** A PR that has been reviewed (via `/review-pr` or manually).

## Workflow

### Step 1: Setup

**Worktree guard:** Check if CWD is inside a worktree:

```bash
if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then
  MAIN_REPO=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/.git$||')
  cd "$MAIN_REPO"
fi
```

If inside a worktree, `cd` to the main repo before proceeding. All git operations (merge, branch delete, worktree remove) must run from the main repo — deleting a branch while CWD is its worktree bricks the shell.

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master)
- `WORKTREE_PATH` — look up from `git worktree list` by matching `$BRANCH_NAME` (needed for cleanup even though we're in the main repo)
- `IS_INTEGRATION` — true when `$BRANCH_NAME` matches `integrate/*`; extract `FEATURE=${BRANCH_NAME#integrate/}`

### Step 2: Confirm Merge

Show: PR URL, title, files changed count, any pending review status.

If branch protection requires human approval and the PR lacks it, tell the user and stop with the PR URL.

Use AskUserQuestion with options:
- **Merge** — proceed with merge (squash or rebase per strategy)
- **Abort** — stop without merging

### Step 3: Merge

**Pre-merge rebase check:** Verify the PR branch is up-to-date with the base branch:

```bash
git fetch origin $DEFAULT_BRANCH
git merge-base --is-ancestor origin/$DEFAULT_BRANCH HEAD
```

If behind (non-zero exit): rebase onto default branch, resolve conflicts, run tests, push with `git push -u origin HEAD --force-with-lease`. Comment on PR with conflict resolution details. Complex conflicts → stop and ask user.

**Merge strategy:**
- Default: `gh pr merge $PR_NUMBER --squash`
- When caller passes `--rebase` (orchestrate does this for multi-phase final PRs): `gh pr merge $PR_NUMBER --rebase`

Multi-phase plans produce one squash commit per phase on the integration branch. Rebase preserves this per-phase history on main. Single-phase plans use squash (one phase = one commit). Phase PRs (base is `integrate/*`) always use `--squash`.

Never use `--delete-branch` — branch cleanup is handled in Step 4.

### Step 4: Clean Up

**Integration branch** (`IS_INTEGRATION=true`):
1. For each phase worktree `.claude/worktrees/$FEATURE-phase-*`: `git worktree remove <path>`
2. `git worktree remove .claude/worktrees/$FEATURE`
3. Delete phase branches: `git branch -D phase-a phase-b ...` (list from plan.json)
4. `git branch -D $BRANCH_NAME`
5. `git worktree prune && git pull --rebase && git remote prune origin`

**Standard worktree** (branch has a worktree but we're in the main repo):
1. `git worktree remove "$WORKTREE_PATH"` (retry `--force` if untracked files)
2. `git branch -D $BRANCH_NAME`
3. `git worktree prune && git pull --rebase && git remote prune origin`

**No worktree:** `git checkout $DEFAULT_BRANCH && git branch -D $BRANCH_NAME && git pull --rebase && git remote prune origin`

### Step 5: Summary

Report: PR number/URL, merge status, cleanup status.

## Arguments

| Arg | Effect |
|-----|--------|
| `<PR number>` | Target specific PR (`/merge-pr 42`) |
| *(none)* | Detect from current branch |
| `--rebase` | Use rebase merge instead of squash (for multi-phase final PRs) |

## Pitfalls

| Mistake | Why |
|---------|-----|
| Running from inside a worktree | Remote branch deletion bricks the shell. The worktree guard catches this. |
| Deleting branch before removing worktree | Git refuses. Remove worktree first. |
| Using `--delete-branch` on `gh pr merge` | Fails in worktree flows. Delete branch manually after. |

## Integration

**Preceded by:** review-pr (or manual review)

**Auto-invoked by:** orchestrate — in `merge-pr` workflow mode
