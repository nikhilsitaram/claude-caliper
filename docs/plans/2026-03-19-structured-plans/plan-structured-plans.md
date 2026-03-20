---
status: Complete
---

# Structured Plan Files Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Replace monolithic markdown plan files with a split-file structure: `plan.json` manifest for structured metadata, per-task `.md` files for implementation prose, and a `validate-plan` script for schema validation, status updates, and deterministic rendering.

**Architecture:** A bash/jq script (`scripts/validate-plan`) provides all programmatic plan operations: schema validation, status updates, and `plan.md` rendering. Skills (draft-plan, orchestrate, phase-dispatcher, implementer, plan-review, implementation-review, spec-reviewer) are updated to produce and consume the new split-file format. The script is the only thing that edits `plan.json` — no LLM hand-edits JSON.

**Tech Stack:** Bash + jq (validation script), Markdown (skill SKILL.md files and prompt templates)

---

## Phase A — Validation Script & Schema
**Status:** Complete (2026-03-19) | **Rationale:** Skills in Phase B invoke the validation script and follow the schema defined here. Must exist before skill integration.

### Phase A Checklist
- [x] A1: Write validate-plan script with --schema mode
- [x] A2: Add --render mode to validate-plan
- [x] A3: Add --update-status mode to validate-plan
- [x] A4: End-to-end validation of all three modes against a sample plan

### Phase A Completion Notes

**Date:** 2026-03-19
**Summary:** Built the `scripts/validate-plan` bash+jq script with three modes: `--schema` (validates plan.json structure, 14 checks), `--render` (deterministically generates `plan.md` from JSON using printf), and `--update-status` (updates task/phase/plan status in plan.json, regenerates plan.md after each write). Created test fixtures (valid-plan with two phases and three tasks), and four test suites totaling 40 passing assertions covering unit and end-to-end lifecycle scenarios.
**Deviations:**
- A1 — added duplicate task ID and phase letter validation (checks 13-14 in test_schema.sh) — Rule 2 (missing validation identified in code review) — duplicate IDs would cause ambiguous dependency resolution.
- A2 — added atomic write to do_render (temp file + mv) — Rule 1 (code doesn't work correctly under failure) — direct redirect would leave partial plan.md on crash.
- A3 — added mktemp/jq/mv error checks to all three do_update_status_* functions and added phase existence check to do_update_status_phase — Rule 1/Rule 2 — silent failures would corrupt plan.json or silently no-op on unknown phase letters.

**Implementation Review Changes:**
- Added uppercase letter format validation (`invalid_phase_letter_format`) to `do_schema` — Rule 2 (missing validation). Phase B skills depend on letter being uppercase A-Z for directory path construction.

### Phase A Tasks

#### A1: Write validate-plan script with --schema mode
**Files:**
- Create: `scripts/validate-plan`
- Create: `tests/validate-plan/fixtures/valid-plan/plan.json`
- Create: `tests/validate-plan/fixtures/valid-plan/phase-a/a1.md`
- Create: `tests/validate-plan/fixtures/valid-plan/phase-a/a2.md`
- Create: `tests/validate-plan/fixtures/valid-plan/phase-a/completion.md`
- Create: `tests/validate-plan/fixtures/valid-plan/phase-b/b1.md`
- Create: `tests/validate-plan/fixtures/valid-plan/phase-b/completion.md`
- Create: `tests/validate-plan/test_schema.sh`

**Verification:** `bash tests/validate-plan/test_schema.sh`

**Done when:** `validate-plan --schema` passes on a valid fixture, fails with specific `ERROR:` messages on each invalid case, and all test assertions pass.

**Avoid:** Don't use Python or Node for the script — the design doc specifies bash + jq, and the script needs to run in any environment without extra dependencies. Don't try to implement `--render` or `--update-status` yet — those are separate tasks.

**Step 1: Create the valid plan.json fixture**

Create `tests/validate-plan/fixtures/valid-plan/plan.json` with a two-phase plan that exercises all schema fields:

```json
{
  "schema": 1,
  "status": "Not Yet Started",
  "goal": "Build a sample feature",
  "architecture": "Two-phase plan for testing validation",
  "tech_stack": "Bash, jq",
  "success_criteria": [
    {
      "run": "echo ok",
      "expect_exit": 0,
      "timeout": 60,
      "severity": "blocking"
    }
  ],
  "phases": [
    {
      "letter": "A",
      "name": "Foundation",
      "status": "Not Started",
      "rationale": "Core layer needed first",
      "success_criteria": [
        {
          "run": "echo phase-a-ok",
          "expect_exit": 0
        }
      ],
      "tasks": [
        {
          "id": "A1",
          "name": "Create core module",
          "status": "pending",
          "depends_on": [],
          "files": {
            "create": ["src/core.ts"],
            "modify": [],
            "test": ["tests/core.test.ts"]
          },
          "verification": "npm test -- tests/core.test.ts",
          "done_when": "Core module exports, 2/2 tests pass",
          "success_criteria": [
            {
              "run": "npm test -- tests/core.test.ts",
              "expect_exit": 0,
              "expect_output": "2 passed"
            }
          ]
        },
        {
          "id": "A2",
          "name": "Add validation layer",
          "status": "pending",
          "depends_on": ["A1"],
          "files": {
            "create": ["src/validate.ts"],
            "modify": [],
            "test": ["tests/validate.test.ts"]
          },
          "verification": "npm test -- tests/validate.test.ts",
          "done_when": "Validation rejects bad input, 3/3 tests pass",
          "success_criteria": []
        }
      ]
    },
    {
      "letter": "B",
      "name": "Consumer",
      "status": "Not Started",
      "rationale": "Depends on Phase A foundation",
      "tasks": [
        {
          "id": "B1",
          "name": "Build dashboard",
          "status": "pending",
          "depends_on": ["A2"],
          "files": {
            "create": ["src/dashboard.ts"],
            "modify": [],
            "test": ["tests/dashboard.test.ts"]
          },
          "verification": "npm test -- tests/dashboard.test.ts",
          "done_when": "Dashboard renders, 2/2 tests pass",
          "success_criteria": []
        }
      ]
    }
  ]
}
```

Create the matching task markdown files:

`tests/validate-plan/fixtures/valid-plan/phase-a/a1.md`:
```markdown
# A1: Create core module

**Avoid:** Don't over-abstract — keep it simple.

## Steps

### Step 1: Write failing test
(test details)
```

`tests/validate-plan/fixtures/valid-plan/phase-a/a2.md`:
```markdown
# A2: Add validation layer

**Avoid:** Don't use regex for validation — use structured checks.

## Steps

### Step 1: Write failing test
(test details)
```

`tests/validate-plan/fixtures/valid-plan/phase-b/b1.md`:
```markdown
# B1: Build dashboard

## Handoff from A2

Validation module exports `validate()` from `src/validate.ts`.

**Avoid:** Don't render without validating input first.

## Steps

### Step 1: Write failing test
(test details)
```

Create empty `completion.md` stubs:
- `tests/validate-plan/fixtures/valid-plan/phase-a/completion.md` (empty file)
- `tests/validate-plan/fixtures/valid-plan/phase-b/completion.md` (empty file)

**Step 2: Write the validate-plan script skeleton**

Create `scripts/validate-plan` as a bash script. Start with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Structured plan validation, status updates, and rendering.
# Depends on jq (assumed available).

usage() {
  cat <<'USAGE'
Usage:
  validate-plan --schema <plan.json>
  validate-plan --render <plan.json>
  validate-plan --update-status <plan.json> --task <ID> --status <STATUS>
  validate-plan --update-status <plan.json> --phase <LETTER> --status <STATUS>
  validate-plan --update-status <plan.json> --plan --status <STATUS>
USAGE
  exit 1
}

ERRORS=()
err() { ERRORS+=("ERROR: $1: $2"); }

MODE=""
PLAN_JSON=""
# Parse args...

case "$MODE" in
  schema) do_schema ;;
  render) echo "Not implemented yet" ; exit 1 ;;
  update-status) echo "Not implemented yet" ; exit 1 ;;
  *) usage ;;
esac
```

Make it executable: `chmod +x scripts/validate-plan`.

**Step 3: Implement --schema validation checks**

The `do_schema` function validates the following (design doc section "Schema Validation Checks"):

1. **Required fields with correct types** — `schema` (integer), `status` (string, one of: `Not Yet Started`, `In Development`, `Complete`), `goal` (string), `architecture` (string), `tech_stack` (string). Each phase: `letter` (single uppercase A-Z), `name`, `status` (one of: `Not Started`, `In Progress`, or matching `Complete (YYYY-MM-DD)` pattern), `rationale`. Each task: `id`, `name`, `status` (one of: pending, in_progress, complete, skipped), `depends_on` (array), `files` (object with create/modify/test arrays), `verification`, `done_when`.

2. **Non-empty `run` strings in success_criteria** — at all three levels (plan, phase, task). Each criterion must have at least one of `expect_exit` or `expect_output`.

3. **`depends_on` references valid task IDs in same or prior phase** — B1 can depend on A1 or A2, but A1 cannot depend on B1.

4. **No duplicate file paths in `create` across tasks** — collect all `create` paths, check uniqueness.

5. **Task `.md` files exist** — for task A1, check `phase-a/a1.md` exists relative to plan.json's directory.

6. **Task file H1 headers match** — first line of `phase-a/a1.md` must be `# A1: Create core module` (matching id + name from plan.json).

7. **`completion.md` stubs exist** — `phase-a/completion.md`, `phase-b/completion.md`, etc.

Derive `PLAN_DIR` from `plan.json`'s directory path. Use `jq` for all JSON parsing. Iterate phases and tasks with `jq -c '.phases[]'` and nested task iteration.

At the end of `do_schema`:
```bash
if [ ${#ERRORS[@]} -gt 0 ]; then
  for e in "${ERRORS[@]}"; do echo "$e" >&2; done
  exit 1
fi
exit 0
```

**Step 4: Write test_schema.sh**

Create `tests/validate-plan/test_schema.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_pass() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    ((FAIL++))
  fi
}

assert_fail() {
  local desc="$1"; shift
  local expected_error="$1"; shift
  local output
  if output=$("$@" 2>&1); then
    echo "FAIL: $desc (expected failure, got success)"
    ((FAIL++))
  elif echo "$output" | grep -q "$expected_error"; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc (expected '$expected_error' in output, got: $output)"
    ((FAIL++))
  fi
}

# Test 1: Valid plan passes
assert_pass "valid plan passes schema check" \
  "$VALIDATE" --schema "$FIXTURES/valid-plan/plan.json"

# Test 2: Missing required field (remove goal)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq 'del(.goal)' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "missing goal field" "missing_field" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 3: depends_on references future phase
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].tasks[0].depends_on = ["B1"]' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "depends_on references future phase" "invalid_dependency" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 4: Duplicate create paths
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[1].tasks[0].files.create = ["src/core.ts"]' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "duplicate create path" "duplicate_create_path" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 5: Missing task file
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
rm "$TMPDIR/phase-a/a1.md"
assert_fail "missing task file" "missing_task_file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 6: H1 header mismatch
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
echo "# A1: Wrong Name" > "$TMPDIR/phase-a/a1.md"
assert_fail "H1 header mismatch" "h1_mismatch" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 7: Missing completion.md
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
rm "$TMPDIR/phase-a/completion.md"
assert_fail "missing completion.md" "missing_completion_file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 8: Invalid task status
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].tasks[0].status = "invalid"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "invalid task status" "invalid_task_status" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 9: Empty run string in success_criteria
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.success_criteria[0].run = ""' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "empty run string" "empty_run" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 10: success_criteria missing both expect_exit and expect_output
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.success_criteria = [{"run": "echo ok"}]' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "criteria missing expect" "missing_expect" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 11: Invalid plan status
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.status = "bogus"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "invalid plan status" "invalid_plan_status" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Test 12: Invalid phase status
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].status = "bogus"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "invalid phase status" "invalid_phase_status" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**Step 5: Run tests and iterate**

Run `bash tests/validate-plan/test_schema.sh`. Fix any failures. The script should pass all 12 assertions (1 valid + 11 error cases).

Commit: "feat: add validate-plan script with --schema mode"

---

#### A2: Add --render mode to validate-plan
**Files:**
- Modify: `scripts/validate-plan`
- Create: `tests/validate-plan/test_render.sh`
- Create: `tests/validate-plan/fixtures/valid-plan/plan.md` (expected output)

**Verification:** `bash tests/validate-plan/test_render.sh`

**Done when:** `validate-plan --render plan.json` deterministically generates `plan.md` from plan.json, matching the expected output byte-for-byte. Running render twice produces identical output.

**Avoid:** Don't use `echo -e` for rendering — portable bash + `printf` is more reliable. Don't include any LLM-generated content in the rendered output — the render must be fully deterministic from JSON fields only.

**Step 1: Create expected plan.md output**

Create `tests/validate-plan/fixtures/valid-plan/plan.md` with the exact expected output for the valid fixture's plan.json. The format follows the design doc's "plan.md (Human-Readable Outline)" section:

```markdown
# Build a sample feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Build a sample feature
**Architecture:** Two-phase plan for testing validation
**Tech Stack:** Bash, jq

---

## Phase A — Foundation
**Status:** Not Started | **Rationale:** Core layer needed first

- [ ] A1: Create core module — *Core module exports, 2/2 tests pass*
- [ ] A2: Add validation layer — *Validation rejects bad input, 3/3 tests pass*

## Phase B — Consumer
**Status:** Not Started | **Rationale:** Depends on Phase A foundation

- [ ] B1: Build dashboard — *Dashboard renders, 2/2 tests pass*
```

Note: checklist items use `[ ]` for all non-complete statuses, `[x]` for `complete`. The `done_when` appears italicized after the task name.

**Step 2: Implement do_render function**

In `scripts/validate-plan`, implement the `--render` mode. The function:

1. Reads plan.json with jq
2. Derives `PLAN_DIR` from plan.json path
3. Writes `plan.md` to `$PLAN_DIR/plan.md`
4. Uses only `printf` and heredocs for output — no LLM-dependent content

Template logic:
```bash
do_render() {
  local plan_json="$1"
  local plan_dir
  plan_dir="$(dirname "$(realpath "$plan_json")")"
  local out="$plan_dir/plan.md"

  local goal architecture tech_stack
  goal=$(jq -r '.goal' "$plan_json")
  architecture=$(jq -r '.architecture' "$plan_json")
  tech_stack=$(jq -r '.tech_stack' "$plan_json")

  {
    printf '# %s Implementation Plan\n\n' "$goal"
    printf '> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate\n\n'
    printf '**Goal:** %s\n' "$goal"
    printf '**Architecture:** %s\n' "$architecture"
    printf '**Tech Stack:** %s\n' "$tech_stack"
    printf '\n---\n'

    local phase_count
    phase_count=$(jq '.phases | length' "$plan_json")

    for ((i=0; i<phase_count; i++)); do
      local letter name status rationale
      letter=$(jq -r ".phases[$i].letter" "$plan_json")
      name=$(jq -r ".phases[$i].name" "$plan_json")
      status=$(jq -r ".phases[$i].status" "$plan_json")
      rationale=$(jq -r ".phases[$i].rationale" "$plan_json")

      printf '\n## Phase %s — %s\n' "$letter" "$name"
      printf '**Status:** %s | **Rationale:** %s\n\n' "$status" "$rationale"

      local task_count
      task_count=$(jq ".phases[$i].tasks | length" "$plan_json")

      for ((j=0; j<task_count; j++)); do
        local tid tname tstatus done_when checkbox
        tid=$(jq -r ".phases[$i].tasks[$j].id" "$plan_json")
        tname=$(jq -r ".phases[$i].tasks[$j].name" "$plan_json")
        tstatus=$(jq -r ".phases[$i].tasks[$j].status" "$plan_json")
        done_when=$(jq -r ".phases[$i].tasks[$j].done_when" "$plan_json")

        if [ "$tstatus" = "complete" ]; then
          checkbox="[x]"
        else
          checkbox="[ ]"
        fi

        printf -- '- %s %s: %s — *%s*\n' "$checkbox" "$tid" "$tname" "$done_when"
      done
    done
  } > "$out"
}
```

**Step 3: Write test_render.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_pass() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    ((FAIL++))
  fi
}

# Test 1: Render produces expected plan.md
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
rm -f "$TMPDIR/plan.md"
"$VALIDATE" --render "$TMPDIR/plan.json"
if diff -u "$FIXTURES/valid-plan/plan.md" "$TMPDIR/plan.md"; then
  echo "PASS: render matches expected output"
  ((PASS++))
else
  echo "FAIL: render does not match expected output"
  ((FAIL++))
fi

# Test 2: Idempotent — running render twice produces identical output
"$VALIDATE" --render "$TMPDIR/plan.json"
if diff -u "$FIXTURES/valid-plan/plan.md" "$TMPDIR/plan.md"; then
  echo "PASS: render is idempotent"
  ((PASS++))
else
  echo "FAIL: render is not idempotent"
  ((FAIL++))
fi

# Test 3: Completed tasks render with [x]
jq '.phases[0].tasks[0].status = "complete"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
"$VALIDATE" --render "$TMPDIR/plan.json"
if grep -q '\[x\] A1' "$TMPDIR/plan.md"; then
  echo "PASS: completed task renders with [x]"
  ((PASS++))
else
  echo "FAIL: completed task does not render with [x]"
  ((FAIL++))
fi

# Test 4: Non-complete statuses render with [ ]
if grep -q '\[ \] A2' "$TMPDIR/plan.md"; then
  echo "PASS: pending task renders with [ ]"
  ((PASS++))
else
  echo "FAIL: pending task does not render with [ ]"
  ((FAIL++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**Step 4: Run tests and iterate**

Run `bash tests/validate-plan/test_render.sh`. The expected output file may need minor whitespace adjustments — match the exact output the script produces. Verify idempotency.

Commit: "feat: add --render mode to validate-plan"

---

#### A3: Add --update-status mode to validate-plan
**Files:**
- Modify: `scripts/validate-plan`
- Create: `tests/validate-plan/test_update_status.sh`

**Verification:** `bash tests/validate-plan/test_update_status.sh`

**Done when:** `--update-status` correctly updates task, phase, and plan statuses in plan.json, regenerates plan.md after each update, and all test assertions pass.

**Avoid:** Don't use `sed` to edit JSON — always use `jq`. The `sponge` command from moreutils is not universally available — write to a temp file then `mv` it to plan.json.

**Step 1: Implement --update-status for tasks**

In `scripts/validate-plan`, implement the `--update-status` mode. Parse the additional args:
- `--task <ID> --status <STATUS>` — update a specific task
- `--phase <LETTER> --status <STATUS>` — update a specific phase
- `--plan --status <STATUS>` — update the plan-level status

For task updates:
```bash
do_update_status_task() {
  local plan_json="$1" task_id="$2" new_status="$3"
  local valid_statuses=("pending" "in_progress" "complete" "skipped")
  # Validate new_status is in valid_statuses
  # Find the task by id in plan.json, update its status
  local tmp
  tmp=$(mktemp)
  jq --arg id "$task_id" --arg status "$new_status" '
    (.phases[].tasks[] | select(.id == $id)).status = $status
  ' "$plan_json" > "$tmp"
  mv "$tmp" "$plan_json"
  # Regenerate plan.md
  do_render "$plan_json"
}
```

**Step 2: Implement --update-status for phases**

For phase updates:
```bash
do_update_status_phase() {
  local plan_json="$1" phase_letter="$2" new_status="$3"
  # Validate: "Not Started", "In Progress", or "Complete (YYYY-MM-DD)"
  if [[ "$new_status" != "Not Started" && "$new_status" != "In Progress" && ! "$new_status" =~ ^Complete\ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$ ]]; then
    echo "ERROR: invalid_phase_status: '$new_status' (expected 'Not Started', 'In Progress', or 'Complete (YYYY-MM-DD)')" >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg letter "$phase_letter" --arg status "$new_status" '
    (.phases[] | select(.letter == $letter)).status = $status
  ' "$plan_json" > "$tmp"
  mv "$tmp" "$plan_json"
  do_render "$plan_json"
}
```

**Step 3: Implement --update-status for plan**

For plan updates:
```bash
do_update_status_plan() {
  local plan_json="$1" new_status="$2"
  local valid_plan_statuses=("Not Yet Started" "In Development" "Complete")
  local valid=false
  for s in "${valid_plan_statuses[@]}"; do
    if [ "$new_status" = "$s" ]; then valid=true; break; fi
  done
  if [ "$valid" = false ]; then
    echo "ERROR: invalid_plan_status: '$new_status' (expected 'Not Yet Started', 'In Development', or 'Complete')" >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg status "$new_status" '.status = $status' "$plan_json" > "$tmp"
  mv "$tmp" "$plan_json"
  do_render "$plan_json"
}
```

**Step 4: Wire up argument parsing**

Update the argument parser to handle the `--update-status` mode with its sub-flags (`--task`, `--phase`, `--plan`, `--status`). Route to the appropriate function.

**Step 5: Write test_update_status.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    ((FAIL++))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Fresh copy for each test group
reset_fixture() {
  rm -rf "$TMPDIR/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
}

# Test 1: Update task status
reset_fixture
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status in_progress
actual=$(jq -r '.phases[0].tasks[0].status' "$TMPDIR/plan.json")
assert_eq "task status updated to in_progress" "in_progress" "$actual"

# Test 2: Task status update regenerates plan.md
if grep -q '\[ \] A1' "$TMPDIR/plan.md"; then
  echo "PASS: in_progress task renders as [ ]"
  ((PASS++))
else
  echo "FAIL: in_progress task should render as [ ]"
  ((FAIL++))
fi

# Test 3: Complete task shows [x] in plan.md
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status complete
if grep -q '\[x\] A1' "$TMPDIR/plan.md"; then
  echo "PASS: complete task renders as [x]"
  ((PASS++))
else
  echo "FAIL: complete task should render as [x]"
  ((FAIL++))
fi

# Test 4: Update phase status
reset_fixture
"$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "In Progress"
actual=$(jq -r '.phases[0].status' "$TMPDIR/plan.json")
assert_eq "phase status updated" "In Progress" "$actual"

# Test 5: Phase status appears in plan.md
if grep -q 'In Progress' "$TMPDIR/plan.md"; then
  echo "PASS: phase status in plan.md"
  ((PASS++))
else
  echo "FAIL: phase status not in plan.md"
  ((FAIL++))
fi

# Test 6: Update plan status
reset_fixture
"$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "In Development"
actual=$(jq -r '.status' "$TMPDIR/plan.json")
assert_eq "plan status updated" "In Development" "$actual"

# Test 7: Invalid task ID fails
reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --task Z99 --status complete 2>/dev/null; then
  echo "FAIL: invalid task ID should fail"
  ((FAIL++))
else
  echo "PASS: invalid task ID rejected"
  ((PASS++))
fi

# Test 8: Invalid task status fails
reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status bogus 2>/dev/null; then
  echo "FAIL: invalid task status should fail"
  ((FAIL++))
else
  echo "PASS: invalid task status rejected"
  ((PASS++))
fi

# Test 9: Invalid phase status fails
reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "bogus" 2>/dev/null; then
  echo "FAIL: invalid phase status should fail"
  ((FAIL++))
else
  echo "PASS: invalid phase status rejected"
  ((PASS++))
fi

# Test 10: Invalid plan status fails
reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "bogus" 2>/dev/null; then
  echo "FAIL: invalid plan status should fail"
  ((FAIL++))
else
  echo "PASS: invalid plan status rejected"
  ((PASS++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**Step 6: Run tests and iterate**

Run `bash tests/validate-plan/test_update_status.sh`. Fix failures until all 10 assertions pass.

Commit: "feat: add --update-status mode to validate-plan"

---

#### A4: End-to-end validation of all three modes against a sample plan
**Files:**
- Create: `tests/validate-plan/test_e2e.sh`

**Verification:** `bash tests/validate-plan/test_e2e.sh`

**Done when:** A full lifecycle test passes: schema validates, render produces plan.md, status updates flow through correctly, schema re-validates after updates, and plan.md reflects final state.

**Avoid:** Don't duplicate fixture setup from earlier tests — reuse the valid-plan fixture. Don't test edge cases already covered in test_schema.sh / test_render.sh / test_update_status.sh — this test verifies mode interactions.

**Step 1: Write test_e2e.sh**

This test exercises a realistic plan lifecycle: validate → update statuses as tasks progress → re-validate → render final state.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc"
    ((FAIL++))
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    ((PASS++))
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    ((FAIL++))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"

# Step 1: Schema validates clean
check "initial schema validation" "$VALIDATE" --schema "$TMPDIR/plan.json"

# Step 2: Render initial plan.md
rm -f "$TMPDIR/plan.md"
check "initial render" "$VALIDATE" --render "$TMPDIR/plan.json"
check "plan.md exists after render" test -f "$TMPDIR/plan.md"

# Step 3: Start plan
"$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "In Development"
assert_eq "plan status" "In Development" "$(jq -r '.status' "$TMPDIR/plan.json")"

# Step 4: Start Phase A
"$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "In Progress"

# Step 5: Work through tasks
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status in_progress
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status complete
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status in_progress
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status complete

# Step 6: Complete Phase A
"$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-19)"

# Step 7: Verify intermediate state
assert_eq "A1 complete" "complete" "$(jq -r '.phases[0].tasks[0].status' "$TMPDIR/plan.json")"
assert_eq "A2 complete" "complete" "$(jq -r '.phases[0].tasks[1].status' "$TMPDIR/plan.json")"
check "plan.md has [x] A1" grep -q '\[x\] A1' "$TMPDIR/plan.md"
check "plan.md has [x] A2" grep -q '\[x\] A2' "$TMPDIR/plan.md"
check "plan.md has Complete" grep -q 'Complete (2026-03-19)' "$TMPDIR/plan.md"

# Step 8: Schema still validates after all updates
check "schema validates after updates" "$VALIDATE" --schema "$TMPDIR/plan.json"

# Step 9: Render is still idempotent
cp "$TMPDIR/plan.md" "$TMPDIR/plan-before.md"
"$VALIDATE" --render "$TMPDIR/plan.json"
check "render idempotent after updates" diff -q "$TMPDIR/plan-before.md" "$TMPDIR/plan.md"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**Step 2: Run and verify**

Run `bash tests/validate-plan/test_e2e.sh`. All assertions should pass. If any mode interactions cause issues (e.g., render after update produces unexpected output), fix in the script.

Commit: "test: add end-to-end lifecycle test for validate-plan"

---

## Phase B — Skill Integration
**Status:** Complete (2026-03-19) | **Rationale:** All skills invoke validate-plan (Phase A) and must adopt the split-file format atomically — the pipeline requires all skills to use the same format.

### Phase B Checklist
- [x] B1: Rewrite draft-plan SKILL.md for structured output
- [x] B2: Rewrite plan-review SKILL.md and reviewer-prompt.md
- [x] B3: Rewrite orchestrate SKILL.md for plan.json consumption
- [x] B4: Rewrite phase-dispatcher-prompt.md for structured task dispatch
- [x] B5: Rewrite implementer-prompt.md and spec-reviewer-prompt.md
- [x] B6: Update implementation-review SKILL.md and reviewer-prompt.md
- [x] B7: Bump plugin version in marketplace.json
- [x] B8: Create GitHub issue for --criteria mode follow-up

### Phase B Completion Notes

**Date:** 2026-03-20
**Summary:** Rewrote all six skill files and prompt templates to produce and consume the new structured plan format (plan.json + split task files). draft-plan now generates the split-file directory structure and calls validate-plan; plan-review adds two-stage validation; orchestrate reads plan.json via jq and calls validate-plan for all status updates; phase-dispatcher receives {PHASE_TASKS_JSON} and dispatches {TASK_METADATA} + {TASK_PROSE} to implementers; implementation-review reads {PLAN_DIR}/plan.json and {PHASE_DIR}/completion.md. Also bumped plugin version to 1.2.0 and created GitHub issue #80 for --criteria runner follow-up.
**Deviations:**
- B2 — fixed 6-point checklist numbering (was out of sequence: 1, 5, then 2-4, 6) — Rule 1 (content didn't work as intended) — out-of-order numbering created reader confusion about the 6-point structure.
- B3 — added CROSS_PHASE_HANDOFF_TARGETS format spec, PLAN_DIR derivation, and PRIOR_COMPLETIONS concatenation method — Rule 2 (missing critical implementation guidance) — orchestrator would stall building these variables without concrete examples.
- B4 — clarified TASK_ID substitution, integration test terminology, and within-phase handoff format — Rule 1 (content didn't work as intended) — implicit substitution and vague "similarly" reference would cause dispatcher to guess.
- B5 — fixed field name (verification not verification_command) and added variable descriptions to spec-reviewer — Rule 1 (incorrect field name, missing context) — field mismatch and missing descriptions caused inconsistency between implementer and reviewer prompts.

**Implementation Review Changes:**
- Fixed success_criteria listed as required in plan-review SKILL.md and reviewer-prompt.md (it's optional).
- Standardized all script invocation paths to `scripts/validate-plan` in orchestrate SKILL.md and draft-plan SKILL.md (bare `validate-plan` would fail with "command not found").
- Added success_criteria optional field note to draft-plan SKILL.md.

### Phase B Tasks

#### B1: Rewrite draft-plan SKILL.md for structured output

> **Handoff from A4:** validate-plan script is at `scripts/validate-plan` (executable bash+jq, no other deps). Commands: `scripts/validate-plan --schema <plan-dir>/plan.json` (exits 0 on success, prints `ERROR: <keyword>: <details>` lines to stderr on failure) and `scripts/validate-plan --render <plan-dir>/plan.json` (writes `plan.md` to the same directory as `plan.json`). The plan.json schema uses `schema: 1` at root; required top-level fields: `schema` (int), `status` (one of: "Not Yet Started", "In Development", "Complete"), `goal`, `architecture`, `tech_stack`, `phases[]`. Each phase requires: `letter` (single uppercase letter), `name`, `status` (one of: "Not Started", "In Progress", "Complete (YYYY-MM-DD)"), `rationale`, `tasks[]`. Each task requires: `id`, `name`, `status` (one of: pending, in_progress, complete, skipped), `depends_on` (array), `files` (object with `create`/`modify`/`test` arrays), `verification`, `done_when`. Optional `success_criteria` array at plan/phase/task level (each criterion: `run` (non-empty string), at least one of `expect_exit` or `expect_output`, optional `timeout` and `severity`). Task `.md` files live at `phase-{letter-lower}/{task-id-lower}.md` relative to `plan.json`; first line must be `# {id}: {name}`. Each phase needs a `phase-{letter-lower}/completion.md` stub.

**Files:**
- Modify: `skills/draft-plan/SKILL.md`

**Verification:** Read `skills/draft-plan/SKILL.md`, confirm it describes the new split-file output format, word count under 1,000.

**Done when:** The draft-plan SKILL.md instructs the planner to generate: plan.json (following the schema), per-task `.md` files in `phase-{letter}/` directories, `completion.md` stubs, and calls `validate-plan --schema` + `validate-plan --render` to validate and generate plan.md. The old monolithic plan format is fully replaced.

**Avoid:** Don't embed the full plan.json schema in SKILL.md — it would blow past the 1,000-word cap. Instead, reference the design doc or a schema example. Don't use `@filename` references (force-loads into context).

**Step 1: Read the current draft-plan SKILL.md**

Read `skills/draft-plan/SKILL.md` to understand the current structure. The file currently describes monolithic plan output with frontmatter, phases, checklists, completion notes, and task blocks all in a single `.md` file.

**Step 2: Redesign the workflow section**

Update the workflow to produce the new directory structure:

```text
docs/plans/YYYY-MM-DD-<topic>/
├── plan.json
├── plan.md               (generated by validate-plan --render)
├── phase-a/
│   ├── completion.md     (empty stub)
│   ├── a1.md
│   └── a2.md
└── phase-b/
    ├── completion.md     (empty stub)
    └── b1.md
```

The workflow steps become:
1. Initialize tracking (unchanged)
2. Explore codebase (unchanged)
3. Decide phasing (unchanged)
4. Write plan.json — the structured manifest with all metadata
5. Write task `.md` files — prose for each task (Avoid+WHY, Steps)
6. Create `completion.md` stubs — empty files, one per phase
7. Run `validate-plan --schema` — fix any errors
8. Run `validate-plan --render` — generates plan.md deterministically
9. Run plan review — dispatch reviewer
10. Hand off to execution

**Step 3: Replace the Plan Document Structure section**

Remove the old monolithic markdown template. Replace with:

**plan.json structure** — describe the schema with a concise example (not the full field reference — too many tokens). Key fields: `schema`, `status`, `goal`, `architecture`, `tech_stack`, `phases[]` with `letter`, `name`, `status`, `rationale`, `tasks[]` with `id`, `name`, `status`, `depends_on`, `files` (create/modify/test), `verification`, `done_when`. Optional: `success_criteria` at all three levels.

**Task file structure** — H1 must match `# {id}: {name}`. Content: `**Avoid:**` section, `## Steps` with TDD steps. Handoff notes go after H1, before Avoid.

**Step 4: Update the Task Structure section**

Keep all 5 required fields (Files, Verification, Done when, Avoid+WHY, Steps). Clarify that Files, Verification, and Done when go in plan.json, while Avoid+WHY and Steps go in the task `.md` file.

Split:
- **plan.json fields:** `id`, `name`, `status`, `depends_on`, `files`, `verification`, `done_when`, `success_criteria`
- **Task .md file content:** Avoid+WHY, Steps (with full code), handoff notes from prior phases

**Step 5: Update the Phasing section**

Minimal changes — replace any references to the old format with the new one. Phase boundaries, complexity gates, and design doc inheritance guidance stay the same.

**Step 6: Update the Plan Review Gate section**

Update to mention `validate-plan --schema` runs as a pre-check (structural validation) before dispatching the LLM reviewer (prose quality + Different Claude Test).

**Step 7: Verify word count**

Count words: `wc -w skills/draft-plan/SKILL.md`. Must be under 1,000. Trim aggressively — the planner model already knows TDD, markdown formatting, and general software practices.

Commit: "refactor: rewrite draft-plan SKILL.md for structured plan output"

---

#### B2: Rewrite plan-review SKILL.md and reviewer-prompt.md

> **Handoff from A4:** `scripts/validate-plan --schema <plan-dir>/plan.json` exits 0 on success; on failure exits 1 and prints one or more `ERROR: <keyword>: <details>` lines to stderr. Keywords include: `missing_field`, `invalid_plan_status`, `invalid_phase_status`, `invalid_task_status`, `invalid_dependency`, `duplicate_create_path`, `duplicate_task_id`, `duplicate_phase_letter`, `missing_task_file`, `h1_mismatch`, `missing_completion_file`, `empty_run`, `missing_expect`. Script path: `scripts/validate-plan` at repo root.

**Files:**
- Modify: `skills/plan-review/SKILL.md`
- Modify: `skills/plan-review/reviewer-prompt.md`

**Verification:** Read both files, confirm they reference the new plan.json + task files structure, word count of SKILL.md under 1,000.

**Done when:** plan-review runs `validate-plan --schema` for structural checks (fields, dependencies, file existence) and dispatches the LLM reviewer only for prose quality, Different Claude Test, and design doc alignment. The reviewer-prompt.md references plan.json + task files instead of the monolithic plan.

**Avoid:** Don't duplicate checks that `validate-plan --schema` already handles (missing fields, dependency ordering, file existence, H1 matching). The LLM reviewer should focus on what programmatic checks cannot: prose quality, design alignment, and Fresh Claude Test assessment.

**Step 1: Read the current files**

Read `skills/plan-review/SKILL.md` and `skills/plan-review/reviewer-prompt.md`.

**Step 2: Update SKILL.md**

Add a two-stage review:

1. **Structural validation** — run `validate-plan --schema {PLAN_DIR}/plan.json`. If errors, report them and stop (no point dispatching LLM reviewer for structurally invalid plans).
2. **Prose + design review** — dispatch LLM reviewer subagent with updated prompt.

Update the "What It Catches" table: move structural checks (missing fields, dependency ordering, artifact consistency, file existence) to "handled by validate-plan --schema". Keep prose quality, design alignment, and Different Claude Test as LLM reviewer concerns.

Update inputs section:
- **Plan directory** — `docs/plans/YYYY-MM-DD-topic/` (contains plan.json + task files)
- **Design doc** — if one exists
- **Repo root** — the worktree

**Step 3: Update reviewer-prompt.md**

The reviewer now receives `{PLAN_DIR}` instead of `{PLAN_PATH}`. It reads:
- `{PLAN_DIR}/plan.json` for structured metadata
- `{PLAN_DIR}/phase-{letter}/{task_id_lower}.md` for task prose

Update the 6-Point Checklist:
1. **Dependency Ordering** — now validated by `validate-plan --schema`. Reviewer skips. Note: "Structural validation already verified."
2. **Artifact Consistency** — partially validated by schema (H1 headers). Reviewer checks cross-task name consistency within prose.
3. **Design Doc Alignment** — unchanged (LLM-only check).
4. **Test-Implementation Coherence** — unchanged (needs prose understanding).
5. **Completeness** — structural fields validated by schema. Reviewer checks: are steps detailed enough? Is code complete? Do avoid sections have reasoning?
6. **Different Claude Test** — unchanged (LLM-only check).

Update the Phase Checks section similarly — schema handles structural checks, reviewer focuses on quality.

**Step 4: Update reviewer output format**

Same output structure (Issues Found + Assessment), but the assessment table notes which checks were handled by schema validation vs LLM review.

Commit: "refactor: rewrite plan-review for structured plan format"

---

#### B3: Rewrite orchestrate SKILL.md for plan.json consumption

> **Handoff from A4:** `scripts/validate-plan --update-status <plan.json> --task <ID> --status <STATUS>` (valid task statuses: pending, in_progress, complete, skipped; fails with `ERROR: task_not_found` if ID unknown, `ERROR: invalid_task_status` if status unknown). `scripts/validate-plan --update-status <plan.json> --phase <LETTER> --status <STATUS>` (valid: "Not Started", "In Progress", "Complete (YYYY-MM-DD)"; fails with `ERROR: phase_not_found` or `ERROR: invalid_phase_status`). `scripts/validate-plan --update-status <plan.json> --plan --status <STATUS>` (valid: "Not Yet Started", "In Development", "Complete"; fails with `ERROR: invalid_plan_status`). All three modes automatically regenerate `plan.md` (via `--render`) after a successful update. Script path: `scripts/validate-plan` at repo root.

**Files:**
- Modify: `skills/orchestrate/SKILL.md`

**Verification:** Read `skills/orchestrate/SKILL.md`, confirm it describes reading plan.json for state, passing `{PHASE_TASKS_JSON}` to dispatcher, calling `validate-plan --update-status` for phase/plan status, word count under 1,000.

**Done when:** The orchestrate SKILL.md instructs the orchestrator to: read plan.json for plan state and phase iteration, extract `{PHASE_TASKS_JSON}` per phase for the dispatcher, pass `{PLAN_DIR}` and `{PHASE_DIR}` to the dispatcher, call `validate-plan --update-status` for phase and plan status updates, and read completion.md files for prior phase context. The old markdown parsing approach is fully replaced.

**Avoid:** Don't describe the validate-plan script internals — orchestrate just calls it. Don't increase word count above 1,000 — the orchestrator model knows how to read JSON and call scripts.

**Step 1: Read the current orchestrate SKILL.md**

Read `skills/orchestrate/SKILL.md` to understand the current structure.

**Step 2: Update the Per-Phase Execution section**

Replace markdown-based plan reading with plan.json reading:

For each phase:
1. `PHASE_BASE_SHA=$(git rev-parse HEAD)`
2. Create phase branch (unchanged)
3. Extract context for dispatcher:
   - `PHASE_TASKS_JSON` — `jq '.phases[N].tasks' plan.json` (the full tasks array for this phase)
   - `PLAN_DIR` — absolute path to plan directory
   - `PHASE_DIR` — `$PLAN_DIR/phase-{letter_lower}`
   - `PRIOR_COMPLETIONS` — concatenate `phase-{letter_lower}/completion.md` from all prior phases
4. Build `{CROSS_PHASE_HANDOFF_TARGETS}` — scan later phases' tasks for `depends_on` entries referencing tasks in the current phase, map source task IDs to target file paths
5. Dispatch phase dispatcher with: `{PHASE_TASKS_JSON}`, `{PLAN_DIR}`, `{PHASE_DIR}`, `{PRIOR_COMPLETIONS}`, `{CROSS_PHASE_HANDOFF_TARGETS}`
5. After dispatcher returns — same flow (implementation-review, triage, etc.)
6. Call `validate-plan --update-status plan.json --phase {LETTER} --status "Complete (YYYY-MM-DD)"`
7. Ship phase PR

After all phases:
- `validate-plan --update-status plan.json --plan --status Complete`
- Create GitHub issue for `--criteria` mode follow-up

**Step 3: Update the Plan Doc Updates table**

Replace markdown-edit actions with validate-plan calls:

| When | Update |
|------|--------|
| First task starts | `validate-plan --update-status plan.json --plan --status "In Development"` |
| Task completes | Dispatcher calls `validate-plan --update-status ... --task {ID} --status complete` |
| Phase dispatcher returns | Dispatcher writes `phase-{letter}/completion.md` |
| Review fixes applied | Orchestrator appends to `phase-{letter}/completion.md` |
| Phase review passes | `validate-plan --update-status plan.json --phase {LETTER} --status "Complete (YYYY-MM-DD)"` |
| All phases done | `validate-plan --update-status plan.json --plan --status Complete` |

**Step 4: Update the Example Workflow**

Replace the markdown-centric example with one showing plan.json reading and validate-plan calls.

**Step 5: Update Inline Handoff Notes section**

Handoff notes now live in task `.md` files. The dispatcher writes to `{PLAN_DIR}/phase-{letter}/{target_task_id_lower}.md`, inserting a `## Handoff from {TASK_ID}` section after the H1 header.

**Step 6: Verify word count**

Must be under 1,000 words. The current file is already dense — replacing markdown parsing instructions with script invocations should reduce rather than increase size.

Commit: "refactor: rewrite orchestrate SKILL.md for plan.json consumption"

---

#### B4: Rewrite phase-dispatcher-prompt.md for structured task dispatch

> **Handoff from A4:** Task-level update: `scripts/validate-plan --update-status <plan.json> --task <ID> --status <STATUS>`. Valid statuses: pending, in_progress, complete, skipped. Fails with exit 1 + `ERROR: task_not_found: '<ID>' not found in plan` if ID not found; `ERROR: invalid_task_status: '<STATUS>'` if status invalid. Always regenerates `plan.md` on success. Script path: `scripts/validate-plan` at repo root.

**Files:**
- Modify: `skills/orchestrate/phase-dispatcher-prompt.md`

**Verification:** Read the file, confirm it describes receiving `{PHASE_TASKS_JSON}` + `{PLAN_DIR}` + `{PHASE_DIR}`, reading task `.md` files, assembling `{TASK_METADATA}` + `{TASK_PROSE}` for implementer, calling `validate-plan --update-status` for task status.

**Done when:** The phase-dispatcher-prompt.md instructs the dispatcher to: receive structured task data as `{PHASE_TASKS_JSON}`, read task prose from `{PHASE_DIR}/{task_id_lower}.md`, assemble `{TASK_METADATA}` (JSON) + `{TASK_PROSE}` (markdown) for the implementer, call `validate-plan --update-status` before and after each task, write `completion.md` and cross-phase handoff notes to task files.

**Avoid:** Don't have the dispatcher read plan.json directly — it receives pre-extracted `{PHASE_TASKS_JSON}` from the orchestrator. This maintains context isolation.

**Step 1: Read the current phase-dispatcher-prompt.md**

Read `skills/orchestrate/phase-dispatcher-prompt.md`.

**Step 2: Update the Variables section**

Replace the old variables:

Old:
- `{PHASE_LETTER}`, `{PHASE_NAME}`, `{PHASE_SECTION}`, `{PRIOR_COMPLETION_NOTES}`, `{PLAN_FILE_PATH}`, `{REPO_PATH}`

New:
- `{PHASE_LETTER}` — the phase letter (A, B, C)
- `{PHASE_NAME}` — the phase name
- `{PHASE_TASKS_JSON}` — JSON array of tasks for this phase (from plan.json)
- `{PRIOR_COMPLETIONS}` — concatenated completion.md content from prior phases
- `{PLAN_DIR}` — absolute path to plan directory (for validate-plan calls and cross-phase handoff writes)
- `{PHASE_DIR}` — absolute path to current phase directory (for reading task .md files)
- `{CROSS_PHASE_HANDOFF_TARGETS}` — JSON object mapping source task IDs in this phase to target task file paths in later phases (e.g., `{"A2": "phase-b/b1.md"}`). Extracted by the orchestrator from plan.json by scanning later phases' `depends_on` arrays. Empty object `{}` if no cross-phase dependencies exist.
- `{REPO_PATH}` — working directory

**Step 3: Update the Per-Task Process**

For each task in `{PHASE_TASKS_JSON}`:
1. Call `validate-plan --update-status {PLAN_DIR}/plan.json --task {ID} --status in_progress`
2. Extract `{TASK_METADATA}` — the JSON object for this task from `{PHASE_TASKS_JSON}`
3. Read `{TASK_PROSE}` — content of `{PHASE_DIR}/{task_id_lower}.md`
4. Dispatch implementer with `{TASK_METADATA}` + `{TASK_PROSE}`
5. After implementer returns: dispatch spec reviewer with same `{TASK_METADATA}` + `{TASK_PROSE}`
6. After reviews pass: call `validate-plan --update-status {PLAN_DIR}/plan.json --task {ID} --status complete`
7. Check `{CROSS_PHASE_HANDOFF_TARGETS}` — if this task's ID is a key, write handoff to the target task file at `{PLAN_DIR}/{target_path}` (the value from the mapping)
8. Similarly, if a later task *within this phase* lists this task's ID in its `depends_on`, write handoff to `{PHASE_DIR}/{target_task_id_lower}.md` before that task is dispatched

**Step 4: Update the Completion Notes section**

When all tasks done:
- Run first-task integration tests if they exist
- Write `{PHASE_DIR}/completion.md` with the completion summary (date, summary, deviations)

**Step 5: Update the Report Back section**

Same structure — tasks completed, HEAD SHA, integration test status, deviations, concerns.

Commit: "refactor: rewrite phase-dispatcher-prompt.md for structured task dispatch"

---

#### B5: Rewrite implementer-prompt.md and spec-reviewer-prompt.md

> **Handoff from B4:** The phase-dispatcher-prompt.md passes two variables to both the implementer and spec-reviewer: `{TASK_METADATA}` (the JSON task object extracted from `{PHASE_TASKS_JSON}` — contains id, name, files, verification, done_when, depends_on, success_criteria) and `{TASK_PROSE}` (the full content of `{PHASE_DIR}/{task_id_lower}.md` — contains Avoid+WHY, Steps, and any handoff notes). Both templates must replace the old single-block task description with these two variables.

**Files:**
- Modify: `skills/orchestrate/implementer-prompt.md`
- Modify: `skills/orchestrate/spec-reviewer-prompt.md`

**Verification:** Read both files, confirm they describe receiving `{TASK_METADATA}` (JSON) + `{TASK_PROSE}` (markdown) instead of the old task block extraction.

**Done when:** The implementer-prompt.md receives `{TASK_METADATA}` (JSON: id, name, files, verification, done_when, depends_on, success_criteria) and `{TASK_PROSE}` (markdown: Avoid+WHY, Steps, handoff notes). The spec-reviewer-prompt.md receives the same pair. Both templates use these two variables instead of extracting task blocks from plan sections.

**Avoid:** Don't change the implementer's TDD workflow or the spec-reviewer's verification approach — only the input format changes. Don't add unnecessary variables.

**Step 1: Read the current files**

Read `skills/orchestrate/implementer-prompt.md` and `skills/orchestrate/spec-reviewer-prompt.md`.

**Step 2: Update implementer-prompt.md**

Replace the old `[Single task block extracted from #### {TASK_ID}: [name]...]` instruction with two clear input sections:

```text
## Task Metadata (from plan.json)

{TASK_METADATA}

This JSON contains: id, name, files (create/modify/test), verification
command, done_when criteria, depends_on (prior tasks), success_criteria.

## Task Instructions (from task file)

{TASK_PROSE}

This contains: Avoid+WHY section, Steps with full code, and any handoff
notes from prior phases.
```

Keep everything else unchanged — the TDD workflow, self-review checklist, report format, and "Before You Begin" questions section.

**Step 3: Update spec-reviewer-prompt.md**

Replace the `[FULL TEXT of task requirements]` section with:

```text
## Task Metadata

{TASK_METADATA}

## Task Instructions

{TASK_PROSE}
```

The reviewer now has structured access to files, verification commands, and done_when criteria in JSON. The prose gives it the avoid+why and steps for compliance checking.

Keep the "CRITICAL: Do Not Trust the Report" section and verification approach unchanged.

Commit: "refactor: update implementer and spec-reviewer prompts for structured input"

---

#### B6: Update implementation-review SKILL.md and reviewer-prompt.md

> **Handoff from B3:** Orchestrate passes implementation-review two paths at step 5: `plan.json` (absolute path, derived as `$(dirname "$(realpath plan.json)")"/plan.json`) and `${PHASE_DIR}/completion.md` (where `PHASE_DIR=${PLAN_DIR}/phase-{letter_lower}`). The reviewer receives these as `{PLAN_DIR}` and `{PHASE_DIR}` variables. See skills/orchestrate/SKILL.md line 57 for the exact dispatch call.

**Files:**
- Modify: `skills/implementation-review/SKILL.md`
- Modify: `skills/implementation-review/reviewer-prompt.md`

**Verification:** Read both files, confirm they reference `{PLAN_DIR}/plan.json` and `{PHASE_DIR}/completion.md` instead of the old plan file.

**Done when:** Implementation-review receives `{PLAN_DIR}/plan.json` for structured plan data and `{PHASE_DIR}/completion.md` for prose context. The reviewer-prompt.md instructs the reviewer to read plan.json for task metadata and completion.md for phase summary/deviations.

**Avoid:** Don't change the review categories or output format — only the input references change. Keep the same 7 cross-task issue categories and 4-level integration test coverage table.

**Step 1: Read the current files**

Read `skills/implementation-review/SKILL.md` and `skills/implementation-review/reviewer-prompt.md`.

**Step 2: Update SKILL.md**

Update the "How to Dispatch" variables table:

| Variable | Value |
|----------|-------|
| `{BASE_SHA}` | unchanged |
| `{HEAD_SHA}` | unchanged |
| `{FEATURE_SUMMARY}` | unchanged |
| `{TASK_LIST}` | Extract from plan.json: `jq '.phases[N].tasks[] \| .id + ": " + .name'` |
| `{PLAN_DIR}` | Path to plan directory (replaces `{PLAN_FILE_PATH}`) |
| `{PHASE_DIR}` | Path to current phase directory |
| `{REPO_PATH}` | unchanged |
| `{PHASE_CONTEXT}` | unchanged |

Update "Post-Review: Plan Doc Updates" to reference `phase-{letter}/completion.md` instead of `### Phase X Completion Notes`.

**Step 3: Update reviewer-prompt.md**

Replace `{PLAN_FILE_PATH}` references with `{PLAN_DIR}`. The reviewer reads:
- `{PLAN_DIR}/plan.json` for task metadata (files, verification, done_when)
- `{PHASE_DIR}/completion.md` for the phase summary and deviations

Update the Context section:

```text
## Context

Read the plan at {PLAN_DIR}/plan.json for structured task data.
Read {PHASE_DIR}/completion.md for:
- What was completed (Summary)
- What deviated from the plan and why (Deviations)
```

Keep all review categories, output format, and rules unchanged.

Commit: "refactor: update implementation-review for structured plan format"

---

#### B7: Bump plugin version in marketplace.json

**Files:**
- Modify: `.claude-plugin/marketplace.json`

**Verification:** `jq '.plugins[].version' .claude-plugin/marketplace.json` — all entries should show the bumped version.

**Done when:** All three plugin entries in marketplace.json have their version bumped (e.g., from `1.1.0` to `1.2.0`). No skill directories were added or removed, but the skill content changed significantly.

**Avoid:** Don't change anything other than version numbers. Don't add or remove skill entries from the plugins array.

**Step 1: Read the current marketplace.json**

Read `.claude-plugin/marketplace.json` to see current version.

**Step 2: Bump all three plugin versions**

The current version is `1.1.0`. Bump to `1.2.0` (minor version bump — backward-incompatible plan format change). Update all three plugin entries:
- `claude-caliper`: `1.1.0` → `1.2.0`
- `claude-caliper-workflow`: `1.1.0` → `1.2.0`
- `claude-caliper-tooling`: `1.1.0` → `1.2.0`

**Step 3: Verify**

Run `jq '.plugins[].version' .claude-plugin/marketplace.json` and confirm all show `"1.2.0"`.

Commit: "chore: bump plugin version to 1.2.0"

---

#### B8: Create GitHub issue for --criteria mode follow-up

**Files:**
- No file changes (GitHub issue only)

**Verification:** `gh issue view <ISSUE_NUMBER>` — issue exists with correct title and body.

**Done when:** A GitHub issue exists in the repo titled "feat: add --criteria runner mode to validate-plan" with a body describing: subprocess timeout management, exit code checking, output substring matching, and the `success_criteria` schema fields already in plan.json.

**Avoid:** Don't implement the --criteria runner — this is a tracking issue only. Don't create the issue if one already exists (check first with `gh issue list`).

**Step 1: Check for existing issue**

Run `gh issue list --search "criteria runner" --state open` to verify no duplicate exists.

**Step 2: Create the issue**

```bash
gh issue create \
  --title "feat: add --criteria runner mode to validate-plan" \
  --body "## Summary

Add a \`--criteria\` mode to \`scripts/validate-plan\` that programmatically runs \`success_criteria\` entries from plan.json.

## Scope

- Subprocess execution with configurable timeout (default 60s)
- Exit code checking (\`expect_exit\`)
- Output substring matching (\`expect_output\`)
- Run at task, phase, and plan levels
- Severity handling: \`blocking\` criteria fail the check, \`warning\` criteria report but don't fail

## Context

The \`success_criteria\` schema fields are already defined in plan.json (added in the structured plans work). This issue covers building the runner that evaluates them.

## Design Reference

See \`docs/plans/2026-03-19-structured-plans/design-structured-plans.md\`, section 'Deferred: Success Criteria Runner'."
```

Commit: not needed (no file changes)
