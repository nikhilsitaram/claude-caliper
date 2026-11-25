---
name: pr-create
description: Use when work is complete and ready to create a PR for review. Triggers include "/pr-create", "create a PR", "commit and push", "open a PR".
---

# Create PR

Commit, push, and create PR — ready for external review.

**Core principle:** Never commit directly to main. All changes go through feature branches and PRs.

**Workflow stops at PR creation.** After bots and reviewers post feedback, use `/pr-review` to address it, then `/pr-merge` to merge and clean up.

## Workflow

### Step 1: Identify Changes

```bash
git status && git diff --stat && git log --oneline -5
```

A clean tree alone isn't a reason to stop: a fully committed, unpushed branch (orchestrate hands one over) still needs a push and a PR. Step 2 decides.

### Step 2: Detect Branch Context

```bash
git branch --show-current
git symbolic-ref --short refs/remotes/origin/HEAD
```

Line 1 is `CURRENT_BRANCH`; line 2 is `origin/<DEFAULT_BRANCH>`. If line 2 errors (the clone has no `origin/HEAD`), run `git remote set-head origin --auto` and repeat it. Plain calls, read and carried forward, because the worktree-isolation guard refuses tests on `$(git …)` results (**See:** `skills/design/worktree-isolation.md`).

Use `<DEFAULT_BRANCH>` (never hardcode `main`) for all subsequent steps. `<BASE>` is the `--base` branch when given, else `<DEFAULT_BRANCH>`.

**Nothing to ship?** If Step 1 showed no uncommitted changes, list the commits ahead of the base (run `git fetch origin` first if `origin/<BASE>` doesn't resolve):

```bash
git log --oneline origin/<BASE>..HEAD
```

Stop only if this is empty too: no uncommitted changes and no commits ahead of the base means there's nothing to push or open a PR for.

**If on default branch:**
1. Sync with origin first (fetch → rebase). Stash only if the tree is dirty, and restore that entry by its SHA: a `pop` after an empty stash takes another session's entry from the shared stack
2. If local main has unpushed commits, **warn user and list them** before any push
3. Create feature branch: `git checkout -b <descriptive-branch-name>`

**If on feature branch:** Continue on current branch.

### Step 3: Review Documentation

Check if changes require updates to README.md, CLAUDE.md, or docs/. Make updates if needed, stage with code changes.

### Step 4: Run Tests

Auto-detect the project's test runner and run tests. If tests fail, stop and help fix. If no tests found, note and continue.

Skip with `--skip-tests` or `-T`. If neither flag was passed, check `caliper-settings get skip_tests` — if it returns `true`, skip tests.

### Step 5: Stage and Commit

Skip this step when the tree is clean (the work is already committed). Otherwise stage specific files (avoid `git add .` to prevent accidental secrets inclusion).

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

Rebase onto `<BASE>` (from Step 2):

```bash
git fetch origin
git rebase origin/<BASE>
```

Use bare `git fetch origin` (no branch arg) so `refs/remotes/origin/<BASE>` actually advances. `git fetch origin <BASE>` only updates `FETCH_HEAD`, leaving the remote-tracking ref stale — `git rebase origin/<BASE>` then rebases onto an outdated tip.

If conflicts occur, resolve them and re-run tests before continuing.

### Step 7: Push

```bash
git push -u origin HEAD
```

If branch was rebased and already has remote, use `git push -u origin HEAD --force-with-lease`. Always use `origin HEAD` explicitly — worktrees lose upstream tracking after rebase, so bare `git push` fails.

### Step 8: Create PR

If `gh pr view` already shows an open PR for this branch, the push updated it: report its URL and skip creation. Otherwise add `--base <BASE>` only when `--base` was given — written in as a literal, since a shell test in the same call as a body that mentions git gets the whole call refused under isolation:

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

When `--base` is provided (e.g., from orchestrate for phase PRs), the PR targets that branch instead of `<DEFAULT_BRANCH>`. This enables the integration branch model where phase PRs target `integrate/<feature>`.

### Step 9: Summary

Report: branch name, test results, files changed, commit hash, PR URL.

## Arguments

| Arg | Effect |
|-----|--------|
| (none) | Full workflow |
| `--docs` `-d` | Review docs only |
| `--quick` `-q` | Skip doc review |
| `--no-push` | Commit only |
| `--skip-tests` `-T` | Skip tests |
| `-m "..."` | Use provided message |
| `--base <branch>` | Target specific base branch for PR (default: `<DEFAULT_BRANCH>`) |

## Common Mistakes

| Mistake | Why It Matters |
|---------|----------------|
| Hardcoding `main` instead of `<DEFAULT_BRANCH>` | Some repos use `master` |
| Pushing unknown commits on local main | May push unintended WIP/experimental work |
| Using `--force` instead of `--force-with-lease` | Can overwrite others' work |
| Merging in /pr-create | Always stop at PR creation for external review |

## Integration

**Auto-invoked by:** orchestrate — after implementation-review passes

**Followed by:** pr-review — after bots and reviewers post feedback
