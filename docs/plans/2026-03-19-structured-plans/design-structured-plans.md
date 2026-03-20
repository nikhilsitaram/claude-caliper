# Design: Structured Plan Files with JSON Manifest

## Goal

Replace monolithic markdown plan files with a split-file structure: a `plan.json` manifest for structured, machine-parseable metadata and per-task `.md` files for implementation prose. Enable programmatic validation of plan structure and real-time status tracking.

## Problem

Plans are currently single `.md` files where all structure (phases, tasks, status) is encoded in markdown conventions. Parsing is entirely LLM-dependent — section extraction, checkbox toggling, handoff note filling, and status updates all rely on text matching. This is fragile: formatting variations cause silent failures, and there's no programmatic way to validate plan structure or track execution progress.

## Architecture

### Directory Structure

```text
docs/plans/YYYY-MM-DD-topic/
├── design-topic.md       # Design doc (unchanged)
├── plan.json             # Structured manifest (source of truth)
├── plan.md               # Human-readable outline (deterministically generated from plan.json)
├── phase-a/
│   ├── completion.md     # Written by dispatcher after phase tasks complete
│   ├── a1.md             # Task prose: Avoid+WHY, Steps
│   └── a2.md             # Task prose: Avoid+WHY, Steps
└── phase-b/
    ├── completion.md     # Stub created by draft-plan
    └── b1.md
```

**File naming convention:** Task files use lowercase task ID (`a1.md` for task `A1`). The dispatcher lowercases the ID when constructing paths: `{PHASE_DIR}/{task_id_lower}.md`.

### plan.json Schema

```json
{
  "schema": 1,
  "status": "Not Yet Started",
  "goal": "One sentence",
  "architecture": "2-3 sentences",
  "tech_stack": "Key technologies",
  "success_criteria": [
    {
      "run": "npm test",
      "expect_exit": 0,
      "timeout": 120,
      "severity": "blocking"
    }
  ],
  "phases": [
    {
      "letter": "A",
      "name": "Core API",
      "status": "Not Started",
      "rationale": "Foundation layer needed before consumers",
      "success_criteria": [
        {
          "run": "pytest tests/integration/ -v",
          "expect_exit": 0
        }
      ],
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
          "done_when": "Handler returns 200, 2/2 tests pass",
          "success_criteria": [
            {
              "run": "npx jest tests/routes.test.ts",
              "expect_exit": 0,
              "expect_output": "2 passed"
            }
          ]
        }
      ]
    }
  ]
}
```

**Field reference:**

- `schema` (integer, required): Schema version for forward compatibility.
- `status` (string, required): `Not Yet Started` | `In Development` | `Complete`.
- `success_criteria` (array, optional): Plan-level criteria. Fields stay in the schema for forward compatibility but are not programmatically enforced yet (see Deferred: Success Criteria Runner).
  - `run` (string, required): Shell command to execute. Must be non-empty.
  - `expect_exit` (integer, optional): Expected exit code.
  - `expect_output` (string, optional): Substring that must appear in stdout.
  - `timeout` (integer, optional): Seconds before timeout. Default 60.
  - `severity` (string, optional): `blocking` (default) | `warning`.
  - At least one of `expect_exit` or `expect_output` is required per criterion. Both may be present (command must satisfy both).
- `phases[].letter` (string, required): Single uppercase letter (A, B, C).
- `phases[].status` (string, required): `Not Started` | `In Progress` | `Complete (YYYY-MM-DD)`.
- `phases[].success_criteria` (array, optional): Phase-level criteria. Same structure as plan-level. Not enforced yet.
- `phases[].tasks[].status` (string, required): `pending` | `in_progress` | `complete` | `skipped`.
- `phases[].tasks[].depends_on` (array of strings): Task IDs this task consumes output from. Must reference same or prior phase only.
- `phases[].tasks[].files` (object, required): `create`, `modify`, `test` — arrays of file paths. File paths must be unique across all tasks in the plan (duplicate creates are a bug).
- `phases[].tasks[].success_criteria` (array, optional): Task-level criteria. Same structure. Not enforced yet.

### plan.md (Human-Readable Outline)

Deterministically generated from `plan.json` by the `validate-plan --render` mode — never edited directly, never LLM-generated. A bash/jq template produces it, ensuring identical output for identical input and clean git diffs (only status changes show up).

The template emits the `> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate` trigger line so Claude invokes the orchestrate skill when asked to execute the plan.

```markdown
# Feature Name Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** One sentence.
**Architecture:** 2-3 sentences.
**Tech Stack:** Key technologies.

---

## Phase A — Core API
**Status:** Not Started | **Rationale:** Foundation layer needed before consumers

- [ ] A1: Setup route handlers — *Handler returns 200, 2/2 tests pass*
- [ ] A2: Auth middleware — *JWT validation rejects expired tokens, 4/4 tests pass*

## Phase B — Consumer Layer
**Status:** Not Started | **Rationale:** Depends on Phase A routes

- [ ] B1: Dashboard page — *Page renders with live data, 3/3 tests pass*
```

This is a read-only artifact. `plan.json` is the source of truth — `plan.md` is derived from it. Checkbox state reflects task `status` in plan.json (`complete` = `[x]`, everything else = `[ ]`).

### Task Files (phase-a/a1.md)

Pure prose — what the implementer reads. The H1 header must match the task ID and name from plan.json (validated by the schema checker).

```markdown
# A1: Setup route handlers

**Avoid:** Don't use express — we're on Hono. Edge runtime compatibility.

## Steps

### Step 1: Write failing test for GET /api/health

(code examples, TDD cycle details)
```

**Handoff notes:** When a task consumes output from a prior phase, the source phase's dispatcher appends a handoff section to the target task file:

```markdown
# B1: Dashboard page

## Handoff from A2

Auth middleware exports `validateToken()` from `src/auth/middleware.ts`. Use it as Hono middleware: `app.use('/dashboard/*', validateToken())`.

**Avoid:** ...

## Steps
...
```

The dispatcher writes to `{PLAN_DIR}/phase-{letter}/{target_task_id_lower}.md`, appending the handoff section after the H1 header and before the existing content.

### Phase Completion Files (phase-a/completion.md)

Stub created by draft-plan (empty file). Written by the dispatcher after all phase tasks complete:

```markdown
# Phase A Completion Notes

**Date:** 2026-03-19
**Summary:** Built core API routes with health check and auth endpoints.
**Deviations:** None — plan followed exactly.
```

Implementation review changes are appended here by the orchestrator.

## Data Flow

### Orchestrator → Dispatcher → Implementer

```text
Orchestrator (main context)
├── Reads: plan.json (full manifest)
├── Per phase:
│   ├── Extracts: {PHASE_TASKS_JSON} — the full tasks array for this phase
│   ├── Passes to dispatcher:
│   │     {PHASE_TASKS_JSON}  — structured task metadata (files, verification, done_when, success_criteria)
│   │     {PLAN_DIR}          — absolute path to plan directory (for cross-phase handoff writes + validate-plan calls)
│   │     {PHASE_DIR}         — absolute path to current phase directory (for reading task .md files)
│   │     {PRIOR_COMPLETIONS} — concatenated completion.md content from prior phases
│   │
│   │   └── Dispatcher (subagent)
│   │       ├── Per task:
│   │       │   ├── Runs: validate-plan --update-status {PLAN_DIR}/plan.json --task A1 --status in_progress
│   │       │   ├── Reads: {PHASE_DIR}/{task_id_lower}.md (prose: Avoid+WHY, Steps)
│   │       │   ├── Extracts: tasks[i] from {PHASE_TASKS_JSON} (metadata: files, verification, done_when)
│   │       │   ├── Passes both to implementer as: {TASK_METADATA} (JSON) + {TASK_PROSE} (markdown)
│   │       │   ├── Writes handoff notes: {PLAN_DIR}/phase-{letter}/{target_task_id_lower}.md (cross-phase)
│   │       │   └── Runs: validate-plan --update-status {PLAN_DIR}/plan.json --task A1 --status complete
│   │       │       (script updates plan.json + regenerates plan.md — real-time visibility)
│   │       └── Writes: {PHASE_DIR}/completion.md
│   │
│   ├── Runs: validate-plan --update-status {PLAN_DIR}/plan.json --phase A --status "Complete (2026-03-19)"
│   ├── Dispatches: implementation-review
│   │     Receives: {PLAN_DIR}/plan.json (structured data) + {PHASE_DIR}/completion.md (prose context)
│   └── Ships: per-phase PR
│
├── After all phases:
│   └── Runs: validate-plan --update-status {PLAN_DIR}/plan.json --plan --status Complete
└── Final task: create GitHub issue for --criteria mode follow-up
```

**Key rules:**
- Only the `validate-plan` script edits plan.json — no LLM hand-edits JSON directly.
- Task statuses update in real time: the dispatcher calls `validate-plan --update-status` before (`in_progress`) and after (`complete`) each task. You see progress as it happens.
- The dispatcher receives `{PLAN_DIR}` so it can call `validate-plan` and write handoff notes into other phases' task files.

### Implementer Prompt Contract

The implementer receives two variables:

- **`{TASK_METADATA}`** — the JSON object for this task from plan.json (id, name, files, verification, done_when, depends_on, success_criteria).
- **`{TASK_PROSE}`** — the full content of the task's `.md` file (Avoid+WHY, Steps, any handoff notes).

The dispatcher assembles these by extracting `tasks[i]` from `{PHASE_TASKS_JSON}` and reading `{PHASE_DIR}/{task_id_lower}.md`.

The spec-reviewer receives the same `{TASK_METADATA}` + `{TASK_PROSE}` pair.

## Validation Hook

A bash script at `scripts/validate-plan`, invoked with absolute path from any working directory. Depends on `jq` (assumed available).

### Modes

| Mode | When | What |
|---|---|---|
| `--schema plan.json` | Pre-orchestration, plan-review | Validate JSON structure, required fields, dependency ordering, valid task IDs, task file existence, H1 header match, non-empty `run` strings, no duplicate file paths across tasks |
| `--update-status plan.json --task A1 --status complete` | After each task completes | Update task status in plan.json + regenerate plan.md |
| `--update-status plan.json --phase A --status "In Progress"` | After phase starts/completes | Update phase status in plan.json + regenerate plan.md |
| `--update-status plan.json --plan --status "In Development"` | Plan lifecycle events | Update plan status in plan.json + regenerate plan.md |
| `--render plan.json` | Standalone rendering (also called internally by `--update-status`) | Deterministically generate plan.md from plan.json |

### Schema Validation Checks (`--schema`)

- All required fields present with correct types
- `run` strings in success_criteria are non-empty
- `depends_on` references point to same or prior phase only
- No duplicate file paths in `create` across tasks
- Task `.md` files exist for every task in plan.json (at `phase-{letter_lower}/{task_id_lower}.md`)
- Task file H1 headers match `# {id}: {name}` from plan.json
- `completion.md` stubs exist for every phase

### Output Format

- **Success:** Exit 0, no output.
- **Failure:** Exit 1, one error per line to stderr: `ERROR: {check_name}: {description}` (e.g., `ERROR: missing_task_file: phase-a/a3.md not found for task A3`).

## Key Decisions

- **JSON over YAML** for the manifest — deterministic parsing, no implicit typing gotchas, better LLM generation reliability at 4 levels of nesting.
- **Split files over monolithic** — natural context isolation (implementer reads only its task file), no section extraction needed, clean separation of machine-readable (JSON) and human-readable (markdown) content.
- **Only `validate-plan` script edits plan.json** — no LLM hand-edits JSON. Dispatchers call the script to update statuses; the script also regenerates plan.md.
- **Real-time status updates** — dispatcher calls `validate-plan --update-status` before and after each task. You see tasks progress as they happen.
- **Success criteria in schema, runner deferred** — `success_criteria` fields are defined in the schema for forward compatibility. The `--criteria` runner mode will be built as a follow-up (tracked via GitHub issue).
- **plan.md is deterministically rendered** — generated by `validate-plan --render`, not by the LLM. Ensures clean diffs and zero formatting drift. Includes the orchestrate skill trigger line.
- **Dispatcher receives {PLAN_DIR}** — enables cross-phase handoff note writes and `validate-plan` calls.
- **Lowercase file naming** — task files use lowercase IDs (`a1.md` for `A1`). Dispatcher lowercases when constructing paths.

## Non-Goals

- Regex support in `expect_output` (substring matching covers 90% of cases).
- Success criteria runner (`--criteria` mode) — deferred to follow-up GitHub issue.
- JSON Schema formal spec (the validation hook enforces structure directly).
- Backward compatibility with old plan format — existing plans are historical artifacts; the one active plan will be migrated manually.

## Affected Skills

| Skill | Change | Magnitude |
|---|---|---|
| **draft-plan** | Generate plan.json + plan.md (via --render) + task files + completion.md stubs in directory structure | Heavy |
| **plan-review** | Run `validate-plan --schema` for structural checks + LLM review for prose quality and "Different Claude Test" | Heavy |
| **orchestrate** | Read plan.json for state; extract {PHASE_TASKS_JSON}; pass to dispatcher with {PLAN_DIR}; update phase/plan statuses via --update-status; regenerate plan.md | Heavy |
| **phase-dispatcher** | Receive {PHASE_TASKS_JSON} + {PLAN_DIR} + {PHASE_DIR}; read task .md files; assemble {TASK_METADATA} + {TASK_PROSE} for implementer; call --update-status for task status; write completion.md and cross-phase handoff notes | Medium |
| **implementer** | Receive {TASK_METADATA} (JSON) + {TASK_PROSE} (markdown) via prompt variables | Light |
| **implementation-review** | Receive {PLAN_DIR}/plan.json path + {PHASE_DIR}/completion.md path; read both for structured data and prose context | Light |
| **spec-reviewer** | Receive {TASK_METADATA} + {TASK_PROSE} from dispatcher (same interface as implementer) | Light |

## Implementation Approach

**Phase A — Validation Script & Schema:** Write `scripts/validate-plan` with `--schema`, `--update-status`, and `--render` modes. Test against a sample plan directory structure.

**Phase B — Skill Integration:** Update draft-plan, orchestrate, phase-dispatcher-prompt, implementer-prompt, plan-review, implementation-review, and spec-reviewer to produce and consume the new split-file format. All changes must be atomic — the pipeline requires all skills to use the same format.

**Final task:** Create a GitHub issue for the `--criteria` mode follow-up (success criteria runner with subprocess timeout management, exit code checking, and output substring matching).

Phase B depends on Phase A (skills invoke the validation hook and follow the schema).
