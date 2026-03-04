---
name: ship
description: Use when work is complete and ready to create a PR for review. Triggers include "/ship", "ship it", "commit and push", "create PR".
---

# Ship

Commit, push, and create PR — ready for CodeRabbit review.

**Core principle:** Never commit directly to main. All changes go through feature branches and PRs.

**Workflow stops at PR creation.** After CodeRabbit reviews, use `/merge-pr` to address feedback, merge, and clean up.

## Workflow

### Step 1: Identify Changes

```bash
git status && git diff --stat && git log --oneline -5
```

If no changes to commit, stop here.

### Step 2: Detect Branch Context

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git branch -r | grep -oP 'origin/\K(main|master)' | head -1)
fi
MAIN_REPO=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/.git$||')
IS_WORKTREE=false
if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then IS_WORKTREE=true; fi
```

Use `$DEFAULT_BRANCH` (never hardcode `main`) for all subsequent steps.

**If on default branch:**
1. Sync with origin first (stash → fetch → rebase → pop)
2. If local main has unpushed commits, **warn user and list them** before any push
3. Create feature branch: `git checkout -b <descriptive-branch-name>`

**If on feature branch:** Continue on current branch.

### Step 3: Review Documentation

Check if changes require updates to README.md, CLAUDE.md, or docs/. Make updates if needed, stage with code changes.

### Step 4: Run Tests

Auto-detect the project's test runner and run tests. If tests fail, stop and help fix. If no tests found, note and continue.

Skip with `--skip-tests` or `-T`.

### Step 5: Stage and Commit

Stage specific files (avoid `git add .` to prevent accidental secrets inclusion).

**Show staged diff summary before committing.** Create conventional commit with HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <subject>

<body - what and why>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 6: Rebase on Main

```bash
git fetch origin $DEFAULT_BRANCH
git rebase origin/$DEFAULT_BRANCH
```

If conflicts occur, resolve them and re-run tests before continuing.

### Step 7: Push

```bash
git push -u origin HEAD
```

If branch was rebased and already has remote, use `git push --force-with-lease`.

### Step 8: Create PR

```bash
gh pr create --title "<commit subject>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points>

## Test plan
<what was tested>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 9: Summary

Report: branch name, test results, files changed, commit hash, PR URL. Note: "PR open for CodeRabbit review. Run `/merge-pr` after review."

## Arguments

| Arg | Effect |
|-----|--------|
| (none) | Full workflow |
| `--docs` `-d` | Review docs only |
| `--quick` `-q` | Skip doc review |
| `--no-push` | Commit only |
| `--skip-tests` `-T` | Skip tests |
| `-m "..."` | Use provided message |

## Common Mistakes

| Mistake | Why It Matters |
|---------|----------------|
| Hardcoding `main` instead of `$DEFAULT_BRANCH` | Some repos use `master` |
| Using `pwd` for worktree detection | Fails in subdirectories — compare `--git-dir` vs `--git-common-dir` |
| Pushing unknown commits on local main | May push unintended WIP/experimental work |
| Using `--force` instead of `--force-with-lease` | Can overwrite others' work |
| Merging in /ship | Always stop at PR creation for CodeRabbit review |

## Integration

**Auto-invoked by:** superpowers:orchestrating — after implementation-review passes

**Followed by:** superpowers:merge-pr — after CodeRabbit reviews

**Pairs with:** superpowers:using-git-worktrees — ship detects worktree context automatically
