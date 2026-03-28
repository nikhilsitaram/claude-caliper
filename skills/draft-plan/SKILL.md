---
name: draft-plan
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

# Writing Plans

Write implementation plans assuming the executor has zero codebase context. Document everything: which files to touch, exact code, how to test, what to avoid and why.

**Save to:** `.claude/claude-caliper/YYYY-MM-DD-<topic>/` directory

## Workflow

1. **Initialize** — `TaskList` to check for prior session context
2. **Entry gate** — `scripts/validate-plan --check-entry $PLAN_DIR/plan.json --stage draft-plan` (exits early if design-review hasn't passed; the plan.json file need not exist yet — only reviews.json is read)
3. **Explore codebase** — Understand patterns, find exact file paths
4. **Decide phasing** — Single vs multi-phase (see Phasing below)
5. **Write plan.json** — Structured manifest with all task metadata
6. **Write task .md files** — Prose for each task (Avoid+WHY, Steps)
7. **Create completion.md stubs** — Empty files, one per phase
8. **Run scripts/validate-plan --schema** — Fix any structural errors
9. **Run scripts/validate-plan --render** — Generates plan.md deterministically
10. **Skip** — plan artifacts are under `.claude/claude-caliper/` (gitignored), no commit needed
11. **Hand off** — Report plan path to caller. Plan-review is dispatched by the design skill after draft-plan returns.

## Plan Structure

**Directory layout:**

```text
.claude/claude-caliper/YYYY-MM-DD-topic/
├── plan.json             # Structured manifest (source of truth)
├── plan.md               # Generated outline (DO NOT edit)
├── phase-a/
│   ├── completion.md     # Empty stub (lead aggregates per-task completions)
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
  "workflow": "pr-create",
  "execution_mode": "subagents",
  "goal": "One sentence",
  "architecture": "2-3 sentences",
  "tech_stack": "Key technologies",
  "phases": [
    {
      "letter": "A",
      "name": "Core API",
      "status": "Not Started",
      "depends_on": [],
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

Optional: `success_criteria` at plan/phase/task levels. `workflow`: `pr-create` (default), `pr-merge`, or `plan-only` — set by design skill. `execution_mode`: `subagents` (default placeholder) or `agent-teams` — design skill overwrites after draft-plan. `review_wait_minutes`: max wait for external reviewers (default 10, 0 to skip).

**See:** `schema-reference.md` for full schema reference.

**Task .md file structure:**

```markdown
# A1: Setup route handlers

**Avoid:** Don't use express — we're on Hono. Edge runtime compatibility.

## Steps

### Step 1: Write failing test for GET /api/health

(Full TDD cycle with code)
```

H1 header must match `# {id}: {name}` from plan.json. When a task consumes output from a prior phase, the lead appends a handoff section after the H1.

## Phasing

**Multi-phase when:** dependency layers, verification gates, or independent shipping. **Single-phase when:** tasks are independent. Use A-prefix (A1, A2...).

**Gates:** 8+ tasks single-phase → look for hidden boundary. 7+ tasks per phase → examine cut points.

Phase boundaries = meaningful "run full suite" points. Each phase gets `phase-{letter}/` with `completion.md` + task files. `depends_on` declares phase ordering. Tasks within a phase execute in parallel — file sets must be disjoint (`validate-plan --schema` enforces this).

Inherit phases from design doc if approved.

## Task Structure

Every task splits metadata (plan.json) and prose (task .md file).

**plan.json fields:**

| Field | Requirement | Good |
|-------|-------------|------|
| **files** | Exact paths (create/modify/test) | `{"create": ["src/auth/login.ts"], "test": ["tests/auth/login.test.ts"]}` |
| **verification** | Runnable command, <60s | `pytest tests/auth/ -v` |
| **done_when** | Measurable end state | `login returns JWT, 4/4 tests pass` |
| **depends_on** | Task IDs this consumes | `["A1", "A2"]` (same phase for semantic ordering, prior phase for cross-phase deps) |

**Task .md file content:**

| Field | Requirement | Good |
|-------|-------------|------|
| **Avoid + WHY** | Pitfalls with reasoning | "Use jose not jsonwebtoken — CJS/Edge issues" |
| **Steps** | TDD cycle per step | Write failing test, verify fail, implement, verify pass, commit |

Write complete code in each step — not "add validation" or "implement the handler."

**Interface-first ordering:** Define contracts first, implement in middle tasks, wire consumers last.

**First task as integration tests:** When cross-task data flow exists, A1 can be broad integration tests (double-loop TDD) that stay RED until the last piece lands.

**Handoff notes:** The lead writes handoff sections to cross-phase task files between phases. Draft-plan doesn't write these.

**Fresh Claude Test:** Could a fresh Claude with zero context execute this task without clarifying questions? Exact paths and measurable done_when = pass.

