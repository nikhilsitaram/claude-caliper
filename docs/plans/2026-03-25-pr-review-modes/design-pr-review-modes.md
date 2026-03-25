# Design: pr-review Mode Selection

## Problem

The pr-review skill has two interaction patterns — interactive (default) and `--automated` (flag, used programmatically by orchestrate). Users who want automated behavior must go through orchestrate. The subagent runs synchronously before external feedback is collected, wasting time when both sources are independent. In orchestrate workflows (single-phase and multi-phase), pr-review runs immediately after pr-create, but bots need ~1 minute to register checks on a new PR — causing pr-review to see zero external feedback and proceed without it.

## Goal

Add a user-facing mode prompt ("Automated" vs "Deliberate"), restructure the workflow so the subagent always runs in the background while external feedback is collected in parallel, and add smart bot-readiness polling.

## Success Criteria

1. User is prompted to choose Automated or Deliberate mode when pr-review starts (skipped when `--automated` flag is passed).
2. In automated mode, all actionable findings from both sources are fixed without user interaction.
3. The fresh-eyes subagent runs in the background in both modes (parallelism improvement).
4. External feedback readiness is detected by polling `gh pr checks` and scanning for bot processing indicators — not a hardcoded wait.
5. CodeRabbit rate-limit warnings are detected and treated as "proceed with available feedback."
6. In user-selected automated mode (not `--automated` flag), a 60-second warm-up delay precedes the first poll to allow bots to register checks on new PRs. When `--automated` is passed by orchestrate, the caller has already polled checks — skip warm-up and polling entirely.
7. Deliberate mode skips warm-up (user triggers manually after seeing bot activity) and polls immediately.
8. The `--automated` flag continues to work for orchestrate backward compatibility.

## Architecture

### Restructured Steps

```text
Step 1: Setup (unchanged)
Step 2: Mode Selection (NEW)
Step 3: Rebase (unchanged)
Step 4: Dispatch Subagent in Background (CHANGED — always background)
Step 5: External Feedback (NEW — poll, collect, automated: fix wave 1)
Step 6: Subagent Results (NEW — wait, collect, automated: fix wave 2)
Step 7: Present & Confirm (deliberate only)
Step 8: Fix, Test, Push (deliberate only)
Step 9: Comment on PR (unchanged)
```

### Step 2: Mode Selection

If `--automated`/`-A` flag is passed, skip prompt and use automated mode. Otherwise:

AskUserQuestion:
- **Automated** — Fix all actionable findings without interaction. External feedback processed first, then subagent findings.
- **Deliberate** — Collect all feedback, present unified triage, choose what to fix. (Current behavior.)

### Step 4: Dispatch Subagent in Background

Both modes dispatch the reviewer subagent with `run_in_background: true` using the existing `reviewer-prompt.md` template. The subagent posts findings as `gh pr comment` and returns them.

### Step 5: External Feedback

**`--automated` flag (from orchestrate):**
Skip warm-up and polling — orchestrate already polled checks before invoking pr-review. Proceed directly to collecting available feedback, assess, fix all actionable, `git commit` locally.

**User-selected automated mode:**
1. Wait 60 seconds for bots to register checks on the PR.
2. Poll `gh pr checks $PR_NUMBER` every 60 seconds.
3. Scan latest PR comments for "processing" / "in progress" indicators from bots.
4. **Ready when:** all checks complete AND no processing indicators found.
5. **CodeRabbit rate limit:** if a rate-limit warning is detected in bot comments, treat as ready — proceed with whatever feedback is available.
6. **Timeout:** 10 minutes max. If reached, proceed with available feedback.
7. Collect and assess all external feedback (same categorization as current Step 4).
8. Fix all actionable items. Run tests after fixes.
9. `git commit` locally (do NOT push yet — wave 2 may modify the same files).

**Deliberate mode:**
1. No warm-up — user triggers pr-review manually after seeing bot activity.
2. Poll `gh pr checks` every 60 seconds. Same readiness signals (all checks complete, no processing indicators, rate-limit = proceed, 10 min timeout).
3. Collect external feedback and report status to user while waiting for subagent.
4. No fixes yet — wait for Step 7 unified triage.

### Step 6: Subagent Results

Wait for the background subagent to return (it was dispatched in Step 4).

**Automated mode:**
1. Assess subagent findings against the *current* working tree (post-wave-1 fixes). Some findings may already be addressed by wave-1 fixes — dismiss those.
2. Fix remaining actionable items. Run tests.
3. `git commit` and `git push -u origin HEAD` (single push covers both waves).

**Deliberate mode:**
1. Collect subagent findings.
2. Merge with external feedback from Step 5 into unified finding set.
3. Proceed to Step 7.

### Steps 7-8: Present & Confirm / Fix (Deliberate Only)

Same as current Steps 5-6. Present unified triage table, user picks fix strategy, fix/test/push.

### Step 9: Comment on PR

Same as current Step 7. Post unified assessment as `gh pr comment`. Automated mode skips merge prompt (caller handles). Deliberate mode offers merge prompt.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Two-wave vs single-pass fixing | Two-wave | User preference. Wave 1 commits locally, wave 2 pushes — no stale remote state. |
| Bot readiness detection | Poll-based (`gh pr checks` + comment scan) | More reliable than hardcoded timeout. Timeout is safety net only. |
| Warm-up delay | 60s for user-selected automated only | Bots need time to register checks. `--automated` (orchestrate) skips — caller already polled. Deliberate skips — user triggers manually after seeing bot activity. |
| Poll interval | 60 seconds | Balanced between responsiveness and API rate limits. |
| Max timeout | 10 minutes | Safety net. Most bots complete in 2-5 minutes. |
| CodeRabbit rate limit | Proceed immediately | Waiting for retry is too slow and may not resolve. |
| Commit strategy | Wave 1: commit local. Wave 2: commit + push. | Avoids intermediate push state. Subagent reviews original code; findings are reconciled against wave-1 fixes before wave 2. |

## Non-Goals

- Configuring which bots to wait for
- Changing `reviewer-prompt.md` template
- Changing orchestrate's poll-checks step (pr-review handles the overlap by skipping warm-up when `--automated`)
- Adding new CLI arguments beyond the existing set
