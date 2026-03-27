---
name: pr-create
description: Use when work is complete and ready to create a PR for review. Triggers include "/pr-create", "create a PR", "commit and push", "open a PR".
---

# Create PR

Commit, push, and create PR — ready for CodeRabbit review.

**Core principle:** Never commit directly to main. All changes go through feature branches and PRs.

**Workflow stops at PR creation.** After CodeRabbit reviews, use `/pr-review` to address feedback, then `/pr-merge` to merge and clean up.

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

Skip with `--skip-tests` or `-T`. If neither flag was passed, check `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get skip_tests` — if it returns `true`, skip tests.

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

### Step 6: Rebase on Target Base

```bash
REBASE_BASE="${BASE_BRANCH:-$DEFAULT_BRANCH}"
git fetch origin "$REBASE_BASE"
git rebase "origin/$REBASE_BASE"
```

If conflicts occur, resolve them and re-run tests before continuing.

### Step 7: Push

```bash
git push -u origin HEAD
```

If branch was rebased and already has remote, use `git push -u origin HEAD --force-with-lease`. Always use `origin HEAD` explicitly — worktrees lose upstream tracking after rebase, so bare `git push` fails.

### Step 8: Create PR

```bash
BASE_FLAG=""
if [ -n "$BASE_BRANCH" ]; then BASE_FLAG="--base $BASE_BRANCH"; fi
gh pr create $BASE_FLAG --title "<commit subject>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points>

## Test plan
<what was tested>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

When `--base` is provided (e.g., from orchestrate for phase PRs), the PR targets that branch instead of `$DEFAULT_BRANCH`. This enables the integration branch model where phase PRs target `integrate/<feature>`.

### Step 9: Summary

Report: branch name, test results, files changed, commit hash, PR URL.

If running inside a worktree, tell the user:

> PR is open for review. When ready to address feedback: `/exit` this session, `cd` to the main repo, then run `/pr-review`. Starting fresh from the main repo avoids worktree CWD issues during cleanup.

## Arguments

| Arg | Effect |
|-----|--------|
| (none) | Full workflow |
| `--docs` `-d` | Review docs only |
| `--quick` `-q` | Skip doc review |
| `--no-push` | Commit only |
| `--skip-tests` `-T` | Skip tests |
| `-m "..."` | Use provided message |
| `--base <branch>` | Target specific base branch for PR (default: `$DEFAULT_BRANCH`) |

## Common Mistakes

| Mistake | Why It Matters |
|---------|----------------|
| Hardcoding `main` instead of `$DEFAULT_BRANCH` | Some repos use `master` |
| Using `pwd` for worktree detection | Fails in subdirectories — compare `--git-dir` vs `--git-common-dir` |
| Pushing unknown commits on local main | May push unintended WIP/experimental work |
| Using `--force` instead of `--force-with-lease` | Can overwrite others' work |
| Merging in /pr-create | Always stop at PR creation for CodeRabbit review |

## Integration

**Auto-invoked by:** orchestrate — after implementation-review passes

**Followed by:** pr-review — after CodeRabbit reviews
