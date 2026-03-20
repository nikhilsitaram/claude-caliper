# Design: PR-Review Step in merge-pr

## Goal

Add an independent fresh-eyes review step to the merge-pr skill so PRs get a quality gate before merging, even without external reviewers.

## Problem

merge-pr currently only reacts to external feedback (CodeRabbit, human reviewers). For single-task work or repos without CodeRabbit, PRs merge with zero review. Even with CodeRabbit, automated linters miss logic/correctness issues.

## Architecture

Dispatch a fresh-eyes Opus subagent to review the full PR diff before reading external feedback. Combine subagent findings with external comments into a unified assessment. Add two user confirmation gates: one before fixing, one before merging.

## Non-Goals

- Replacing CodeRabbit or human review — this supplements, not replaces
- Reviewing style/formatting — CodeRabbit's job
- Reviewing test coverage — tests were already run before ship
- Reviewing commit message quality — already committed

## Key Decisions

### Subagent gets no implementation context

The reviewer receives only the diff and repo path. No plan docs, no feature description, no task list. This ensures true fresh-eyes review — it judges the code on its own merits, not the author's intent.

### PR comments as the audit trail

The subagent posts its findings directly as a `gh pr comment` on the PR — this creates a visible audit trail of what was reviewed, even if the merge-pr session is lost. After fixes are applied, the main agent posts a second comment summarizing the unified assessment (all sources), what was fixed, what was dismissed with reasons, and what needed no action.

### Unified assessment combines all sources

Subagent findings and external comments are merged into one table with the same categorization rules (actionable fix / suggestion / informational / false positive). No source gets priority — each finding is evaluated on merit.

### Two user confirmation gates

1. After presenting the assessment (before fixing) — lets the user redirect before work begins
2. After fixes are pushed (before merging) — final gate before the irreversible merge

### Skippable with --skip-review

The subagent review (Step 2) can be skipped with `--skip-review` for trusted/trivial PRs (docs-only, version bumps). External feedback processing still runs.

## Revised Workflow

| Step | What | Change |
|------|------|--------|
| 1. Setup | Identify PR, detect environment | Same |
| **2. PR Review** | Dispatch subagent to review full diff and comment on PR | **New** |
| **3. Collect & Assess All Feedback** | Fetch external comments + combine with subagent findings | **Expanded** |
| **4. Present & Confirm** | Show assessment table, get user approval to proceed | **New** |
| 5. Fix, Test, Push | Address actionable items | Same |
| 6. Comment on PR | Post unified assessment with actions taken | **Expanded** |
| **7. Confirm Merge** | Ask user before merging | **New** |
| 8. Merge | Squash merge from main repo | Same |
| 9. Clean Up | Worktree/branch cleanup | Same |
| 10. Summary | Report results | Same |

## Step 2 Detail: Subagent Review

**Input:**
- Full diff: `DEFAULT_BRANCH..HEAD`
- Repo path for reading surrounding code

**Output:** Structured findings table:

```
| # | Severity | File:Line | Finding |
```

Severities: bug, security, logic, cleanup.

**Model:** Opus — catching subtle issues requires strong reasoning.

**Focus areas:** Correctness, security, logic errors, dead code, inconsistencies that automated linters miss.

**PR comment:** The subagent posts its findings table as a `gh pr comment` before returning results to the main agent. This creates a visible record on the PR regardless of session state.

## Deliverables

1. `skills/merge-pr/reviewer-prompt.md` — subagent prompt template (~200 words)
2. Updated `skills/merge-pr/SKILL.md` — revised workflow with Steps 2, 4, 7 added, Step 3 expanded, new `--skip-review` flag

## Implementation Approach

Single phase — self-contained edit to one skill file plus one new supporting file. No cross-skill dependencies.
