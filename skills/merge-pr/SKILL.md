---
name: merge-pr
description: Use when a PR is ready to merge or needs review before merging, or when triggered by "/merge-pr", "merge the PR", "address review feedback", "review feedback ready".
---

# Merge PR

Address review feedback, comment on the PR, merge with squash, and clean up.

**Prerequisite:** A PR created by `/ship`.

**Review principle:** Verify each suggestion against the codebase before implementing. Push back on incorrect suggestions with technical reasoning. No performative agreement ("Great point!", "You're right!").

## Workflow

### Step 1: Setup

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If the list returns multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master)
- `MAIN_REPO` from `git rev-parse --path-format=absolute --git-common-dir` (strip `/.git`)
- `IS_WORKTREE` — true when `--git-dir` differs from `--git-common-dir`
- `WORKTREE_PATH` — look up from `git worktree list` by matching `$BRANCH_NAME` (works regardless of CWD)

If not on the PR branch: look up `WORKTREE_PATH` first — if the branch is in a worktree, `cd` into it (gh pr checkout fails when a worktree holds the branch). Otherwise `gh pr checkout $PR_NUMBER`.

### Step 2: PR Review

Skip if `--skip-review` was passed.

Read `reviewer-prompt.md` (same directory as SKILL.md) and dispatch a fresh-eyes reviewer subagent with:
- `{DIFF_RANGE}` = `$DEFAULT_BRANCH..HEAD`
- `{REPO_PATH}` = repository root path
- `{PR_NUMBER}` = PR number from Step 1

The subagent posts its findings as a `gh pr comment` on the PR (visible audit trail), then returns findings for use in Step 3.

### Step 3: Collect & Assess All Feedback

Fetch PR conversation comments, inline review comments, and review status via `gh`.

Merge subagent findings (Step 2) with external comments into one table. If Step 2 was skipped, process external comments only. Each finding is evaluated on merit regardless of source.

Categorize each item:

| Category | Action |
|----------|--------|
| **Actionable fix** — bug, security, correctness | Fix it |
| **Suggestion** — style, refactor, nice-to-have | Evaluate: fix if it improves correctness/readability, dismiss with reason if not |
| **Informational** — explanation, praise | Acknowledge, no change |
| **False positive** — incorrect analysis | Dismiss with technical reasoning |

### Step 4: Present & Confirm

Show the user a summary table of all findings with source, category, and planned action (fix / dismiss / no action). Ask the user to confirm before proceeding to fixes.

### Step 5: Fix, Test, Push

If `--skip-fixes` was passed, skip this entire step.

For each actionable item: make the fix. Run project tests — do not merge with failing tests. Commit and push.

### Step 6: Comment on PR

Post a `gh pr comment` with the unified assessment covering all sources (subagent review + external reviewers). Include: what was fixed, what was dismissed (with reasons), and what needed no action. Omit empty sections.

### Step 7: Confirm Merge

Ask the user for final confirmation before merging. Show: PR URL, number of fixes applied, any dismissed items.

### Step 8: Merge

If branch protection requires human approval and the PR lacks it, tell the user and stop with the PR URL.

**CWD safety:** Always `cd "$MAIN_REPO"` before merging. In worktrees, the merge triggers remote branch deletion which bricks the shell if CWD is inside the worktree. Running from the main repo is safe in all cases.

```bash
cd "$MAIN_REPO"
gh pr merge $PR_NUMBER --squash  # adjust flag if repo uses merge or rebase
```

Never use `--delete-branch` — branch cleanup is handled in Step 9.

### Step 9: Clean Up

**Worktree — run each sub-step as a SEPARATE Bash tool call.** Never chain with `&&` — CWD changes don't persist if a later chained command fails, bricking the shell.

Derive `WORKTREE_PATH` if not already captured (exact branch match — grep substring would collide on similar names like `feature` vs `feature-2`):
```bash
git worktree list --porcelain | awk -v b="refs/heads/$BRANCH_NAME" '$1=="worktree"{wt=$2} $1=="branch" && $2==b{print wt; exit}'
```

1. `git worktree remove "$WORKTREE_PATH"` (retry with `--force` if untracked files)
2. `git branch -D $BRANCH_NAME`
3. `git worktree prune`
4. `git pull --rebase`
5. `git remote prune origin`

**Not in a worktree:**

```bash
git checkout $DEFAULT_BRANCH
git branch -D $BRANCH_NAME
git pull --rebase
git remote prune origin
```

### Step 10: Summary

Report: PR number/URL, review items (fixed/dismissed/informational), merge status, cleanup status.

## Arguments

| Arg | Effect |
|-----|--------|
| `<PR number>` | Target specific PR (`/merge-pr 42`) |
| *(none)* | Detect from current branch |
| `--skip-review` / `-R` | Skip subagent review (Step 2) — external feedback still processed |
| `--skip-fixes` / `-S` | Skip fixing — just comment, merge, clean up |

## Pitfalls

| Mistake | Why |
|---------|-----|
| Merging while CWD is inside worktree | Remote branch deletion bricks the shell. `cd "$MAIN_REPO"` before merge. |
| Chaining Step 9 with `&&` | CWD change doesn't persist if later command fails. Use separate Bash calls. |
| Deleting branch before removing worktree | Git refuses. Remove worktree first. |
| Using `--delete-branch` on `gh pr merge` | Fails in worktree flows. Delete branch manually after. |
| Blindly implementing review suggestions | Verify each against the codebase, push back on incorrect ones. |
| Merging without commenting | Always post what was addressed before merging. |
