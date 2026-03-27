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

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `BASE_BRANCH` from `gh pr view $PR_NUMBER --json baseRefName --jq .baseRefName` (fallback: `DEFAULT_BRANCH`)
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master) — used only as fallback for `BASE_BRANCH`
- `MAIN_REPO` from `git rev-parse --path-format=absolute --git-common-dir` (strip `/.git`)
- `IS_WORKTREE` — true when `--git-dir` differs from `--git-common-dir`
- `WORKTREE_PATH` — look up from `git worktree list` by matching `$BRANCH_NAME` (works regardless of CWD)

If not on the PR branch: look up `WORKTREE_PATH` first — if the branch is in a worktree, `cd` into it (`gh pr checkout` fails when a worktree holds the branch). Otherwise `gh pr checkout $PR_NUMBER`.

### Step 2: Mode Selection

If `--automated`/`-A` flag was passed, use automated mode (skip prompt). If both `--automated` and `--skip-fixes` are passed, fail fast — these flags are mutually exclusive.

If no mode flag was passed, check `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get review_mode`. If it returns `automated`, use automated mode (skip prompt). If `deliberate` (or any other value), proceed to the prompt below.

Otherwise, AskUserQuestion:
- **Automated** — Fix all actionable findings without interaction. External feedback processed first, then subagent findings.
- **Deliberate** — Collect all feedback, present unified triage, choose what to fix.

### Step 3: Rebase onto Base Branch

Ensure the PR branch is up-to-date with its base branch so the review covers only this PR's changes:

```bash
git fetch origin $BASE_BRANCH
if ! git merge-base --is-ancestor origin/$BASE_BRANCH HEAD; then
  git rebase origin/$BASE_BRANCH
  git push -u origin HEAD --force-with-lease
fi
```

If rebased, log: "Branch was behind `$BASE_BRANCH` — rebased and force-pushed to ensure the review covers only this PR's changes."

If rebase has conflicts, stop and ask the user to resolve.

After a force-push, existing bot review comments become outdated. Step 5 should only process comments posted *after* the rebase push timestamp, or wait for fresh bot comments if the PR was just rebased.

### Step 4: Dispatch Subagent in Background

Skip if `--skip-review` was passed. If `--skip-review` was not passed, check `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get skip_review` — if it returns `true`, skip this step.

Read `reviewer-prompt.md` (same directory as SKILL.md) and dispatch a fresh-eyes reviewer subagent with `run_in_background: true`:
- `{DIFF_RANGE}` = `origin/$BASE_BRANCH..HEAD`
- `{REPO_PATH}` = repository root path
- `{PR_NUMBER}` = PR number from Step 1

The subagent posts its findings as a `gh pr comment` on the PR, then returns findings for use in Step 6.

### Step 5: External Feedback

**`--automated` flag (from orchestrate):** Wait 90 seconds for bots to post, then poll `gh pr checks` every 30 seconds (timeout: 5 minutes). Bots need time to analyze the diff — skipping this window means merging before external feedback lands.

**User-selected automated / Deliberate — poll for bot readiness:**
1. **Warm-up:** In user-selected automated mode, wait 60 seconds for bots to register checks. Skip in deliberate mode (user triggers manually after seeing bot activity).
2. Poll `gh pr checks $PR_NUMBER` every 60 seconds.
3. Scan latest PR comments for "processing" / "in progress" indicators from bots.
4. **Ready when:** all checks complete AND no processing indicators found.
5. **CodeRabbit rate limit:** if a rate-limit warning is detected in bot comments, treat as ready — proceed with available feedback.
6. **Timeout:** `${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get review_wait_minutes` minutes max (default: 10). Proceed with available feedback.

**Collect feedback:** Fetch PR conversation comments, inline review comments, and review status via `gh`. Categorize each item:

| Category | Action |
|----------|--------|
| **Actionable fix** — bug, security, correctness | Fix it |
| **Suggestion** — style, refactor, nice-to-have | Evaluate: fix if it improves correctness/readability, dismiss with reason if not |
| **Informational** — explanation, praise | Acknowledge, no change |
| **False positive** — incorrect analysis | Dismiss with technical reasoning |

**Automated mode:** Fix all actionable items. Run tests. If `--skip-review` was passed (no wave 2 coming): `git commit` and `git push -u origin HEAD`. Otherwise: `git commit` locally (do NOT push yet — wave 2 may modify the same files).

**Deliberate mode:** Collect and report status. No fixes yet — wait for unified triage in Step 7.

### Step 6: Subagent Results

Wait for the background subagent to return (dispatched in Step 4). Skip if `--skip-review` was passed.

**Automated mode:** Assess subagent findings against the *current* working tree (post-wave-1 fixes). Dismiss findings already addressed by wave-1. Fix remaining actionable items. Run tests. `git commit` and `git push -u origin HEAD` (single push covers both waves).

**Deliberate mode:** Collect subagent findings. Merge with external feedback from Step 5 into a unified finding set. Proceed to Step 7.

### Step 7: Present & Confirm (Deliberate Only)

Show the user a summary table with source, category, planned action, and counts per category.

AskUserQuestion with options:
- **Fix all** — actionable + suggestion items (excludes dismissed/false positives)
- **Fix critical only** — actionable items (bugs, security, correctness)
- **Skip fixes, proceed** — jump to Step 9
- **Other** — user provides custom instructions (e.g. "fix items 1, 3, 5")

### Step 8: Fix, Test, Push (Deliberate Only)

If `--skip-fixes` was passed, skip this step.

For each actionable item: make the fix. Run project tests — do not proceed with failing tests. Commit and push with `git push -u origin HEAD`.

### Step 9: Comment on PR

Post a `gh pr comment` with unified assessment: what was fixed, dismissed (with reasons), and no-action. Omit empty sections.

Report: PR URL, review items (fixed/dismissed/informational).

If automated mode, invoke pr-merge after commenting. `--automated` flag and user-selected automated are the same — the flag just pre-selects the mode so the prompt is skipped.

In deliberate mode, AskUserQuestion with options:
- **Merge PR** — invoke pr-merge via Skill tool (pr-merge's worktree guard handles CWD automatically)
- **Not yet** — if inside a worktree, tell the user: "When ready to merge: `cd` to the main repo, then run `/pr-merge`." Otherwise: "Run `/pr-merge` when ready to merge."

## Arguments

| Arg | Effect |
|-----|--------|
| `<PR number>` | Target specific PR (`/pr-review 42`) |
| *(none)* | Detect from current branch |
| `--skip-review` / `-R` | Skip subagent review (Steps 4, 6) — external feedback still processed |
| `--skip-fixes` / `-S` | Skip fixing — just comment (invalid with `--automated`) |
| `--automated` / `-A` | Force fixes for all actionable items, suppress interaction (used by pr-merge workflow) |

## Pitfalls

| Mistake | Why |
|---------|-----|
| Blindly implementing review suggestions | Verify each against the codebase, push back on incorrect ones. |
| Proceeding without commenting | Always post what was addressed before finishing. |
| Pushing between wave 1 and wave 2 | Wave 1 commits locally, wave 2 pushes — avoids intermediate remote state. |

## Integration

**Preceded by:** pr-create — after CodeRabbit reviews

**Followed by:** pr-merge — when ready to merge
