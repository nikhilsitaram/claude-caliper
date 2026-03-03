---
name: subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-Driven Development

Execute plan by dispatching fresh subagent per task, with two-stage review after each: spec compliance review first, then code quality review.

**Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration

## When to Use

- Have an implementation plan with mostly independent tasks
- Tasks can be dispatched one at a time to fresh subagents
- Don't use for tightly coupled tasks or when no plan exists

## The Process

**Per task:** Dispatch implementer → spec compliance review → code quality review → mark complete

**After all tasks:** Write completion report → verify Task 0 integration tests pass → implementation review → ship

## Prompt Templates

- `./implementer-prompt.md` - Dispatch implementer subagent
- `./spec-reviewer-prompt.md` - Dispatch spec compliance reviewer subagent
- `./code-quality-reviewer-prompt.md` - Dispatch code quality reviewer subagent
- `skills/implementation-review/reviewer-prompt.md` - Auto-dispatched final implementation reviewer

## Example Workflow

```
You: I'm using Subagent-Driven Development to execute this plan.

[Read plan file once: docs/plans/YYYY-MM-DD-feature/plan-feature.md]
[Extract all 5 tasks with full text and context]
[Create TaskCreate/TaskUpdate with all tasks]

Task 0: Broad integration tests

[Dispatch implementer subagent for Task 0]
Implementer: Created test_feature_e2e.py with 4 failing tests.
  Created stub files for modules. All tests RED as expected. Committed.

[Spec + code quality review pass]
[Mark Task 0 complete]

Task 1: Hook installation script

[Get Task 1 text and context (already extracted)]
[Dispatch implementation subagent with full task text + context]

Implementer: "Before I begin - should the hook be installed at user or system level?"

You: "User level (~/.config/superpowers/hooks/)"

Implementer: "Got it. Implementing now..."
[Later] Implementer:
  - Implemented install-hook command
  - Added tests, 5/5 passing
  - Self-review: Found I missed --force flag, added it
  - Committed

[Dispatch spec compliance reviewer]
Spec reviewer: ✅ Spec compliant - all requirements met, nothing extra

[Get git SHAs, dispatch code quality reviewer]
Code reviewer: Strengths: Good test coverage, clean. Issues: None. Approved.

[Mark Task 1 complete]

Task 2: Recovery modes

[Get Task 2 text and context (already extracted)]
[Dispatch implementation subagent with full task text + context]

Implementer: [No questions, proceeds]
Implementer:
  - Added verify/repair modes
  - 8/8 tests passing
  - Self-review: All good
  - Committed

[Dispatch spec compliance reviewer]
Spec reviewer: ❌ Issues:
  - Missing: Progress reporting (spec says "report every 100 items")
  - Extra: Added --json flag (not requested)

[Implementer fixes issues]
Implementer: Removed --json flag, added progress reporting

[Spec reviewer reviews again]
Spec reviewer: ✅ Spec compliant now

[Dispatch code quality reviewer]
Code reviewer: Strengths: Solid. Issues (Important): Magic number (100)

[Implementer fixes]
Implementer: Extracted PROGRESS_INTERVAL constant

[Code reviewer reviews again]
Code reviewer: ✅ Approved

[Mark Task 2 complete]

...

[After all tasks]
[Verify Task 0 broad integration tests now pass (GREEN)]

[Auto-dispatch implementation reviewer (skills/implementation-review/reviewer-prompt.md)]
Implementation reviewer: Found 2 cross-task issues:
  - Duplicated constant in fetcher.ts and cache.ts
  - Error message in cli.ts doesn't explain what went wrong

[Fix cross-task issues, re-dispatch implementation reviewer]
Implementation reviewer: No cross-task issues remaining

[Auto-invoke superpowers:ship — commits, pushes, creates PR]
PR created! Waiting for CodeRabbit review. Use /merge-pr after review.
```

**Integration test levels:** Task 0 provides Level 1 (broad acceptance tests, written first). Each implementer writes Level 2 (boundary tests at cross-task seams, during TDD). Implementation-review provides Level 3 (coverage verification). See test-driven-development/testing-anti-patterns.md Anti-Pattern 5 for details.

## Deviation Rules

When reality diverges from the plan, follow these rules in order:

| Rule | Trigger | Action | Permission |
|------|---------|--------|------------|
| **Rule 1: Auto-fix bugs** | Code doesn't work as intended | Fix inline, commit, document | No user permission needed |
| **Rule 2: Auto-add missing critical** | Missing error handling, validation, auth | Fix inline, commit, document | No user permission needed |
| **Rule 3: Auto-fix blockers** | Missing dep, broken import, wrong types | Fix inline, commit, document | No user permission needed |
| **Rule 4: STOP for architectural changes** | New DB table, library swap, breaking API change | **Stop and ask user** | Requires explicit user decision |

**Scope boundary:** Only auto-fix issues directly caused by the current task's changes. Pre-existing issues go to a deferred list — note them in the task completion report but don't fix them.

**Fix attempt limit:** After 3 auto-fix attempts on a single issue, stop and document the remaining problem. Don't loop indefinitely.

**Documentation:** For every Rule 1-3 deviation, the implementer subagent must include in its completion report:
- What deviated from the plan
- What was done to fix it
- Which rule applied

The orchestrator includes deviation summaries in the final report.

## Plan Doc Updates

The orchestrator updates the plan document during execution to maintain a living record.

**On first task start:**
1. Read the plan file
2. Change the frontmatter `status: Not Yet Started` to `status: In Development`
3. Change the current phase's `**Status:** Not Yet Started` to `**Status:** In Development`

**On each task completion:**
1. In the plan file's phase checklist, change `- [ ] Task N: ...` to `- [x] Task N: ...` for the completed task

**After all tasks complete (before invoking implementation-review):**
1. Append a `## Completion Report — [Phase Name]` section to the end of the plan doc
2. Include:
   - `**Completed:** YYYY-MM-DD`
   - `### Summary` — 2-3 sentences describing what was built
   - `### Deviations from Plan` — each deviation with: what changed, why, and impact (files/scope affected). Include Rule 1-3 auto-fixes from the deviation log. If no deviations, write "None — implemented as planned."

**After implementation-review passes:**
1. Change the current phase's status to `**Status:** Complete (YYYY-MM-DD)`
2. If all phases are complete, change the frontmatter to `status: Complete (YYYY-MM-DD)`

## Implementation Review (Auto-Dispatched)

After the completion report is written and Task 0 integration tests pass GREEN:

**Gather inputs:**
- `{BASE_SHA}` — `git merge-base HEAD origin/main`
- `{HEAD_SHA}` — `git rev-parse HEAD`
- `{FEATURE_SUMMARY}` — 1-2 sentence summary from the plan
- `{TASK_LIST}` — list of tasks implemented
- `{PLAN_FILE_PATH}` — path to plan doc (contains completion report)
- `{REPO_PATH}` — codebase root

**Dispatch reviewer:**

Use the Agent tool (general-purpose, model: "opus") with the prompt template from `skills/implementation-review/reviewer-prompt.md`, substituting all variables above.

**Handle result:**
- If issues found: dispatch a fix subagent or fix directly, re-dispatch reviewer
- Repeat until clean

**Post-review plan doc updates:**
- Append `### Implementation Review Changes` to the completion report (if fixups were made)
- Write handoff notes to next phase (if multi-phase plan)
- Update phase status to `Complete (YYYY-MM-DD)`

## Key Constraints

| Constraint | Why it matters |
|-----------|---------------|
| One implementer at a time | Parallel implementers cause git conflicts and file overwrites |
| Provide full task text, don't make subagent read the plan file | Reading wastes subagent context on irrelevant tasks; controller curates what's needed |
| Spec compliance before code quality review | Code quality review is wasted effort if the implementation doesn't match spec |
| Answer subagent questions before they proceed | Subagents working on assumptions produce work that needs to be redone |

## Integration

**Required workflow skills:**
- **superpowers:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **superpowers:writing-plans** - Creates the plan this skill executes
- **superpowers:requesting-code-review** - Code review template for reviewer subagents
- **superpowers:implementation-review** - Fresh-eyes review of entire feature after all tasks
- **superpowers:ship** - Auto-invoked after implementation review to commit, push, and create PR
- **superpowers:merge-pr** - Used after CodeRabbit review to address feedback, merge, and clean up

**Subagents should use:**
- **superpowers:test-driven-development** - Subagents follow TDD for each task

