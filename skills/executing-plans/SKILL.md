---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
---

# Executing Plans

## Overview

Load plan, review critically, execute tasks in batches, report for review between batches.

**Core principle:** Batch execution with checkpoints for architect review.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

## The Process

### Step 0: Load Persisted Tasks

Check for existing task state from a prior session:

1. Call `TaskList` to check for existing native tasks
2. If tasks exist: Resume from where the previous session left off — find the first non-completed task
3. If no tasks: Look for `.tasks.json` co-located with the plan file (e.g. `docs/plans/.tasks.json`)
4. If `.tasks.json` found: Recreate native tasks with `TaskCreate`, preserving `blockedBy` dependencies and marking already-completed tasks
5. If neither exists: Bootstrap tasks from the plan (Step 1b below)

### Step 0.5: Verify Plan Review

Before executing, confirm the plan has passed superpowers:plan-review:
1. Check if a plan review was already run (ask user or check conversation context)
2. If NOT reviewed: **REQUIRED SUB-SKILL:** Run superpowers:plan-review before proceeding
3. If reviewed and passed: Continue to Step 1

**Do NOT skip this.** Executing an unreviewed plan wastes implementation effort on inconsistencies that are cheap to fix in the plan.

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns and no tasks loaded from Step 0: Create tasks with `TaskCreate` for each plan task, setting `blockedBy` dependencies for sequential tasks (Step 1b)

### Step 2: Execute Batch
**Default: First 3 tasks**

For each task:
1. `TaskUpdate` to mark as `in_progress`
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. `TaskUpdate` to mark as `completed`
5. Update `.tasks.json` with new status (enables cross-session resume)

### Step 3: Report
When batch complete:
- Show what was implemented
- Show verification output
- Say: "Ready for feedback."

### Step 4: Continue
Based on feedback:
- Apply changes if needed
- Execute next batch
- Repeat until complete

### Step 5: Implementation Review

After all tasks complete and verified:
- **REQUIRED SUB-SKILL:** Use superpowers:implementation-review
- Fresh-eyes review of entire feature (base-branch..HEAD, not just final batch)
- Fix any cross-task issues found, re-run until clean

### Step 6: Complete Development

After implementation review passes:
- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch
- Follow that skill to verify tests, present options, execute choice

## Deviation Rules

When reality diverges from the plan, follow these rules in order:

| Rule | Trigger | Action | Permission |
|------|---------|--------|------------|
| **Rule 1: Auto-fix bugs** | Code doesn't work as intended | Fix inline, commit, document | No user permission needed |
| **Rule 2: Auto-add missing critical** | Missing error handling, validation, auth | Fix inline, commit, document | No user permission needed |
| **Rule 3: Auto-fix blockers** | Missing dep, broken import, wrong types | Fix inline, commit, document | No user permission needed |
| **Rule 4: STOP for architectural changes** | New DB table, library swap, breaking API change | **Stop and ask user** | Requires explicit user decision |

**Scope boundary:** Only auto-fix issues directly caused by the current task's changes. Pre-existing issues go to a deferred list — note them in the batch report but don't fix them.

**Fix attempt limit:** After 3 auto-fix attempts on a single issue, stop and document the remaining problem. Don't loop indefinitely.

**Documentation:** For every Rule 1-3 deviation, include in the batch report:
- What deviated from the plan
- What was done to fix it
- Which rule applied

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Rule 4 deviation (architectural change needed)
- Hit a blocker mid-batch after 3 fix attempts
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Reference skills when plan says to
- Between batches: just report and wait
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

**Required workflow skills:**
- **superpowers:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **superpowers:writing-plans** - Creates the plan this skill executes
- **superpowers:plan-review** - Validates plan consistency before execution begins
- **superpowers:implementation-review** - Fresh-eyes review of entire feature after all batches
- **superpowers:finishing-a-development-branch** - Complete development after all tasks
