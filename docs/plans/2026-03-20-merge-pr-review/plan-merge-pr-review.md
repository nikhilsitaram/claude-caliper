---
status: Not Yet Started
---

# PR-Review Step in merge-pr — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add an independent fresh-eyes review step to merge-pr so PRs get a quality gate before merging, even without external reviewers.

**Architecture:** Dispatch an Opus subagent with the full PR diff to review for correctness/logic/security issues. Merge subagent findings with external comments into a unified assessment table. Two user confirmation gates (before fixing, before merging) and a `--skip-review` flag for trivial PRs.

**Tech Stack:** Claude Code skills (SKILL.md markdown), subagent dispatch via Agent tool (Opus model), `gh` CLI for PR operations.

---

## Phase A — Implement PR Review Step
**Status:** Not Started | **Rationale:** Self-contained single phase — one new file and one modified file with no cross-skill dependencies.

### Phase A Checklist
- [ ] A1: Snapshot before-version and create reviewer-prompt.md
- [ ] A2: Update SKILL.md with new workflow steps
- [ ] A3: Run skill-eval to validate changes

### Phase A Completion Notes
<!-- Written by dispatcher after all tasks complete.
     Implementation review changes appended here by orchestrator. -->

### Phase A Tasks

#### A1: Snapshot before-version and create reviewer-prompt.md
**Files:**
- Create: `skills/merge-pr/reviewer-prompt.md`

**Verification:** `wc -w skills/merge-pr/reviewer-prompt.md` — should be under 300 words. Manual read-through confirms template has all required variables and output format.

**Done when:** (1) Before-snapshot exists at `~/.claude/skill-evals/merge-pr/snapshot-before/SKILL.md` capturing the pre-edit state. (2) `skills/merge-pr/reviewer-prompt.md` exists with a complete subagent prompt template that accepts `{DIFF_RANGE}`, `{REPO_PATH}`, and `{PR_NUMBER}` variables, specifies Opus model, focuses on correctness/security/logic/dead-code, posts findings as a `gh pr comment` on the PR, and outputs a structured findings table with `| # | Severity | File:Line | Finding |` format. Severities are: bug, security, logic, cleanup.

**Avoid:** Including feature context or plan docs in the prompt — the design doc explicitly requires "no implementation context" so the reviewer judges code on its own merits, not the author's intent. If context leaks in, the reviewer becomes a confirmation machine instead of a fresh-eyes check.

**Step 1: Snapshot SKILL.md for eval baseline (before any edits)**

This must run before any modifications in A1 or A2. Without it, A3's skill-eval has no baseline.

```bash
mkdir -p ~/.claude/skill-evals/merge-pr/snapshot-before
cp skills/merge-pr/SKILL.md ~/.claude/skill-evals/merge-pr/snapshot-before/SKILL.md
```

**Step 2: Create the reviewer prompt file**

Create `skills/merge-pr/reviewer-prompt.md` with the following content. Follow the existing pattern from `skills/implementation-review/reviewer-prompt.md` (dispatch block with yaml-like metadata, then structured prompt body).

```markdown
# PR Review Prompt Template

Dispatch a fresh-eyes Opus subagent to review the full PR diff before reading external feedback.

```text
Agent tool (general-purpose):
  model: "opus"
  mode: "bypassPermissions"
  description: "Fresh-eyes PR review"
  prompt: |
    You are reviewing a PR diff with fresh eyes. You have NO context about
    what this feature does or why — judge the code purely on its own merits.

    ## Diff

    The code is at {REPO_PATH}

    ```bash
    git diff {DIFF_RANGE}
    ```

    Read the full diff first, then read surrounding code in any file where
    you need context to evaluate a change.

    ## Focus Areas

    Hunt for issues automated linters miss:
    - **bug** — incorrect behavior, off-by-one, null/undefined access, race conditions
    - **security** — injection, auth bypass, secret exposure, unsafe defaults
    - **logic** — unreachable code, tautological conditions, wrong operator, missing edge cases
    - **cleanup** — dead code, unused imports, duplicated logic, inconsistent naming

    Ignore style/formatting — that is the linter's job.

    ## Output

    ### Findings

    | # | Severity | File:Line | Finding |
    |---|----------|-----------|---------|

    If zero issues found, output the table header with a single row:
    `| — | — | — | No issues found |`

    ### Summary

    **Issues found:** [count]
    **Highest severity:** [bug/security/logic/cleanup or "none"]
    **Recommendation:** [merge as-is / fix before merge]

    ## Post Review

    After completing your review, post your full findings (the table and summary
    above) as a comment on the PR:

    ```bash
    gh pr comment {PR_NUMBER} --body "<your findings markdown>"
    ```

    This creates a visible audit trail on the PR regardless of session state.

    ## Rules

    - Read-only review — do not modify files (except the PR comment)
    - Be specific: file:line references, not vague suggestions
    - If zero issues, say so — do not invent problems
    - Do not review test coverage or commit messages — out of scope
```
```

**Step 3: Verify word count and structure**

Run `wc -w skills/merge-pr/reviewer-prompt.md` to confirm under 300 words. Read the file to verify the template parses correctly — the outer fenced block uses triple-backtick with `text` language label, and the inner bash block uses triple-backtick with `bash`. Verify no `@filename` references that would force-load files.

---

#### A2: Update SKILL.md with new workflow steps
**Files:**
- Modify: `skills/merge-pr/SKILL.md`

**Verification:** `wc -w skills/merge-pr/SKILL.md` — must be under 1,000 words (hard cap from CLAUDE.md). Manual read-through confirms workflow steps are numbered 1-10, `--skip-review` flag is documented, and the new steps reference `reviewer-prompt.md` correctly.

**Done when:** `skills/merge-pr/SKILL.md` has 10 workflow steps matching the design doc's revised workflow table. Step 2 (PR Review) dispatches subagent per `reviewer-prompt.md` and subagent posts findings as a `gh pr comment`. Step 3 (Collect & Assess) merges subagent findings with external comments into one table. Step 4 (Present & Confirm) shows assessment and gets user approval. Step 6 (Comment on PR) posts unified assessment with actions taken (fixed/dismissed/no-action) as a `gh pr comment`. Step 7 (Confirm Merge) asks user before merging. `--skip-review` flag is in the Arguments table and documented to skip Step 2 only (external feedback still runs). Word count under 1,000.

**Avoid:** Exceeding the 1,000-word cap — the current SKILL.md is 737 words and we are adding 3 new steps plus expanding one. Every sentence must justify its token cost. Favor terse table rows and reuse existing patterns from the current file rather than verbose prose.

**Step 1: Add Step 2 (PR Review) after Setup**

Insert a new `### Step 2: PR Review` section after Step 1 (Setup). Content:

```markdown
### Step 2: PR Review

Skip if `--skip-review` was passed.

Dispatch a fresh-eyes reviewer subagent using `reviewer-prompt.md` with:
- `{DIFF_RANGE}` = `$DEFAULT_BRANCH..HEAD`
- `{REPO_PATH}` = repository root path
- `{PR_NUMBER}` = PR number from Step 1

The subagent posts its findings as a `gh pr comment` on the PR (visible audit trail), then returns findings for use in Step 3.
```

**Step 2: Expand current Step 2 into Step 3 (Collect & Assess All Feedback)**

Rename the current "Step 2: Read & Assess Feedback" to "Step 3: Collect & Assess All Feedback". Expand it to merge subagent findings (from Step 2) with external PR comments into a single unified table. Keep the existing categorization table (Actionable fix / Suggestion / Informational / False positive). Add a note that each finding is evaluated on merit regardless of source (subagent vs external reviewer). Remove the existing last line "Show the user a summary of what will be addressed vs dismissed before proceeding." — that behavior moves to the new Step 4.

The updated section should read:

```markdown
### Step 3: Collect & Assess All Feedback

Fetch PR conversation comments, inline review comments, and review status via `gh`.

Merge subagent findings (Step 2) with external comments into one table. Each finding is evaluated on merit regardless of source.

Categorize each item:

| Category | Action |
|----------|--------|
| **Actionable fix** — bug, security, correctness | Fix it |
| **Suggestion** — style, refactor, nice-to-have | Evaluate: fix if it improves correctness/readability, dismiss with reason if not |
| **Informational** — explanation, praise | Acknowledge, no change |
| **False positive** — incorrect analysis | Dismiss with technical reasoning |
```

**Step 3: Add Step 4 (Present & Confirm)**

Insert a new `### Step 4: Present & Confirm` section after Step 3:

```markdown
### Step 4: Present & Confirm

Show the user a summary table of all findings with source, category, and planned action (fix / dismiss / no action). Ask the user to confirm before proceeding to fixes.
```

**Step 4: Renumber existing Steps 3-7 to Steps 5-9**

- Current "Step 3: Fix, Test, Push" becomes "Step 5: Fix, Test, Push"
- Current "Step 4: Comment on PR" becomes "Step 6: Comment on PR" — expand to post unified assessment (all sources: subagent + external), listing what was fixed, what was dismissed with reasons, and what needed no action
- Current "Step 5: Merge" becomes "Step 8: Merge" (Step 7 is the new confirm gate)
- Current "Step 6: Clean Up" becomes "Step 9: Clean Up"
- Current "Step 7: Summary" becomes "Step 10: Summary"

**Step 5: Add Step 7 (Confirm Merge)**

Insert a new `### Step 7: Confirm Merge` section between "Comment on PR" (Step 6) and "Merge" (Step 8):

```markdown
### Step 7: Confirm Merge

Ask the user for final confirmation before merging. Show: PR URL, number of fixes applied, any dismissed items.
```

**Step 6: Verify `--skip-fixes` placement**

The existing `--skip-fixes` line ("If `--skip-fixes` was passed, skip this entire step.") lives inside the Fix, Test, Push section. After renumbering, this section is Step 5. The text says "this entire step" (relative reference) so it does not need updating — just verify it stayed inside the correct section during the renumber.

**Step 7: Add `--skip-review` to Arguments table**

Add a row to the Arguments table:

```markdown
| `--skip-review` / `-R` | Skip subagent review (Step 2) — external feedback still processed |
```

**Step 8: Update Pitfalls table step references**

The Pitfalls table has "Chaining Step 6 with `&&`" — after renumbering, Clean Up is Step 9. Update the reference to "Step 9". No other pitfall rows reference step numbers.

**Step 9: Verify word count**

Run `wc -w skills/merge-pr/SKILL.md`. If over 1,000 words, trim prose in the new sections. Candidate cuts: merge the Present & Confirm step into a single sentence, compress the PR Review step dispatch instructions, remove redundant phrases from the expanded Step 3.

**Step 10: Verify step numbering consistency**

Read the full file and confirm all internal cross-references (Pitfalls "Step 9", `--skip-review` pointing to Step 2) are correct and no step numbers are duplicated or skipped.

---

#### A3: Run skill-eval to validate changes
**Files:**
- Create: `~/.claude/skill-evals/merge-pr/evals.json`
- Create: `~/.claude/skill-evals/merge-pr/iteration-1/config.json`

**Verification:** Skill-eval benchmark completes with pass rate reported. After-variant pass rate >= before-variant on all evals.

**Done when:** skill-eval runs 3 times per variant (before/after) across 2-3 eval scenarios, benchmark.md is generated, and after-variant shows equal or better pass rate than before-variant. No regressions in existing merge-pr behavior.

**Avoid:** Hardcoding PR numbers in eval prompts — use generic scenarios that test behavior patterns, not specific repos.

**Prerequisite:** A1 Step 1 already captured the before-snapshot at `~/.claude/skill-evals/merge-pr/snapshot-before/SKILL.md`. Verify it exists before proceeding.

**Step 1: Create evals.json**

Create `~/.claude/skill-evals/merge-pr/evals.json` with 3 eval scenarios:

```json
{
  "skill_name": "merge-pr",
  "evals": [
    {
      "id": 1,
      "name": "standard-pr-with-review",
      "prompt": "Merge PR #42. The PR has CodeRabbit comments and is ready for review.",
      "expectations": [
        "Dispatches a fresh-eyes subagent reviewer before reading external feedback",
        "Subagent posts its findings as a gh pr comment on the PR",
        "Merges subagent findings with external comments into unified assessment",
        "Presents assessment table to user and asks for confirmation before fixing",
        "Posts unified assessment comment on PR with actions taken (fixed/dismissed/no-action)",
        "Asks user for confirmation before merging (after fixes are pushed)",
        "Uses reviewer-prompt.md template for subagent dispatch"
      ]
    },
    {
      "id": 2,
      "name": "skip-review-flag",
      "prompt": "Merge PR #42 --skip-review. It's a docs-only change.",
      "expectations": [
        "Skips the subagent review step (Step 2)",
        "Still fetches and processes external PR comments",
        "Still presents assessment to user before fixing",
        "Still asks for confirmation before merging"
      ]
    },
    {
      "id": 3,
      "name": "no-external-feedback",
      "prompt": "Merge PR #42. No reviewers have commented yet.",
      "expectations": [
        "Dispatches fresh-eyes subagent reviewer even with no external comments",
        "Subagent posts its findings as a gh pr comment on the PR",
        "Assessment table includes subagent findings only when no external comments exist",
        "Posts unified assessment comment on PR with actions taken",
        "Presents assessment and asks user confirmation before any fixes",
        "Asks user for final confirmation before merging"
      ]
    }
  ]
}
```

**Step 2: Create config.json for iteration-1**

Create `~/.claude/skill-evals/merge-pr/iteration-1/config.json`:

```json
{
  "before": {
    "label": "v1-no-review",
    "type": "skill",
    "skill_path": "~/.claude/skill-evals/merge-pr/snapshot-before/SKILL.md"
  },
  "after": {
    "label": "v2-with-review",
    "type": "skill",
    "skill_path": "skills/merge-pr/SKILL.md"
  }
}
```

**Step 3: Resolve eval script paths**

```bash
PLUGIN_ROOT=$(python3 -c "
import json, os
p = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
print(p['plugins']['claude-caliper@claude-caliper'][0]['installPath'])
")
EVAL_ROOT=~/.claude/skill-evals
SKILL_EVAL_SCRIPT=$PLUGIN_ROOT/skills/skill-eval/scripts/run_eval.py
AGGREGATE_SCRIPT=$PLUGIN_ROOT/skills/skill-eval/scripts/aggregate_benchmark.py
```

**Step 4: Run both variants in parallel**

Spawn "after" and "before" eval runs simultaneously (3 runs each):

```bash
python3 $SKILL_EVAL_SCRIPT \
  --evals-path $EVAL_ROOT/merge-pr/evals.json \
  --output-dir $EVAL_ROOT/merge-pr/iteration-1/ \
  --variant after \
  --skill-path skills/merge-pr/SKILL.md \
  --runs 3
```

```bash
python3 $SKILL_EVAL_SCRIPT \
  --evals-path $EVAL_ROOT/merge-pr/evals.json \
  --output-dir $EVAL_ROOT/merge-pr/iteration-1/ \
  --variant before \
  --skill-path $EVAL_ROOT/merge-pr/snapshot-before/SKILL.md \
  --runs 3
```

**Step 5: Grade and aggregate**

Follow the skill-eval workflow: dispatch grader subagents per eval, then run the aggregate script to produce benchmark.json and benchmark.md.

**Step 6: Analyze results**

Verify after-variant pass rate >= before-variant on all evals. The key signal: evals 1 and 3 should show clear improvement (new review behavior present in after, absent in before). Eval 2 tests the skip-review flag which only exists in after.

If after-variant regresses on any eval, investigate which expectation failed and iterate on SKILL.md.
