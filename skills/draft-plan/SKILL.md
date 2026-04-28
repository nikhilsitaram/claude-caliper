---
name: draft-plan
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

> **Subagent dispatch:** Use `subagent_type: "claude-caliper:plan-drafter"`. The agent definition contains the full planning methodology. The invocation prompt needs only the design doc path, working directory, and plan directory.

# Writing Plans

Write implementation plans assuming the executor has zero codebase context. Document everything: which files to touch, exact code, how to test, what to avoid and why.

**Save to:** the absolute `$PLAN_DIR` injected by the dispatcher (resolves to `$MAIN_ROOT/.claude/claude-caliper/YYYY-MM-DD-<topic>/` in the main repo, not the worktree). Plans are gitignored but persist across worktree cleanup.

## Workflow

1. **Initialize** — `TaskList` to check for prior session context
2. **Entry gate** — `validate-plan --check-entry $PLAN_DIR/plan.json --stage draft-plan` (exits early if design-review hasn't passed; the plan.json file need not exist yet — only reviews.json is read)
3. **Explore codebase** — Understand patterns, find exact file paths
4. **Decide phasing** — Single vs multi-phase (see Phasing below)
5. **Write plan.json** — Structured manifest with all task metadata
6. **Write task .md files** — Prose for each task (Avoid+WHY, Steps). Each step shows complete code, not verbs like "add X" or "handle Y". Avoid sections explain *why*, not just *what*.
7. **Create completion.md stubs** — Empty files, one per phase
8. **Run validate-plan --schema** — Fix any structural errors
9. **Run validate-plan --render** — Generates plan.md deterministically
10. **Self-review** — Re-read every task file and check against the Self-Review Gate below. Fix findings before handoff.
11. **Skip** — plan artifacts are under `$MAIN_ROOT/.claude/claude-caliper/` (main repo root, gitignored), no commit needed
12. **Hand off** — Report plan path to caller. Plan-review is dispatched by the design skill after draft-plan returns.

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
          "complexity": "medium",
          "reviewer_needed": true,
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

Optional: `success_criteria` at plan/phase/task levels. `workflow`: `pr-create` (default), `pr-merge`, or `plan-only` — set by design skill. `execution_mode`: `subagents` (default placeholder) or `agent-teams` — design skill overwrites after draft-plan. `review_wait_minutes`: max wait for external reviewers (default 5, 0 to skip).

**See:** `schema-reference.md` for full schema reference.

**Task .md file structure:**

```markdown
# A1: Setup route handlers

**Avoid:** Don't use express — we're on Hono. Edge runtime compatibility.

## Steps

### Step 1: Write failing test for GET /api/health

(Full TDD cycle with code)
```

H1 header must match `# {id}: {name}` from plan.json. When a task consumes output from a prior phase, the orchestrate lead appends a handoff section after the H1 at the prior phase's wrap-up.

## Phasing

**Multi-phase when:** dependency layers, verification gates, or independent shipping. **Single-phase when:** tasks are independent. Use A-prefix (A1, A2...).

**Gates:** 8+ tasks single-phase → look for hidden boundary. 7+ tasks per phase → examine cut points.

Phase boundaries = meaningful "run full suite" points. Each phase gets `phase-{letter}/` with `completion.md` + task files. `depends_on` declares phase ordering. Tasks within a phase execute in parallel — file sets must be disjoint (`validate-plan --schema` enforces this).

Inherit phases from design doc if approved.

## Task Consolidation

Each task carries fixed overhead: worktree creation, subagent dispatch, and a review cycle. Trivial tasks (single-line changes, import additions, config updates) don't justify that cost individually. Before finalizing tasks, scan for consolidation opportunities:

- **Bundle mechanical changes:** If multiple files each need small, mechanical edits (renaming an export, adding an import, updating a config value), combine them into one task. A single task can span many files as long as the changes are cohesive and the verification is straightforward.
- **Keep substantive tasks separate:** Changes that require design decisions, new logic, or non-trivial testing should remain their own task — consolidation is for rote work, not for collapsing genuinely independent features.
- **Rule of thumb:** If a task's prose would be shorter than its plan.json metadata, it's too small — look for neighbors to merge with.
- **TDD for consolidated tasks:** Mechanical changes don't need per-file red/green cycles. In the task prose, specify a single verification pass (e.g., "run the full test suite and confirm no regressions") rather than step-by-step TDD. The implementer follows whatever discipline the task prose prescribes.

## Task Structure

Every task splits metadata (plan.json) and prose (task .md file).

**plan.json fields:**

| Field | Requirement | Good |
|-------|-------------|------|
| **files** | Exact paths (create/modify/test) | `{"create": ["src/auth/login.ts"], "test": ["tests/auth/login.test.ts"]}` |
| **verification** | Runnable command, <60s | `pytest tests/auth/ -v` |
| **done_when** | Measurable end state | `login returns JWT, 4/4 tests pass` |
| **depends_on** | Task IDs this consumes | `["A1", "A2"]` (same phase for semantic ordering, prior phase for cross-phase deps) |
| **complexity** | Enum: low, medium, high | `"medium"` |
| **reviewer_needed** | Bool — false only for low-complexity mechanical tasks | `true` |

**Task .md file content:**

| Field | Requirement | Good |
|-------|-------------|------|
| **Avoid + WHY** | Pitfalls with reasoning | "Use jose not jsonwebtoken — CJS/Edge issues" |
| **Steps** | TDD cycle per step (consolidated mechanical tasks: list changes + suite-level verification) | Write failing test, verify fail, implement, verify pass, commit |

Write complete code in each step — not "add validation" or "implement the handler."

**Interface-first ordering:** Define contracts first, implement in middle tasks, wire consumers last.

**First task as integration tests:** When cross-task data flow exists, A1 can be broad integration tests (double-loop TDD) that stay RED until the last piece lands.

**Handoff notes:** The orchestrate lead writes handoff sections to cross-phase task files at the source phase's wrap-up (post-review). Draft-plan doesn't write these.

## Self-Review Gate

Before handoff, re-read every task file and the plan.json. The plan-reviewer downstream applies a 7-point checklist; catch the prose-level items here so review is pass/fail, not an editing pass. Goal at handoff: zero or one remaining issues.

**Per task:**

- **Different Claude Test** — Could a fresh Claude with zero context execute this unambiguously? No "the handler" or "the config" without a file path.
- **Measurable `done_when`** — "4/4 tests pass" or "endpoint returns 200", not "auth works" or "feature complete".
- **Complete code in steps** — Actual code, not "add validation" or "implement the handler".
- **Avoid + WHY** — Every avoid section gives the reason, not just the prohibition.
- **Artifact consistency** — Same file/function name everywhere. Every path in `plan.json` matches its prose references; every function referenced in prose matches its declaration.
- **Verification is runnable** — The command exists in this codebase's tooling (npm vs yarn vs pnpm, pytest vs unittest).

**Across the plan:**

- **Design criteria map to tasks** — Each success criterion from the design doc is covered by at least one task's `done_when`. Missing criterion → add a task.
- **Consolidation sweep** — Any task whose prose is shorter than its plan.json metadata should merge with a neighbor (see Task Consolidation).
- **Complexity gates** — 8+ tasks single-phase or 7+ per phase → split.
- **Interface-first ordering** — Tasks defining contracts precede tasks consuming them.

