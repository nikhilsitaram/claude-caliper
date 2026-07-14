# plan.json Schema Reference (v2)

Full reference for the `plan.json` manifest and the `validate-plan` CLI. `plan.json` is the single source of truth for a plan — every task's metadata lives here, and there are no per-task `.md` files. `plan.md` is a read-only outline deterministically rendered from `plan.json`.

## Directory Layout

```text
.claude/claude-caliper/YYYY-MM-DD-topic/
├── design-topic.md       # Design doc (unchanged)
├── plan.json             # Structured manifest (source of truth)
├── plan.md               # Human-readable outline (rendered from plan.json — DO NOT edit)
├── reviews.json          # Review gate records (written by review skills)
├── phase-a/
│   └── completion.md     # Reviewer's aggregation point (written by the orchestrate lead)
└── phase-b/
    └── completion.md
```

There is exactly one `completion.md` per phase — the point where the orchestrate lead aggregates task outcomes for the phase's single implementation review. draft-plan writes only `plan.json` (and the rendered `plan.md`); the orchestrate lead creates `completion.md` at phase wrap-up. No per-task files of any kind.

## plan.json Schema

```json
{
  "schema": 2,
  "status": "Not Yet Started",
  "workflow": "pr-create",
  "goal": "One sentence",
  "architecture": "2-3 sentences",
  "tech_stack": "Key technologies",
  "success_criteria": [
    { "run": "npm test", "expect_exit": 0, "timeout": 120, "severity": "blocking" }
  ],
  "phases": [
    {
      "letter": "A",
      "name": "Core API",
      "status": "Not Started",
      "depends_on": [],
      "rationale": "Foundation layer needed before consumers",
      "success_criteria": [
        { "run": "pytest tests/integration/ -v", "expect_exit": 0 }
      ],
      "tasks": [
        {
          "id": "A1",
          "name": "Setup route handlers",
          "status": "pending",
          "intent": "Add the HTTP route handlers that expose the health and auth endpoints so downstream consumers have a stable surface to call. This is the foundation task — nothing else in the phase can be wired until these routes exist and return well-formed responses.",
          "depends_on": [],
          "complexity": "medium",
          "files": {
            "create": ["src/routes.ts"],
            "modify": [],
            "test": ["tests/routes.test.ts"]
          },
          "verification": "npx jest tests/routes.test.ts",
          "done_when": "Handler returns 200, 2/2 tests pass",
          "avoid": [
            { "rule": "Don't use express", "why": "we're on Hono for edge-runtime compatibility; express won't run on the target." }
          ],
          "success_criteria": [
            { "run": "npx jest tests/routes.test.ts", "expect_exit": 0, "expect_output": "2 passed" }
          ]
        }
      ]
    }
  ]
}
```

## Field Reference

### Plan level

- `schema` (integer, required): Schema version. Must be `2`. A schema-1 plan is rejected up front with a message naming the version change (there is no migration tooling — finish in-flight schema-1 plans on the previous plugin version).
- `status` (string, required): `Not Yet Started` | `In Development` | `Complete`.
- `workflow` (string, required): `pr-create` | `pr-merge` | `orchestrate` | `plan-only`. Set by the design skill's routing step; the drafter does not choose it.
- `goal` (string, required): One sentence.
- `architecture` (string, required): 2–3 sentences.
- `tech_stack` (string, required): Key technologies.
- `integration_branch` (string, optional): When present, the branch that phase worktrees and the final PR chain integrate onto. Must be a non-empty string. `validate-plan --check-base` enforces that execution runs from this branch.
- `success_criteria` (array, optional): Plan-level acceptance checks. Same shape at every level (see below). Present in the schema; enforced by the `--criteria` runner.

### success_criteria (plan / phase / task)

- `run` (string, required): Shell command. Must be non-empty.
- `expect_exit` (integer, optional): Expected exit code.
- `expect_output` (string, optional): Substring that must appear in stdout.
- `timeout` (integer, optional): Seconds before timeout. Default 60.
- `severity` (string, optional): `blocking` (default) | `warning`.
- At least one of `expect_exit` or `expect_output` is required per criterion.

### Phase level

- `phases[].letter` (string, required): Single uppercase letter (A, B, C). Phases must appear in alphabetical order.
- `phases[].name` (string, required).
- `phases[].status` (string, required): `Not Started` | `In Progress` | `Complete (YYYY-MM-DD)`.
- `phases[].depends_on` (array, required): Phase letters this phase depends on. Each must reference an earlier phase.
- `phases[].rationale` (string, required): Why this phase is a boundary.
- `phases[].success_criteria` (array, optional): Same shape as plan-level.

### Task level

- `phases[].tasks[].id` (string, required): Phase-letter prefix + number (`A1`). Must be unique; prefix must match the phase letter.
- `phases[].tasks[].name` (string, required).
- `phases[].tasks[].status` (string, required): `pending` | `in_progress` | `complete` | `skipped`.
- `phases[].tasks[].intent` (string, required): 2–4 sentences of *what* the task builds and *why*. This replaces per-task prose entirely. It must let a fresh Claude — reading the codebase directly at full context — execute the task unambiguously: which component, what behavior, how it fits the phase. It carries intent, never pasted implementation code.
- `phases[].tasks[].depends_on` (array of strings): Task IDs this task consumes output from. Must reference same or prior phase only.
- `phases[].tasks[].complexity` (string, required): `low` | `medium` | `high`.
  - `low`: mechanical/rote — rename, config update, import addition, single-line edits
  - `medium`: standard implementation with clear boundaries following existing patterns
  - `high`: multi-system integration, complex logic, novel patterns, or architectural decisions
- `phases[].tasks[].files` (object, required): `create`, `modify`, `test` — arrays of file paths (each key required, arrays may be empty). File paths must be unique across all tasks in the plan; file *sets* must be disjoint across tasks within a phase (they run in parallel).
- `phases[].tasks[].verification` (string, required): Runnable command, <60s.
- `phases[].tasks[].done_when` (string, required): Measurable end state.
- `phases[].tasks[].avoid` (array, required): Array of `{rule, why}` objects. Each object needs a non-empty `rule` (the pitfall to avoid) and a non-empty `why` (the reason). This is where task-specific pitfalls live now that there is no prose section.
- `phases[].tasks[].success_criteria` (array, optional): Same shape as plan-level.
- `phases[].tasks[].handoffs` (array, managed by CLI): `{from, note}` objects recording cross-phase context. Never hand-edit — written by `validate-plan --add-handoff` (see below) and rendered into plan.md.

## plan.md (rendered outline)

Deterministically generated from `plan.json` by `validate-plan --render` — never edited directly, never LLM-generated. It emits the `> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate` trigger line, one checklist entry per task (`complete`/`skipped` → `[x]`, else `[ ]`) with the task's `done_when` as the italic suffix, and a nested bullet per recorded handoff. `plan.json` is the source of truth; `plan.md` is derived.

## Handoffs

Cross-phase context is structured data, not prose. When a Phase B task depends on a Phase A task, the orchestrate lead records the shipped-interface note at Phase A's wrap-up (post-review, so it reflects reality):

```bash
validate-plan --add-handoff plan.json --task B1 --from A2 --note "Auth middleware exports validateToken() from src/auth/middleware.ts; use as app.use('/dashboard/*', validateToken())"
```

This appends `{from: "A2", note: "..."}` to task B1's `handoffs` array and re-renders plan.md. `validate-plan --check-handoffs plan.json --phase A` then verifies that every cross-phase dependency into a later phase has a recorded handoff (or an explicit `## Handoff Notes` opt-out beginning with `None` in the source phase's `completion.md`).

## validate-plan Modes

| Mode | When | What |
|---|---|---|
| `--schema plan.json` | Pre-orchestration, plan-review | Validate JSON structure, required fields/types, schema version, task-ID/phase-letter rules, `depends_on` ordering, `intent`/`avoid` presence and shape, disjoint file sets, non-empty criteria `run` strings. Chains to `--consistency`. |
| `--render plan.json` | Standalone (also called internally by `--update-status`/`--add-handoff`) | Deterministically generate plan.md from plan.json |
| `--update-status plan.json --task A1 --status complete` | After each task | Update task status + regenerate plan.md (enforces phase/dependency preconditions) |
| `--update-status plan.json --phase A --status "In Progress"` | Phase start/complete | Update phase status + regenerate plan.md (phase-complete requires all tasks done + impl-review gate) |
| `--update-status plan.json --plan --status "In Development"` | Plan lifecycle | Update plan status + regenerate plan.md |
| `--add-handoff plan.json --task B1 --from A2 --note "..."` | Phase wrap-up (cross-phase deps) | Record a handoff as structured data + regenerate plan.md |
| `--check-handoffs plan.json --phase A` | Phase wrap-up | Verify cross-phase deps into later phases have recorded handoffs |
| `--criteria plan.json --task A1 \| --phase A \| --plan` | Verification | Run `success_criteria` and report pass/fail |
| `--check-entry`, `--check-base`, `--check-review`, `--check-workflow`, `--consistency` | Gates | Review-gate, base-branch, and cross-status consistency checks |

### Schema validation checks (`--schema`)

- All required fields present with correct types; `schema` is exactly `2`.
- `intent` present and non-empty for every task; `avoid` present as an array of `{rule, why}` with both non-empty.
- `run` strings in `success_criteria` are non-empty; each criterion has `expect_exit` or `expect_output`.
- `depends_on` references (task and phase) point to the same or a prior scope; no dependency cycles.
- Task IDs unique with phase-matching prefixes; phase letters unique and alphabetically ordered.
- No duplicate `create` paths across tasks; no file-set overlap between tasks in the same phase.

### Output format

- **Success:** Exit 0, no output.
- **Failure:** Exit 1, one error per line to stderr: `ERROR: {check_name}: {description}`.

## Status Lifecycle

- **Plan:** `Not Yet Started` → `In Development` → `Complete`. A plan can't be `Complete` while any phase is incomplete or a required review gate is unmet; a phase can't advance while the plan is `Not Yet Started`.
- **Phase:** `Not Started` → `In Progress` → `Complete (YYYY-MM-DD)`. Marking a phase complete requires all its tasks `complete`/`skipped` and a passing `impl-review` record for `phase-{letter}`.
- **Task:** `pending` → `in_progress` → `complete` (or `skipped`). A task can't advance while its parent phase is `Not Started` or any dependency is still `pending`/`in_progress`.

Only `validate-plan` edits `plan.json` — no LLM hand-edits the manifest. Every status change regenerates plan.md, so progress is visible in real time.
