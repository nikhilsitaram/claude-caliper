# Design: Optimize validate-plan Schema Validation Performance

## Problem

`validate-plan --schema` forks ~100 jq subprocesses per invocation. Each field extraction is a separate `echo "$json" | jq -r '.field'` call. With the valid-plan fixture (2 phases, 3 tasks), `do_schema()` alone accounts for ~70 jq forks, and `do_consistency()` (chained from `--schema`) adds ~20 more.

`test_schema.sh` runs 27 tests, each invoking `validate-plan --schema` as a separate subprocess. That's ~2,700 jq forks total, producing a 10.5-second bottleneck (37% of full test suite runtime).

The overhead is process forks, not validation logic. The JSON is already loaded into a bash variable (`json=$(cat "$plan_json")`), but each field access re-pipes it through a new jq process.

## Goal

Reduce jq subprocess forks in `do_schema()` and `do_consistency()` from ~100 to ~5-10 per invocation by batching extractions. Target: `test_schema.sh` under 3 seconds.

## Success Criteria

- `test_schema.sh` completes in under 3 seconds (down from 10.5s)
- All 18 existing test files pass with zero modifications
- No changes to error strings, exit codes, or CLI interface
- `validate-plan --schema` behaves identically for all callers (orchestrate, plan-review, draft-plan, design)

## Architecture

### Batch Extraction Pattern

Replace individual jq field extractions with level-based bulk extractions. Each level gets one jq call that outputs all needed data in a bash-parseable format.

**Level 1 — Top-level scalars (1 jq call, replaces ~10):**
Extract schema, status, goal, architecture, tech_stack, workflow, execution_mode, and integration_branch metadata in a single `@tsv` or JSON output. Bash validates each field with case statements.

**Level 2 — Phase data (1 jq call, replaces ~8 × N_phases):**
One jq call outputs one JSON line per phase containing: letter, name, status, rationale, depends_on array, task count, success_criteria. Bash iterates with `while IFS= read -r phase_json` and extracts fields from the small per-phase JSON.

**Level 3 — Task data (1 jq call, replaces ~15 × N_tasks):**
One jq call outputs one JSON line per task containing: phase letter, id, name, status, verification, done_when, files object, depends_on array, success_criteria. Bash iterates and validates.

**Level 4 — Dependency graph (1 jq call, replaces ~4 × N_phases):**
Extract the full phase dependency adjacency list as a single JSON object. This covers the BFS cycle detection section (lines 426-454) which currently calls jq per BFS node visit and per dependency edge. Bash performs BFS on the extracted graph without further jq calls.

**Orphan file check and fileset overlap** are covered by Level 3 — task IDs and file lists are already extracted. Bash builds associative arrays for duplicate path and orphan detection without additional jq calls. The `tr '[:upper:]' '[:lower:]'` calls for case conversion should also use bash `${var,,}` to eliminate subprocess forks.

### What stays in bash

- File existence checks (`test -f`)
- H1 header matching (`head -n 1`)
- String validation (case statements, regex)
- BFS cycle detection (on pre-extracted adjacency list)
- Error accumulation and reporting

### do_consistency() optimization

Same batching pattern. One jq call extracts all plan/phase/task statuses and dependency completion data. Bash applies the 6 consistency rules on the extracted data. Reduces ~20 jq forks to ~1-2.

## Key Decisions

1. **JSON-per-line for nested data, TSV for flat fields** — TSV is zero-fork parseable with `read`. Nested structures (depends_on arrays, files objects) come as compact JSON per line, with a secondary jq pass on the small entity JSON (fast — tiny input).

2. **No jq inside inner loops where avoidable** — For fields that are simple strings, use TSV extraction so bash `read` handles parsing. Reserve JSON-per-line + jq for structures that need array/object access.

3. **Preserve exact error strings** — All 19 test files assert specific error strings. The refactored code must emit identical messages. Tests are the acceptance gate.

4. **No changes to other functions** — Only `do_schema()` and `do_consistency()` are refactored. `do_criteria`, `do_render`, `do_update_status`, and check functions have few jq calls and are not bottlenecks.

6. **Pass loaded JSON between functions** — `do_schema()` chains to `do_consistency()`, which currently re-reads plan.json from disk. Pass the already-loaded `$json` variable to eliminate redundant file I/O.

5. **No test modifications** — The optimization is internal to validate-plan. If tests need changes, the refactor has a bug.

## Non-Goals

- Rewriting validate-plan in Python or another language
- Adding new validation rules or changing existing ones
- Optimizing test fixture setup (minor gain compared to jq batching)
- Optimizing functions other than do_schema and do_consistency

## Implementation Approach

Single phase, 3 tasks:

1. **Refactor `do_schema()`** — Replace ~70 individual jq calls with 4-5 bulk extractions. Iterate extracted data in bash. Preserve all error strings and validation logic.

2. **Refactor `do_consistency()`** — Replace ~20 individual jq calls with 1-2 bulk extractions. Same pattern as do_schema.

3. **Benchmark and validate** — Run all 18 test files, confirm zero failures. Benchmark `test_schema.sh` and full suite, confirm speedup targets met.
