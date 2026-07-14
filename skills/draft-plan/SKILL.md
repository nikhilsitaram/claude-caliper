---
name: draft-plan
description: Use when you have a spec or requirements for a multi-step task, before touching code
---

> **Subagent dispatch:** Use `subagent_type: "claude-caliper:plan-drafter"`. The agent definition contains the full planning methodology. The invocation prompt needs only the design doc path, working directory, and plan directory.

# Writing Plans

A plan is `plan.json` — a structured manifest of phases and tasks. Each task carries *intent*, not code: enough for a fresh Claude, reading the codebase directly at full context, to execute it unambiguously. Plans never paste implementation code and never spawn per-task `.md` files. `plan.md` is rendered from `plan.json`; you don't write it by hand.

**Save to:** the absolute `$PLAN_DIR` injected by the dispatcher (resolves to `$MAIN_ROOT/.claude/claude-caliper/YYYY-MM-DD-<topic>/` in the main repo, not the worktree). Plans are gitignored but persist across worktree cleanup.

## Workflow

1. **Initialize** — `TaskList` to check for prior session context
2. **Entry gate** — `validate-plan --check-entry $PLAN_DIR/plan.json --stage draft-plan` (exits early if design-review hasn't passed; plan.json need not exist yet — only reviews.json is read)
3. **Explore codebase** — Understand patterns, find exact file paths. You know the codebase so the implementer's `intent` can be terse and precise.
4. **Decide phasing** — Single vs multi-phase (see Phasing below)
5. **Write plan.json** — All task metadata, including `intent` and `avoid` (see Task Structure)
6. **Run validate-plan --schema** — Fix any structural errors
7. **Run validate-plan --render** — Generates plan.md deterministically
8. **Self-review** — Re-read every task entry against the Self-Review Gate below. Fix findings before handoff.
9. **Skip commit** — plan artifacts live under `$MAIN_ROOT/.claude/claude-caliper/` (gitignored)
10. **Hand off** — Report plan path to caller. Plan-review is dispatched by the design skill after draft-plan returns.

## Plan Structure

**Directory layout:**

```text
.claude/claude-caliper/YYYY-MM-DD-topic/
├── plan.json             # Structured manifest (source of truth)
└── plan.md               # Generated outline (DO NOT edit)
```

`plan.json` is the only artifact you write. `plan.md` is rendered. Per-phase `completion.md` files are created later by the orchestrate lead as the reviewer's aggregation point — not by draft-plan.

**plan.json shape:**

```json
{
  "schema": 2,
  "status": "Not Yet Started",
  "workflow": "pr-create",
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
          "intent": "Add the HTTP route handlers exposing health and auth endpoints so downstream consumers have a stable surface. Foundation task — nothing else in the phase wires up until these routes return well-formed responses.",
          "depends_on": [],
          "complexity": "medium",
          "files": { "create": ["src/routes.ts"], "modify": [], "test": ["tests/routes.test.ts"] },
          "verification": "npx jest tests/routes.test.ts",
          "done_when": "Handler returns 200, 2/2 tests pass",
          "avoid": [
            { "rule": "Don't use express", "why": "we're on Hono for edge-runtime compatibility" }
          ]
        }
      ]
    }
  ]
}
```

`workflow` (`pr-create` | `pr-merge` | `orchestrate` | `plan-only`) is set by the design skill, not chosen here. `success_criteria` is optional at plan/phase/task levels.

**See:** `schema-reference.md` for the full field reference, status lifecycle, and `validate-plan` modes.

## Phasing

**Multi-phase when:** dependency layers, verification gates, or independent shipping. **Single-phase when:** tasks are independent. Use A-prefix (A1, A2...).

**Gates:** 8+ tasks single-phase → look for hidden boundary. 7+ tasks per phase → examine cut points.

Phase boundaries = meaningful "run full suite" points. `depends_on` (phase level) declares phase ordering. Tasks within a phase execute in parallel — file sets must be disjoint (`validate-plan --schema` enforces this).

Inherit phases from design doc if approved.

## Task Consolidation

Each task carries fixed overhead: worktree creation, subagent dispatch, and its share of the phase review. Trivial tasks (single-line changes, import additions, config updates) don't justify that cost individually. Before finalizing, scan for consolidation:

- **Bundle mechanical changes:** If multiple files each need small, mechanical edits (renaming an export, adding an import, updating a config value), combine them into one task. A single task can span many files as long as the changes are cohesive and the verification is straightforward.
- **Keep substantive tasks separate:** Changes requiring design decisions, new logic, or non-trivial testing stay their own task — consolidation is for rote work, not for collapsing genuinely independent features.
- **Rule of thumb:** If a task's `intent` would be shorter than the rest of its metadata, it's too small — look for neighbors to merge with.
- **Discipline for consolidated tasks:** Mechanical changes don't need per-file red/green cycles. State a single verification pass in `intent` (e.g., "run the full test suite and confirm no regressions") rather than step-by-step TDD. The implementer follows whatever the task prescribes.

## Task Structure

Every task is a single plan.json entry — no split prose file. The two fields that carry direction:

| Field | Requirement | Good |
|-------|-------------|------|
| **intent** | 2–4 sentences: *what* to build and *why*. Names the component and its behavior; states how it fits the phase. No pasted code. | "Add JWT validation middleware that rejects expired/invalid tokens before the handler runs, so protected routes can trust `req.user`. Consumed by every task in Phase B." |
| **avoid** | Array of `{rule, why}` — each pitfall with its reason | `{"rule": "Use jose not jsonwebtoken", "why": "jsonwebtoken has CJS/Edge issues on the target runtime"}` |
| **files** | Exact paths (create/modify/test) | `{"create": ["src/auth/login.ts"], "test": ["tests/auth/login.test.ts"]}` |
| **verification** | Runnable command, <60s | `pytest tests/auth/ -v` |
| **done_when** | Measurable end state | `login returns JWT, 4/4 tests pass` |
| **depends_on** | Task IDs this consumes | `["A1"]` (same phase for ordering, prior phase for cross-phase deps) |
| **complexity** | Enum: low, medium, high | `"medium"` |

The implementer reads the codebase directly, so `intent` states the outcome and seams — not line-by-line code.

**Interface-first ordering:** Define contracts first, implement in middle tasks, wire consumers last.

**Integration tests for cross-task seams:** When the design's `## Test Strategy` section names a seam (producer module → consumer module), the plan must include at least one task whose `done_when` exercises that seam end-to-end with no mock at the seam under test. The Test Strategy section is the trigger — the seams it names map 1:1 to integration tasks. Multi-phase plans and plans with cross-task `depends_on` are where seams typically exist, but the design doc, not the plan structure, is the source of truth.

**Placement rules — same-phase vs cross-phase seams:**

- **Same-phase seam** (producer and consumer in the same phase, or single-phase plan): place as the phase's A1 task using double-loop TDD (broad tests stay RED until the last piece lands).
- **Cross-phase seam** (Phase A producer → Phase B consumer): place as the final task of the consumer's phase (B-last), not A1. The A1 placement would make Phase A's impl-review fail because the consumer code doesn't exist yet when Phase A wraps up.

Either placement works as long as the seam is exercised without mocking the producer. Each integration task's `done_when` should name the seam explicitly: `"kv_launcher → kv_fetch seam runs end-to-end with real subprocess spawn, 1/1 test passes"` — not just `"integration tests pass"`. The named seam links the task back to design's Test Strategy and lets plan-review verify the contract.

**Handoff notes:** When a task depends on a prior phase's task, the orchestrate lead records the shipped-interface note into plan.json via `validate-plan --add-handoff` at the source phase's wrap-up (post-review, so it reflects the real interface). Draft-plan doesn't write these — just declare the `depends_on`.

## Self-Review Gate

Before handoff, re-read every task entry and the plan.json. The plan-reviewer downstream applies a checklist; catch these items here so review is pass/fail, not an editing pass. Goal at handoff: zero or one remaining issues.

**Per task:**

- **Different Claude Test** — Could a fresh Claude with only this entry and codebase access execute it unambiguously? No "the handler" or "the config" without a file path; `intent` names the component and its behavior.
- **Measurable `done_when`** — "4/4 tests pass" or "endpoint returns 200", not "auth works" or "feature complete".
- **Intent is outcome, not code** — Describes what and why and the seams; no pasted implementation.
- **Avoid + WHY** — Every `avoid` entry gives the reason, not just the prohibition.
- **Artifact consistency** — Same file/function names across `intent`, `files`, `avoid`, and `done_when`. Every path referenced exists in `files`.
- **Verification is runnable** — The command matches this codebase's tooling (npm vs yarn vs pnpm, pytest vs unittest).

**Across the plan:**

- **Design criteria map to tasks** — Each success criterion from the design doc is covered by at least one task's `done_when`. Missing criterion → add a task.
- **Test Strategy seams map to integration tasks** — Every seam in the design's `## Test Strategy` maps to a task whose `done_when` names the seam and the non-mocking constraint.
- **Consolidation sweep** — Any task whose `intent` is shorter than the rest of its metadata should merge with a neighbor.
- **Complexity gates** — 8+ tasks single-phase or 7+ per phase → split.
- **Interface-first ordering** — Tasks defining contracts precede tasks consuming them.
