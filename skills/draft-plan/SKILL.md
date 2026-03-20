---
name: draft-plan
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

Write implementation plans assuming the executor has zero codebase context. Document everything: which files to touch, exact code, how to test, what to avoid and why.

**Context:** Runs after design approval. All needed context comes from the design doc.

**Save to:** `docs/plans/YYYY-MM-DD-<topic>/` directory

## Workflow

1. **Initialize tracking** — `TaskList` for prior session, `TaskCreate` for planning phases
2. **Explore codebase** — Understand patterns, find exact file paths
3. **Decide phasing** — Single vs multi-phase (see Phasing below)
4. **Write plan.json** — Structured manifest with all task metadata
5. **Write task .md files** — Prose for each task (Avoid+WHY, Steps)
6. **Create completion.md stubs** — Empty files, one per phase
7. **Run scripts/validate-plan --schema** — Fix any structural errors
8. **Run scripts/validate-plan --render** — Generates plan.md deterministically
9. **Run plan review** — Dispatch reviewer, fix issues until clean
10. **Hand off to execution** — Report plan path to user

## Plan Structure

**Directory layout:**

```text
docs/plans/YYYY-MM-DD-topic/
├── plan.json             # Structured manifest (source of truth)
├── plan.md               # Generated outline (DO NOT edit)
├── phase-a/
│   ├── completion.md     # Empty stub (dispatcher fills)
│   ├── a1.md             # Task prose
│   └── a2.md
└── phase-b/
    ├── completion.md
    └── b1.md
```

**plan.json fields:**

```json
{
  "schema": 1,
  "status": "Not Yet Started",
  "goal": "One sentence",
  "architecture": "2-3 sentences",
  "tech_stack": "Key technologies",
  "phases": [
    {
      "letter": "A",
      "name": "Core API",
      "status": "Not Started",
      "rationale": "Foundation layer needed first",
      "tasks": [
        {
          "id": "A1",
          "name": "Setup route handlers",
          "status": "pending",
          "depends_on": [],
          "files": {
            "create": ["src/routes.ts"],
            "modify": [],
            "test": ["tests/routes.test.ts"]
          },
          "verification": "npx jest tests/routes.test.ts",
          "done_when": "Handler returns 200, 2/2 tests pass"
        }
      ]
    }
  ]
}
```

Optional: `success_criteria` array at plan, phase, and task levels for future automated verification.

**See:** `docs/plans/2026-03-19-structured-plans/design-structured-plans.md` for full schema reference.

**Task .md file structure:**

```markdown
# A1: Setup route handlers

**Avoid:** Don't use express — we're on Hono. Edge runtime compatibility.

## Steps

### Step 1: Write failing test for GET /api/health

(Full TDD cycle with code)
```

H1 header must match `# {id}: {name}` from plan.json. When a task consumes output from a prior phase, the source phase's dispatcher appends a handoff section after the H1.

## Phasing

**Use multiple phases when:** dependency layers exist (Phase A creates things Phase B consumes), verification gates are needed, or phases ship independently.

**Stay single-phase when:** tasks are independent or share a linear chain with no natural cut points. Don't phase for phasing's sake. Single-phase plans still use A-prefix (A1, A2, etc.).

**Complexity gates:**
- **8+ tasks in a single-phase plan** — almost always has a hidden dependency boundary. Look for it before proceeding.
- **7+ tasks in any individual phase** — examine for cut points. Large phases make debugging harder.

**Phase boundaries** fall where "run full suite and verify" is meaningful. Each phase gets its own directory (`phase-a/`, `phase-b/`) with a `completion.md` stub and task `.md` files. The phase's `rationale` field in plan.json explains why the phase exists.

**Design doc inheritance:** If the design doc already has approved phases, use those as the starting structure. Don't contradict without flagging.

## Task Structure

Every task splits metadata (plan.json) and prose (task .md file). Missing any field means the executor stalls or guesses wrong.

**plan.json fields:**

| Field | Requirement | Bad | Good |
|-------|-------------|-----|------|
| **files** | Exact paths (create/modify/test) | "the auth files" | `{"create": ["src/auth/login.ts"], "test": ["tests/auth/login.test.ts"]}` |
| **verification** | Runnable command, <60s | "check that it works" | `pytest tests/auth/ -v` |
| **done_when** | Measurable end state | "authentication complete" | `login returns JWT, 4/4 tests pass` |
| **depends_on** | Task IDs this consumes | `["A3", "B1"]` (invalid — wrong phase) | `["A1", "A2"]` (same/prior phase only) |

**Task .md file content:**

| Field | Requirement | Bad | Good |
|-------|-------------|-----|------|
| **Avoid + WHY** | Pitfalls with reasoning | "don't use X" | "Use jose not jsonwebtoken — CJS/Edge issues" |
| **Steps** | TDD cycle per step | "add validation" | Write failing test, verify fail, implement, verify pass, commit |

Write complete code in each step — not "add validation" or "implement the handler." If the executor has to guess what the code looks like, the plan isn't specific enough.

**Interface-first ordering:** Define contracts first (embed in plan), implement against them in middle tasks, wire consumers last.

**First task as integration tests:** When cross-task data flow exists, the first task in a phase (A1) can be broad integration tests — the outer loop of double-loop TDD. Write end-to-end tests with stub imports that stay RED until the last piece lands.

**Handoff notes:** The dispatcher appends handoff sections to cross-phase task files during execution. Draft-plan doesn't write these.

### The Fresh Claude Test

> Could a fresh Claude with zero prior context execute this task without asking a single clarifying question?

Vague paths ("the auth files") or done-when ("authentication complete") fail this test. Exact paths and measurable outcomes pass.

## Plan Review Gate

After creating all files, validate structure then dispatch LLM review:

1. **Run `scripts/validate-plan --schema <plan-dir>/plan.json`** — structural checks (required fields, file existence, H1 headers, dependency ordering, no duplicate file paths). Exit 0 = pass, exit 1 = errors to stderr. Fix errors and re-run until clean.

2. **Run `scripts/validate-plan --render <plan-dir>/plan.json`** — generates plan.md from plan.json. This is deterministic — same input produces same output.

3. **Dispatch plan-review** — LLM reviewer checks prose quality and applies the Different Claude Test (could a fresh Claude execute without asking questions?).

**See:** `skills/plan-review/reviewer-prompt.md` for dispatch details.

Skipping validation or review risks plans with missing paths, ordering bugs, or vague done-when conditions reaching execution where they're harder to fix.

## After Review Passes

Report the plan file path to the user. Run orchestrate in the main context where it can interact with the user for Rule 4 escalations and ship decisions.
