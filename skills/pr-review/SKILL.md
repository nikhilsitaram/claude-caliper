---
name: pr-review
description: Use when a PR has review feedback to address, needs fresh-eyes review, or when triggered by "/pr-review", "address review feedback", "review feedback ready".
---

# Review PR

Dispatch fresh-eyes review, address feedback, and comment on the PR.

**Prerequisite:** A PR created by `/pr-create`.

**Review principle:** Verify each suggestion against the codebase before implementing. Push back on incorrect ones with technical reasoning — no performative agreement.

## Workflow

### Step 1: Setup

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If multiple candidates, ask the user. Store PR number, branch, URL.

Detect: `BASE_BRANCH` from `gh pr view --json baseRefName`, `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback for BASE_BRANCH), `MAIN_REPO` from `git rev-parse --path-format=absolute --git-common-dir` (strip `/.git`), `IS_WORKTREE` (git-dir differs from git-common-dir), `WORKTREE_PATH` from `git worktree list` matching branch.

If not on PR branch: use existing worktree if found (`cd` into it), otherwise `gh pr checkout`.

### Step 2: Mode Selection

If `--automated`/`-A` passed, use automated mode. `--automated` + `--skip-fixes` is invalid — fail fast.

If no flag, check `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get review_mode`. If `automated`, use it. Otherwise prompt:
- **Automated** — Fix all actionable findings without interaction.
- **Deliberate** — Collect all feedback, present unified triage, choose what to fix.

### Step 3: Rebase onto Base Branch

```bash
git fetch origin $BASE_BRANCH
if ! git merge-base --is-ancestor origin/$BASE_BRANCH HEAD; then
  git rebase origin/$BASE_BRANCH
  git push -u origin HEAD --force-with-lease
fi
```

If rebased, log it. If conflicts, stop and ask user. After force-push, only process comments posted *after* the push timestamp (or wait for fresh bot comments).

### Step 4: Dispatch Subagent in Background

Skip if `--skip-review` passed or `caliper-settings get skip_review` returns `true`.

Read reviewer model: `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get reviewer_model` — substitute into `reviewer-prompt.md`'s `model:` field.

Read `reviewer-prompt.md` and dispatch with `run_in_background: true`:
- `{DIFF_RANGE}` = `origin/$BASE_BRANCH..HEAD`
- `{REPO_PATH}` = repository root
- `{PR_NUMBER}` = PR number

Subagent posts findings as `gh pr comment`, then returns them for Step 6.

### Step 5: External Feedback

**Wait for bots:**
- `--automated` from orchestrate: wait 90s, then poll `gh pr checks` every 30s (timeout: 5 min).
- User-selected automated: wait 60s warm-up, then poll every 60s.
- Deliberate: no warm-up, poll every 60s.
- Poll until all checks complete and no "processing"/"in progress" indicators in comments.
- CodeRabbit rate-limit warning = treat as ready.
- Timeout: `caliper-settings get review_wait_minutes` (default: 10).

**Collect from all three sources:**
1. Conversation comments: `gh pr view --json comments`
2. Inline review comments: `gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments`
3. Reviews: `gh pr view --json reviews`

All three required — bots post to sources 2-3.

**Categorize:**

| Category | Action |
|----------|--------|
| **Actionable** — bug, security, correctness | Fix |
| **Suggestion** — style, refactor | Fix if improves code, dismiss with reason if not |
| **Informational** — praise, explanation | Acknowledge |
| **False positive** | Dismiss with reasoning |

**Automated:** Fix actionable items, run tests. If `--skip-review` (no wave 2): commit and push. Otherwise: commit locally only (wave 2 may touch same files).

**Deliberate:** Collect and report. No fixes yet.

### Step 6: Subagent Results

Wait for background subagent (Step 4). Skip if `--skip-review`.

**Automated:** Dismiss findings already fixed in wave 1. Fix remaining actionable items, run tests, commit and push (covers both waves).

**Deliberate:** Merge with Step 5 findings into unified set. Proceed to Step 7.

### Step 7: Present & Confirm (Deliberate Only)

Show summary table (source, category, action, counts). AskUserQuestion:
- **Fix all** — actionable + suggestions
- **Fix critical only** — bugs, security, correctness
- **Skip fixes** — jump to Step 9
- **Other** — custom instructions

### Step 8: Fix, Test, Push (Deliberate Only)

Skip if `--skip-fixes`. Fix each item, run tests (fail = stop), commit and push.

### Step 9: Comment on PR

Post `gh pr comment`: what was fixed, dismissed (with reasons), no-action. Omit empty sections.

Report PR URL and item counts. Automated mode: invoke pr-merge. Deliberate mode: offer merge or tell user to run `/pr-merge` when ready.

## Arguments

| Arg | Effect |
|-----|--------|
| `<PR number>` | Target specific PR |
| *(none)* | Detect from current branch |
| `--skip-review` / `-R` | Skip subagent review (Steps 4, 6) |
| `--skip-fixes` / `-S` | Skip fixing — just comment (invalid with `--automated`) |
| `--automated` / `-A` | Fix all actionable, no interaction |

## Pitfalls

| Mistake | Why |
|---------|-----|
| Blindly implementing suggestions | Verify against codebase, push back on incorrect ones |
| Skipping PR comment | Always post what was addressed |
| Pushing between wave 1 and 2 | Wave 1 commits locally, wave 2 pushes |

## Integration

**Preceded by:** pr-create | **Followed by:** pr-merge
