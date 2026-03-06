---
name: draft-plan
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

Write implementation plans assuming the executor has zero codebase context. Document everything: which files to touch, exact code, how to test, what to avoid and why.

**Context:** Runs as a fresh subagent dispatched by design after design approval. All needed context comes from the design doc — no live conversation context is carried over.

**Save to:** `docs/plans/YYYY-MM-DD-<topic>/plan-<topic>.md`

## Workflow

1. **Initialize tracking** — `TaskList` for prior session, `TaskCreate` for planning phases
2. **Explore codebase** — Understand patterns, find exact file paths
3. **Decide phasing** — Single vs multi-phase (see Phasing below)
4. **Write tasks** — Each task follows required structure
5. **Save plan** — Write to plan file with frontmatter
6. **Run plan review** — Dispatch reviewer, fix issues until clean
7. **Hand off to execution** — Dispatch fresh orchestrator

## Plan Document Structure

```markdown
---
status: Not Yet Started
---

# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** [One sentence]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]

---

### Phase 1 — [Name]
**Status:** Not Yet Started
**Rationale:** [Why this phase exists]

- [ ] Task 0: Write failing broad integration tests (skip for single-module changes)
- [ ] Task 1: [Title]

---

## Task Details
```

## Phasing

**Use multiple phases when:** dependency layers exist (Phase N creates things Phase N+1 consumes), verification gates are needed (confirm N works before starting N+1), or phases ship independently.

**Stay single-phase when:** tasks are independent or share a linear chain with no natural cut points. Don't phase for phasing's sake.

**Complexity gates:**
- **8+ tasks in a single-phase plan** — almost always has a hidden dependency boundary. Look for it before proceeding.
- **7+ tasks in any individual phase** — examine for cut points. Large phases make debugging harder ("which of 9 tasks broke this?").

**Phase boundaries** fall where "run full suite and verify" is meaningful. Each phase ends with a verification task and a one-sentence rationale explaining why it exists.

**Design doc inheritance:** If the design doc already has approved phases, use those as the starting structure. Don't contradict without flagging.

## Task Structure

Every task includes all fields below — missing any one means a fresh executor stalls or guesses wrong.

| Field | Requirement | Bad | Good |
|-------|-------------|-----|------|
| **Files** | Exact paths (create/modify/test) | "the auth files" | `src/auth/login.ts`, `tests/auth/login.test.ts` |
| **Verification** | Runnable command, <60s | "check that it works" | `pytest tests/auth/ -v` |
| **Done when** | Measurable end state | "authentication complete" | "login returns JWT, 4/4 tests pass" |
| **Avoid + WHY** | Pitfalls with reasoning | "don't use X" | "Use jose not jsonwebtoken — CJS/Edge issues" |
| **Steps** | TDD cycle per step | "add validation" | Write failing test, verify fail, implement, verify pass, commit |

Write complete code in each step — not "add validation" or "implement the handler." If the executor has to guess what the code looks like, the plan isn't specific enough.

### Task Template

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Verification:** `pytest tests/path/test.py -v`

**Done when:** POST /api/auth/login returns 200 with valid JWT; 401 with invalid credentials; test_login_* 4/4 passing

**Avoid:** Use jose not jsonwebtoken — CommonJS issues with Edge runtime

**Step 1: Write the failing test**
```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

**Step 2: Run test to verify it fails**
`pytest tests/path/test.py::test_name -v` — expect FAIL

**Step 3: Write minimal implementation**
```python
def function(input):
    return expected
```

**Step 4: Run test to verify it passes**
`pytest tests/path/test.py::test_name -v` — expect PASS

**Step 5: Commit**
```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

**Interface-first ordering:** Define contracts first (embed in plan), implement against them in middle tasks, wire consumers last.

**Task 0 (broad integration tests):** The outer loop of double-loop TDD. Write end-to-end tests with stub imports that stay RED until the last piece lands. Stubs should compile/parse but fail on assertions, not imports. Skip for single-module changes with no cross-task data flow.

### The Fresh Claude Test

> Could a fresh Claude with zero prior context execute this task without asking a single clarifying question?

Vague paths ("the auth files") or done-when ("authentication complete") fail this test. Exact paths and measurable outcomes pass.

## Plan Review Gate

After saving, dispatch plan-review before execution. Plans with issues get fixed and re-reviewed until clean.

**Gather:** `{PLAN_PATH}`, `{DESIGN_DOC_PATH}` (or "None"), `{REPO_PATH}`

**Dispatch:** Agent tool (general-purpose, model: "opus") with prompt from `skills/plan-review/reviewer-prompt.md`

Skipping review risks plans with missing paths or ordering bugs reaching execution where they're harder to fix.

## Execution Handoff

After review passes, dispatch a fresh Opus orchestrator with zero planning context (automatic `/clear`).

Prompt includes: plan file path, working directory, instruction to use `orchestrate`, instruction to use `ship` when complete.

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Read the plan at docs/plans/<folder>/plan-<topic>.md and execute
    using orchestrate. When complete, use
    implementation-review then ship.
    Working directory: <worktree-path>"
)
```
