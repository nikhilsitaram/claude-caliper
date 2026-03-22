---
name: merge-pr
description: Use when a reviewed PR is ready to merge, or when triggered by "/merge-pr", "merge the PR", "merge it".
---

# Merge PR

Confirm, squash merge, and clean up branches and worktrees.

**Prerequisite:** A PR that has been reviewed (via `/review-pr` or manually). Run this from the main repo, not from inside a worktree.

## Workflow

### Step 1: Setup

**Worktree guard:** Check if the session started inside a worktree:

```bash
if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then
  MAIN_REPO=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/.git$||')
  echo "STOP: You are inside a worktree. Run: cd $MAIN_REPO && /merge-pr"
fi
```

If inside a worktree, tell the user to `cd` to the main repo and re-run `/merge-pr` from there. Merging from inside a worktree bricks the shell when the remote branch is deleted. Do not proceed.

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master)
- `WORKTREE_PATH` — look up from `git worktree list` by matching `$BRANCH_NAME` (needed for cleanup even though we're in the main repo)
- `IS_INTEGRATION` — true when `$BRANCH_NAME` matches `integrate/*`; extract `FEATURE=${BRANCH_NAME#integrate/}`

### Step 2: Confirm Merge

Show: PR URL, title, files changed count, any pending review status.

If branch protection requires human approval and the PR lacks it, tell the user and stop with the PR URL.

Use AskUserQuestion with options:
- **Merge** — proceed with squash merge
- **Abort** — stop without merging

### Step 3: Merge

**Pre-merge rebase check:** Verify the PR branch is up-to-date with the base branch:

```bash
git fetch origin $DEFAULT_BRANCH
git merge-base --is-ancestor origin/$DEFAULT_BRANCH HEAD
```

If behind (non-zero exit): rebase onto default branch, resolve conflicts, run tests, push with `git push -u origin HEAD --force-with-lease`. Comment on PR with conflict resolution details. Complex conflicts → stop and ask user.

```bash
gh pr merge $PR_NUMBER --squash
```

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

## Pitfalls

| Mistake | Why |
|---------|-----|
| Running from inside a worktree | Remote branch deletion bricks the shell. The worktree guard catches this. |
| Deleting branch before removing worktree | Git refuses. Remove worktree first. |
| Using `--delete-branch` on `gh pr merge` | Fails in worktree flows. Delete branch manually after. |

## Integration

**Preceded by:** review-pr (or manual review)

**Auto-invoked by:** orchestrate — in `merge-pr` workflow mode
