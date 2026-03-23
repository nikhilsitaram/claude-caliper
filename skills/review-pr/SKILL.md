---
name: review-pr
description: Use when a PR has review feedback to address, needs fresh-eyes review, or when triggered by "/review-pr", "address review feedback", "review feedback ready".
---

# Review PR

Dispatch fresh-eyes review, address feedback, and comment on the PR.

**Prerequisite:** A PR created by `/create-pr`.

**Review principle:** Verify each suggestion against the codebase before implementing. Push back on incorrect ones with technical reasoning — no performative agreement.

## Workflow

### Step 1: Setup

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If the list returns multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master)
- `MAIN_REPO` from `git rev-parse --path-format=absolute --git-common-dir` (strip `/.git`)
- `IS_WORKTREE` — true when `--git-dir` differs from `--git-common-dir`
- `WORKTREE_PATH` — look up from `git worktree list` by matching `$BRANCH_NAME` (works regardless of CWD)

If not on the PR branch: look up `WORKTREE_PATH` first — if the branch is in a worktree, `cd` into it (`gh pr checkout` fails when a worktree holds the branch). Otherwise `gh pr checkout $PR_NUMBER`.

### Step 2: PR Review

Skip if `--skip-review` was passed.

Read `reviewer-prompt.md` (same directory as SKILL.md) and dispatch a fresh-eyes reviewer subagent with:
- `{DIFF_RANGE}` = `$DEFAULT_BRANCH..HEAD`
- `{REPO_PATH}` = repository root path
- `{PR_NUMBER}` = PR number from Step 1

The subagent posts its findings as a `gh pr comment` on the PR (visible audit trail), then returns findings for use in Step 3.

### Step 3: Collect & Assess All Feedback

Fetch PR conversation comments, inline review comments, and review status via `gh`.

Merge subagent findings (Step 2) with external comments. If Step 2 was skipped, process external only. Evaluate each on merit.

Categorize each item:

| Category | Action |
|----------|--------|
| **Actionable fix** — bug, security, correctness | Fix it |
| **Suggestion** — style, refactor, nice-to-have | Evaluate: fix if it improves correctness/readability, dismiss with reason if not |
| **Informational** — explanation, praise | Acknowledge, no change |
| **False positive** — incorrect analysis | Dismiss with technical reasoning |

### Step 4: Present & Confirm

Show the user a summary table with source, category, planned action, and counts per category.

Use AskUserQuestion with options:
- **Fix all** — actionable + suggestion items (excludes dismissed/false positives)
- **Fix critical only** — actionable items (bugs, security, correctness)
- **Skip fixes, proceed** — jump to Step 6 (omit this option when `--automated` is passed — in automated workflows, all actionable findings must be fixed to maintain audit trail integrity)
- **Other** — user provides custom instructions (e.g. "fix items 1, 3, 5")

### Step 5: Fix, Test, Push

If `--skip-fixes` was passed, skip this entire step.

For each actionable item: make the fix. Run project tests — do not proceed with failing tests. Commit and push with `git push -u origin HEAD`.

### Step 6: Comment on PR

Post a `gh pr comment` with unified assessment: what was fixed, dismissed (with reasons), and no-action. Omit empty sections.

Report: PR URL, review items (fixed/dismissed/informational).

If inside a worktree, tell the user: "When ready to merge: `cd` to the main repo, then run `/merge-pr`." Otherwise: "Run `/merge-pr` when ready to merge."

## Arguments

| Arg | Effect |
|-----|--------|
| `<PR number>` | Target specific PR (`/review-pr 42`) |
| *(none)* | Detect from current branch |
| `--skip-review` / `-R` | Skip subagent review (Step 2) — external feedback still processed |
| `--skip-fixes` / `-S` | Skip fixing — just comment |
| `--automated` / `-A` | Suppress "Skip fixes, proceed" option (used by merge-pr workflow) |

## Pitfalls

| Mistake | Why |
|---------|-----|
| Blindly implementing review suggestions | Verify each against the codebase, push back on incorrect ones. |
| Proceeding without commenting | Always post what was addressed before finishing. |

## Integration

**Preceded by:** create-pr — after CodeRabbit reviews

**Followed by:** merge-pr — when ready to merge
