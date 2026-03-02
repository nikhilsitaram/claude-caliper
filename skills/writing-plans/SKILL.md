---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** This should be run in a dedicated worktree (created by brainstorming skill after design approval).

**Save plans to:** `docs/plans/YYYY-MM-DD-<topic>/plan-<topic>.md` (inside the topic folder created by brainstorming)

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

````markdown
---
status: Not Yet Started
---

# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---

## Phases

### Phase 1 — [Phase Name]
**Status:** Not Yet Started

- [ ] Task 0: Write failing broad integration tests
- [ ] Task 1: [Task title]
- [ ] Task 2: [Task title]

### Phase 2 — [Phase Name] (if multi-phase)
**Status:** Not Yet Started

- [ ] Task 3: [Task title]
- [ ] Task 4: [Task title]

---

## Task Details
````

**Status values:** `Not Yet Started` | `In Development` | `Complete (YYYY-MM-DD)`

The orchestrator (subagent-driven-development) updates these statuses during execution. The plan author only sets the initial `Not Yet Started` values.

For single-phase plans, use one phase section. The phase structure is required even for single-phase work — it keeps the format consistent and supports future phase additions.

## Phasing Decision

Before writing tasks, determine whether the plan needs multiple phases.

**Use multiple phases when ANY of these apply:**

1. **Dependency layers** — Phase N creates things (utilities, interfaces, schemas) consumed by Phase N+1. Example: shared utility extraction must land before bug fixes that import those utilities.
2. **Verification gates** — Phase N must be verified working before Phase N+1 can meaningfully start. Example: database schema changes must be tested before API routes that depend on the new schema.
3. **Independent shippability** — each phase should be deployable and revertible on its own. Example: "critical bugs" phase can ship independently of "code quality" phase.

**Stay single-phase when:** All tasks are independent or share only a linear dependency chain with no natural cut points. Don't phase for phasing's sake — one phase with 5 tasks is better than 5 phases with 1 task each.

**Phase boundary rules:**

- A boundary falls where "run full suite and verify" is meaningful — the work so far stands alone
- Each phase ends with a verification task ("Phase N commit — run full suite")
- Phase rationale required: one sentence per phase explaining why it exists and why it's in this position (e.g., "Everything downstream imports these. Must land first.")

**Design doc inheritance:** If the design doc includes an **Implementation Approach** section with approved phases from brainstorming, use those as the starting structure. You may refine (split a phase, add verification tasks) but should not contradict approved phasing without flagging the deviation to the user.

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
Task 0: Write failing broad integration tests        ← acceptance criteria (stays RED)
Task 1: Define UserService interface and types       ← contract
Task 2: Implement UserService against interface      ← implements contract
Task 3: Implement UserRepository against interface   ← implements contract
Task 4: Wire implementations to consumers            ← Task 0 tests go GREEN
```

## Broad Integration Tests (Task 0)

Every multi-task plan MUST include Task 0: failing broad integration tests that define the feature's acceptance criteria in code.

**What Task 0 contains:**
- End-to-end tests that exercise the feature's complete flow
- They import/reference modules that later tasks will create
- Stub files (empty exports, interface-only) so tests compile/parse
- All tests fail (RED) — they define "done," implementation hasn't started yet

**This is the outer loop of double-loop TDD:** Task 0 tests stay RED throughout implementation. They go GREEN when the last piece lands. If they don't go green, the feature isn't done.

**Task 0 follows normal task structure** (Files, Verification, Done when, Steps). Example:

    ### Task 0: Write failing broad integration tests

    **Files:**
    - Create: `tests/integration/test_feature_e2e.py`
    - Create: `src/module_a.py` (stub — empty exports only)
    - Create: `src/module_b.py` (stub — empty exports only)

    **Verification:** `pytest tests/integration/test_feature_e2e.py -v` — all tests FAIL (expected)

    **Done when:** Integration test file exists with 3+ test cases covering the feature's acceptance criteria. All tests fail because implementations are stubs. Stubs compile/parse without errors.

    **Avoid:** Don't implement any real logic in stubs — just enough for tests to parse and fail on assertions, not on import errors.

**Skip Task 0 when:** Single-module change, no cross-task data flow, or purely additive tasks with no interactions (e.g., adding independent utility functions).

## Remember
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- Reference relevant skills with @ syntax
- DRY, YAGNI, TDD, frequent commits
- Every task passes the "fresh Claude" specificity test

## Plan Review (Required)

<HARD-GATE>
After saving the plan, auto-dispatch a plan review subagent BEFORE offering execution options. Do NOT skip. Do NOT proceed to execution without a passing review.
</HARD-GATE>

**Announce:** "Running plan review before execution."

**Gather inputs:**
- `{PLAN_PATH}` — the plan file just saved
- `{DESIGN_DOC_PATH}` — design doc from brainstorming (or "None")
- `{REPO_PATH}` — codebase root (worktree path)

**Dispatch reviewer:**

Use the Agent tool (general-purpose, model: "opus") with the prompt template from `skills/plan-review/reviewer-prompt.md`, substituting the three variables above.

**Handle result:**
- If issues found: fix the plan, re-dispatch reviewer
- Repeat until clean
- Once clean: proceed to execution handoff

## Execution Handoff

After plan review passes, dispatch execution automatically.

Dispatch a fresh **Opus** orchestrator subagent via the `Task` tool with `model: "opus"`. The orchestrator starts with zero prior context — all planning baggage stays in the parent. This is the automatic equivalent of `/clear` before execution.

The orchestrator prompt MUST include:
1. The full path to the plan file (e.g. `docs/plans/YYYY-MM-DD-topic/plan-topic.md`)
2. The working directory (worktree path)
3. Instruction to use `superpowers:subagent-driven-development` skill
4. Instruction to use `superpowers:ship` when complete to commit, push, and create PR

Example Task dispatch:
```text
Task(
  description: "Execute implementation plan",
  model: "opus",
  prompt: "You are an orchestrator. Read the plan at docs/plans/<topic-folder>/plan-<topic>.md and execute it using the superpowers:subagent-driven-development skill. When all tasks are complete and completion report is written, use superpowers:implementation-review for fresh-eyes review, then superpowers:ship to commit, push, and create a PR. Working directory: <worktree-path>"
)
```
