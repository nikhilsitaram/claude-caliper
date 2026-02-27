---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** This should be run in a dedicated worktree (created by brainstorming skill).

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

## REQUIRED FIRST STEP: Initialize Task Tracking

Before any exploration or planning, call `TaskList` to check for existing tasks from a prior session. Then call `TaskCreate` for each major planning phase (explore codebase, write tasks, save plan, handoff).

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

Every task MUST include ALL of the following fields. Missing fields = incomplete plan.

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Verification:** `pytest tests/path/test.py -v` (must complete in <60s)

**Done when:** [Measurable state — not "it works" or "authentication complete"]
Example: "POST /api/auth/login returns 200 with valid JWT; 401 with invalid credentials; test_login_* 4/4 passing"

**Avoid:** [What NOT to do + WHY]
Example: "Use jose not jsonwebtoken — CommonJS issues with Edge runtime"

**Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

**Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

**Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

### Mandatory Task Field Checklist

Before saving the plan, verify EVERY task has:

| Field | Requirement | Bad Example | Good Example |
|-------|-------------|-------------|--------------|
| **Files** | Exact paths (create/modify/test) | "the auth files" | `src/auth/login.ts`, `tests/auth/login.test.ts` |
| **Verification** | Automated, runnable, <60s | "check that it works" | `pytest tests/auth/ -v` |
| **Done when** | Measurable end state | "authentication complete" | "login returns JWT, 4/4 tests pass" |
| **Avoid + WHY** | Pitfalls with reasoning | "don't use X" | "Use jose not jsonwebtoken — CJS/Edge issues" |

### Specificity Quality Bar

> Could a fresh Claude instance with zero prior context execute this task without asking a single clarifying question? If not, add specificity.

## Interface-First Task Ordering

When a plan creates interfaces consumed by later tasks:

1. **First task:** Define contracts (types, interfaces, exports) — embed the contract text in the plan itself
2. **Middle tasks:** Implement against contracts
3. **Last task:** Wire implementations to consumers

Embed the contract in the plan so executors don't need to explore the codebase to understand dependencies.

Example ordering:
```
Task 1: Define UserService interface and types     ← contract
Task 2: Implement UserService against interface     ← implements contract
Task 3: Implement UserRepository against interface  ← implements contract
Task 4: Wire UserService into API routes            ← consumes implementations
```

## Remember
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- Reference relevant skills with @ syntax
- DRY, YAGNI, TDD, frequent commits
- Every task passes the "fresh Claude" specificity test

## Task Persistence

After saving the plan, write a `.tasks.json` file co-located with the plan document. This enables cross-session resume:

```json
{
  "planFile": "docs/plans/YYYY-MM-DD-feature-name.md",
  "createdAt": "ISO-8601 timestamp",
  "tasks": [
    {
      "id": 1,
      "title": "Task 1: Component Name",
      "status": "pending",
      "blockedBy": []
    },
    {
      "id": 2,
      "title": "Task 2: Next Component",
      "status": "pending",
      "blockedBy": [1]
    }
  ]
}
```

**File location:** Same directory as the plan, e.g. `docs/plans/.tasks.json`

When tasks are completed during execution, the executing skill updates this file so progress survives session boundaries.

## Plan Review (Required)

<HARD-GATE>
After saving the plan and `.tasks.json`, run plan-review BEFORE offering execution options. Do NOT skip this step. Do NOT proceed to execution without a passing review.
</HARD-GATE>

**REQUIRED SUB-SKILL:** Use superpowers:plan-review to validate the plan.

Provide the reviewer with:
- The plan file path
- The design doc path (if one exists from brainstorming)
- The codebase root (worktree path)

**If issues found:** Fix the plan, update `.tasks.json` if structure changed, re-run review.

**If clean:** Proceed to execution handoff.

## Execution Handoff

<HARD-GATE>
After plan review passes, use `AskUserQuestion` to present the execution choice. Do NOT proceed to implementation without an explicit answer.
</HARD-GATE>

Use `AskUserQuestion` with these options:

**Question:** "Plan reviewed and validated. Saved to `docs/plans/<filename>.md`. How would you like to execute?"

**Option 1: Subagent-Driven (this session)**
- Description: "Dispatch an Opus orchestrator subagent with fresh context to run subagent-driven-development. Fast iteration, two-stage review per task."

**Option 2: Parallel Session (separate)**
- Description: "Open a new session in the worktree directory and use executing-plans. Batch execution with human checkpoints between batches."

**After user answers:**

**If Subagent-Driven chosen:**

Dispatch a fresh **Opus** orchestrator subagent via the `Task` tool with `model: "opus"`. The orchestrator starts with zero prior context — all planning baggage stays in the parent. This is the automatic equivalent of `/clear` before execution.

The orchestrator prompt MUST include:
1. The full path to the plan file (e.g. `docs/plans/YYYY-MM-DD-feature.md`)
2. The working directory (worktree path)
3. Instruction to use `superpowers:subagent-driven-development` skill
4. Instruction to use `superpowers:finishing-a-development-branch` when complete

Example Task dispatch:
```
Task(
  description: "Execute implementation plan",
  model: "opus",
  prompt: "You are an orchestrator. Read the plan at docs/plans/<filename>.md and execute it using the superpowers:subagent-driven-development skill. When all tasks are complete, use superpowers:finishing-a-development-branch to wrap up. Working directory: <worktree-path>"
)
```

**If Parallel Session chosen:**
- Guide them to open new session in worktree
- **REQUIRED SUB-SKILL:** New session uses superpowers:executing-plans
