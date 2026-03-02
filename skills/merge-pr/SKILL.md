---
name: merge-pr
description: Use when a PR has been reviewed by CodeRabbit and is ready to merge. Triggers include "/merge-pr", "merge the PR", "address review feedback", "coderabbit reviewed". Handles fixing review issues, commenting on PR, merging, and cleaning up branch/worktree.
---

# Merge PR

Address CodeRabbit review feedback, comment on the PR with what was fixed, merge, and clean up.

**Prerequisite:** A PR created by `/ship` that has been reviewed by CodeRabbit.

**REQUIRED BACKGROUND:** Follow receiving-code-review principles when evaluating CodeRabbit feedback — verify before implementing, push back on incorrect suggestions, no performative agreement.

## Workflow

### Step 1: Identify PR

Determine the PR to merge:

**If PR number provided** (`/merge-pr 42`):
```bash
gh pr view 42 --json number,title,headRefName,url,state
```

**If no PR number** — detect from current branch:
```bash
gh pr view --json number,title,headRefName,url,state
```

**If not on a feature branch** — list recent PRs:
```bash
gh pr list --author @me --state open --limit 5
```

Store `PR_NUMBER`, `BRANCH_NAME`, and `PR_URL` for later steps.

### Step 2: Detect Environment

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git branch -r | grep -oP 'origin/\K(main|master)' | head -1)
fi
MAIN_REPO=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/.git$||')
IS_WORKTREE=false
if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then IS_WORKTREE=true; fi
```

**If not on the PR branch**, check it out:
```bash
gh pr checkout $PR_NUMBER
```

### Step 3: Read Review Comments

Fetch both conversation comments and inline review comments:

```bash
# PR conversation comments (includes CodeRabbit summary)
gh pr view $PR_NUMBER --comments --json comments

# Inline review comments (file-specific suggestions)
gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments --paginate
```

Also check the review status:
```bash
gh pr view $PR_NUMBER --json reviews --jq '.reviews[] | {author: .author.login, state: .state, body: .body}'
```

### Step 4: Assess Feedback

Categorize each CodeRabbit comment:

| Category | Action |
|----------|--------|
| **Actionable fix** — bug, security issue, correctness problem | Fix it |
| **Suggestion** — style improvement, refactor, nice-to-have | Evaluate: is it actually better? Fix if yes, dismiss with reason if no |
| **Informational** — explanation, context, praise | Acknowledge, no code change |
| **False positive** — incorrect analysis, doesn't apply | Dismiss with technical reasoning |

**Show the user a summary** of what will be addressed vs dismissed before proceeding.

**Apply receiving-code-review principles:** Verify each suggestion against the codebase. Don't blindly implement. Push back on incorrect suggestions with technical reasoning.

### Step 5: Fix Issues

For each actionable item:
1. Make the fix
2. Verify it doesn't break existing functionality

After all fixes, run tests:

| Indicator | Command |
|-----------|---------|
| `tests/` dir + Python files | `python3 -m pytest tests/ -v 2>&1 \| tail -30` |
| `package.json` with `test` script | `npm test 2>&1 \| tail -30` |
| `Cargo.toml` | `cargo test 2>&1 \| tail -30` |
| `go.mod` | `go test ./... 2>&1 \| tail -30` |
| `Makefile` with `test` target | `make test 2>&1 \| tail -30` |

If tests fail, fix before continuing. Do NOT merge with failing tests.

### Step 6: Commit and Push

Stage and commit the fixes:
```bash
git add <specific files>
git commit -m "$(cat <<'EOF'
fix: address CodeRabbit review feedback

<brief description of what was fixed>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push
```

### Step 7: Comment on PR

Leave a PR comment summarizing what was addressed:

```bash
gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## Review feedback addressed

### Fixed
- <item 1: what was wrong and what was fixed>
- <item 2: ...>

### Dismissed
- <item: reason it was dismissed (e.g., false positive, YAGNI, technically incorrect)>

### No action needed
- <informational items acknowledged>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

If nothing was dismissed, omit the Dismissed section. If everything was fixed, just list the fixes.

### Step 8: Merge PR

**Before merging**, check branch protection:
```bash
gh api repos/{owner}/{repo}/branches/$DEFAULT_BRANCH/protection 2>/dev/null | grep -q "required_pull_request_reviews"
```
If reviews are required and the PR hasn't been approved, tell the user the PR needs human approval and provide the URL. Stop here.

Merge with squash:
```bash
gh pr merge $PR_NUMBER --squash
```

Never use `--delete-branch` on `gh pr merge` — branch cleanup is handled in Step 9.

### Step 9: Clean Up

**If in a worktree (`$IS_WORKTREE` is true):**

**CRITICAL: Run each sub-step as a separate Bash tool call.** Never chain with `&&`.

**Step 9a** — Move CWD to main repo:
```bash
cd "$MAIN_REPO"
```

**Step 9b** — Remove the worktree:
```bash
git worktree remove <worktree-path>
```
If it fails due to untracked files, retry with `--force`. If path doesn't exist, skip to 9d.

**Step 9c** — Delete the branch:
```bash
git branch -D $BRANCH_NAME
```

**Step 9d** — Prune stale worktree refs:
```bash
git worktree prune
```

**Step 9e** — Sync main:
```bash
git pull --rebase
git remote prune origin
```

**If NOT in a worktree:**
```bash
git checkout $DEFAULT_BRANCH
git branch -D $BRANCH_NAME
git pull --rebase
git remote prune origin
```

### Step 10: Summary

Provide a summary:
- PR number and URL
- Review items: fixed, dismissed, informational
- Comment posted on PR
- Merge status
- Cleanup status (branch deleted, worktree removed if applicable)

## Arguments

- `<PR number>`: Specific PR to merge (e.g., `/merge-pr 42`)
- No arguments: Detect PR from current branch
- `--skip-fixes` or `-S`: Skip fixing issues — just comment, merge, and clean up

## Examples

```text
/merge-pr                  # Detect PR from current branch, full workflow
/merge-pr 42               # Merge specific PR
/merge-pr -S               # Skip fixes, just merge and clean up
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Blindly implementing all CodeRabbit suggestions | Verify each against codebase. Push back on incorrect ones. |
| Merging with failing tests | Always run tests after fixes. Never merge red. |
| Removing worktree while CWD is inside it | `cd "$MAIN_REPO"` first. Run each cleanup sub-step as separate Bash call. |
| Chaining Step 9 cleanup with `&&` | CWD change may not persist if later command fails — bricks the shell. |
| Deleting branch before removing worktree | Git refuses. Remove worktree first. |
| Using `--delete-branch` on `gh pr merge` | Fails in worktree flows. Delete branch manually after worktree removal. |
| Not commenting on PR before merging | Always leave a comment detailing what was addressed. |
| Performative agreement with CodeRabbit | Follow receiving-code-review principles. Evaluate technically. |

## Integration

**Follows:**
- **superpowers:ship** — creates the PR that this skill merges

**Pairs with:**
- **superpowers:receiving-code-review** — principles for evaluating CodeRabbit feedback
- **superpowers:using-git-worktrees** — merge-pr handles worktree cleanup automatically

## Safety

- Never use `--no-verify` to bypass pre-commit hooks
- Never use `--force` (use `--force-with-lease` only if push rejected after rebase)
- Always run tests after fixes, before merging
- Always comment on PR before merging
- In worktrees: cd out before removing, run each cleanup as separate Bash call
