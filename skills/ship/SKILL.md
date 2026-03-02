---
name: ship
description: Use when work is complete and ready to ship — all changes go through feature branches and PRs. Triggers include "/ship", "ship it", "commit and push", "create PR". Stops at PR creation so CodeRabbit can review. Use /merge-pr after review.
---

# Ship

Review docs, commit, push, and create PR — ready for CodeRabbit review.

**Core principle: never commit directly to main.** All changes go through feature branches and PRs.

**Workflow stops at PR creation.** After CodeRabbit reviews, use `/merge-pr` to address feedback, merge, and clean up.

## Workflow

### Step 1: Identify Changes

Run a single combined command to understand what changed:
```bash
git status && git diff --stat && git log --oneline -5
```

If there are no changes to commit, stop here.

### Step 2: Detect Branch Context

Determine the current branch, default branch, and environment:
```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
# Fallback: check for main or master
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git branch -r | grep -oP 'origin/\K(main|master)' | head -1)
fi
MAIN_REPO=$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/.git$||')
# Robust worktree detection: compare .git dir to common dir (works from subdirectories)
IS_WORKTREE=false
if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then IS_WORKTREE=true; fi
```

Use `$DEFAULT_BRANCH` (not a hardcoded `main`) for all subsequent steps.

**If on the default branch:**
- First, sync local main with origin to avoid carrying stale local-only commits. Stash uncommitted changes first since rebase requires a clean working tree:
  ```bash
  git stash
  git fetch origin $DEFAULT_BRANCH
  git rebase origin/$DEFAULT_BRANCH
  git stash pop
  ```
  If local main was ahead (unpushed commits), **warn the user** and list the unpushed commits before pushing. These may be intentionally unpushed (WIP, experimental). Only push after user confirmation: `git push origin $DEFAULT_BRANCH`
- Generate a branch name from the changes (e.g., `feature/add-composite-scoring`, `fix/mobile-sidebar-overlap`)
- Create and switch to the branch:
  ```bash
  git checkout -b <branch-name>
  ```

**If on a feature branch:**
- Continue on the current branch.

### Step 3: Review Documentation

Based on the changes, determine if any documentation needs updating:

**Always check:**
- `README.md` - if public API, installation, or usage changed
- `CLAUDE.md` - if project patterns, conventions, or important context changed
- Any docs in `docs/` folder related to modified code

**CLAUDE.md Guidelines:**

CLAUDE.md is loaded into context every session. Keep it minimal:

- **Only include** what Claude wouldn't know: project-specific patterns, non-obvious conventions, critical gotchas
- **Never duplicate** information from README.md, docs/, or code comments
- **Challenge each line**: Does this justify being loaded every session? Would Claude figure this out anyway?
- **Prefer pointers**: "See docs/api.md for endpoint details" instead of duplicating the content
- **Remove stale info**: Delete anything no longer relevant

Bad CLAUDE.md patterns to avoid:
- Generic best practices Claude already knows
- Information that exists in README or docs/
- Obvious things like "use conventional commits" or "write tests"
- Historical context that doesn't affect current development

**Documentation triggers:**
- New files/features → README may need feature list update
- New dependencies → README installation section
- API changes → README usage examples
- Non-obvious patterns/conventions → CLAUDE.md (only if truly needed)
- Schema changes → relevant docs in docs/
- Config changes → setup documentation

**If documentation needs updates:**
1. Make the necessary edits
2. Show the user what was updated and why
3. Stage the doc changes along with code changes

**If documentation is already current:**
- Note that docs were reviewed and are up to date

### Step 4: Run Tests

Auto-detect the test runner from the project and run the test suite:

| Indicator | Command |
|-----------|---------|
| `tests/` dir + Python files | `python3 -m pytest tests/ -v 2>&1 \| tail -30` |
| `package.json` with `test` script | `npm test 2>&1 \| tail -30` |
| `Cargo.toml` | `cargo test 2>&1 \| tail -30` |
| `go.mod` | `go test ./... 2>&1 \| tail -30` |
| `Makefile` with `test` target | `make test 2>&1 \| tail -30` |

If no test runner is detected, skip and note "no tests found".

- If tests **pass** → continue to Step 5
- If tests **fail** → stop, show the failures, and do NOT commit. Help the user fix the failures first.
- If the test runner is not installed → warn the user and continue (don't block)

Skip this step when `--skip-tests` or `-T` is passed.

### Step 5: Stage and Commit

Stage all relevant changes:
```bash
git add <specific files>
```

Prefer staging specific files over `git add .` to avoid accidentally including sensitive files.

**Before committing, show the user the staged diff summary and file list.** Confirm they're happy with what's being committed.

Analyze the staged changes and create a conventional commit message:
- Use imperative mood ("Add feature" not "Added feature")
- Keep subject line under 70 characters
- Include body with details if changes are significant

Format:
```text
<type>(<scope>): <subject>

<body - what and why>

Co-Authored-By: Claude <noreply@anthropic.com>
```

Types: feat, fix, docs, style, refactor, perf, test, chore

Create the commit using a HEREDOC for proper formatting:
```bash
git commit -m "$(cat <<'EOF'
<commit message here>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 6: Rebase on Main

Fetch the latest main and rebase your branch on top of it. This keeps the PR merge clean.

```bash
git fetch origin $DEFAULT_BRANCH
git rebase origin/$DEFAULT_BRANCH
```

- If rebase **succeeds cleanly** → continue
- If there are **conflicts** → resolve them, then re-run tests before continuing
- If rebase is a **no-op** (already up to date) → continue

### Step 7: Push

Push the branch to the remote:
```bash
git push -u origin $CURRENT_BRANCH
```

If the branch was rebased and already had a remote, use:
```bash
git push --force-with-lease
```

### Step 8: Create PR

Create a pull request using `gh`:
```bash
gh pr create --title "<commit subject line>" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points describing the changes>

## Test plan
<bulleted checklist of what was tested>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### Step 9: Summary

Provide a summary:
- Branch name used
- Test results (pass count, or skipped)
- Files changed
- Documentation updates made (if any)
- Commit hash and message
- PR number and URL
- Note: "PR is open for CodeRabbit review. Run `/merge-pr` after review."

## Arguments

- No arguments: Full workflow (branch + docs + tests + commit + push + PR)
- `--docs` or `-d`: Review documentation only, don't commit
- `--quick` or `-q`: Skip documentation review
- `--no-push`: Commit only, don't push or create PR
- `--skip-tests` or `-T`: Skip running tests
- `--message "..."` or `-m "..."`: Use provided commit message instead of generating one

## Examples

```text
/ship                           # Full workflow: branch, commit, push, PR
/ship -d                        # Review docs only, no commit
/ship -q                        # Quick: skip doc review
/ship --no-push                 # Commit only, no push/PR
/ship -T                        # Skip tests
/ship -m "fix: resolve login bug"  # Use specific message
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Running `git fetch origin main` when default branch is `master` | Always use `$DEFAULT_BRANCH`, never hardcode branch names |
| Rebasing with uncommitted changes | Stash or commit changes before rebasing — `git stash` then `git stash pop` after |
| Using `pwd` to detect worktrees from a subdirectory | Compare `git rev-parse --git-dir` vs `--git-common-dir` instead |
| Pushing unknown commits sitting on local main | Always warn user and list unpushed commits before pushing main |
| Using `git push --force` after rebase | Always use `--force-with-lease` to avoid overwriting others' work |
| Merging PR in /ship | /ship stops at PR creation. Use /merge-pr after CodeRabbit review. |

## Integration

**Auto-invoked by:**
- **superpowers:subagent-driven-development** — after implementation-review passes

**Followed by:**
- **superpowers:merge-pr** — after CodeRabbit reviews the PR

**Pairs with:**
- **superpowers:using-git-worktrees** — ship detects worktree context automatically

## Safety

- Never use `--no-verify` to bypass pre-commit hooks
- Never commit files that look like secrets (.env, credentials, keys)
- Always show the user what will be committed before committing
- Only use `--force-with-lease` (never `--force`) and only after a rebase
- Never commit directly to main — always use a feature branch
