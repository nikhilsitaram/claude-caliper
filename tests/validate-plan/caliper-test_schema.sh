#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/bin/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_pass() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    ((FAIL++)) || true
  fi
}

assert_fail() {
  local desc="$1"; shift
  local expected_error="$1"; shift
  local output
  if output=$("$@" 2>&1); then
    echo "FAIL: $desc (expected failure, got success)"
    ((FAIL++)) || true
  elif echo "$output" | grep -q "$expected_error"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected_error' in output, got: $output)"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Test 1: Valid plan passes"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
assert_pass "valid plan passes schema check" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Missing required field (remove goal)"
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq 'del(.goal)' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "missing goal field" "missing_field: goal" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: depends_on references future phase"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].tasks[0].depends_on = ["B1"]' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "depends_on references future phase" "invalid_dependency" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Duplicate create paths"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[1].tasks[0].files.create = ["src/core.ts"]' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "duplicate create path" "duplicate_create_path" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 5: Missing task file"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
rm "$TMPDIR/phase-a/a1.md"
assert_fail "missing task file" "missing_task_file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 6: H1 header mismatch"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
echo "# A1: Wrong Name" > "$TMPDIR/phase-a/a1.md"
assert_fail "H1 header mismatch" "h1_mismatch" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 7: Missing completion.md"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
rm "$TMPDIR/phase-a/completion.md"
assert_fail "missing completion.md" "missing_completion_file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 8: Invalid task status"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].tasks[0].status = "invalid"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "invalid task status" "invalid_task_status" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 9: Empty run string in success_criteria"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.success_criteria[0].run = ""' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "empty run string" "empty_run" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 10: success_criteria missing both expect_exit and expect_output"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.success_criteria = [{"run": "echo ok"}]' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "criteria missing expect" "missing_expect" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 11: Invalid plan status"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.status = "bogus"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "invalid plan status" "invalid_plan_status" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 12: Invalid phase status"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].status = "bogus"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "invalid phase status" "invalid_phase_status" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 13: Duplicate task ID"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].tasks[1].id = "A1"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "duplicate task ID" "duplicate_task_id" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 14: Duplicate phase letter"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[1].letter = "A"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "duplicate phase letter" "duplicate_phase_letter" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 15: Lowercase phase letter"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases[0].letter = "a"' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "lowercase phase letter" "invalid_phase_letter_format" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 16: Empty phases array"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '.phases = []' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "empty phases array" "empty_phases" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 17: Valid workflow pr-merge passes"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "pr-merge"} | .phases[0] += {"depends_on": []} | .phases[1] += {"depends_on": ["A"]}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_pass "valid workflow pr-merge passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 18: Invalid workflow value fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "auto"} | .phases[0] += {"depends_on": []} | .phases[1] += {"depends_on": ["A"]}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "invalid workflow auto fails" "invalid_workflow" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 18b: Old workflow value 'ship' is rejected"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "ship"}' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "old workflow ship is rejected" "invalid_workflow" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 18c: Old workflow value 'review-only' is rejected"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "review-only"}' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "old workflow review-only is rejected" "invalid_workflow" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 18d: Old workflow value 'create-pr' is rejected"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "create-pr"}' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "old workflow create-pr is rejected" "invalid_workflow" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 18e: Old workflow value 'merge-pr' is rejected"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "merge-pr"}' "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "old workflow merge-pr is rejected" "invalid_workflow" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 19: Missing workflow field fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq 'del(.workflow)' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "missing workflow fails" "missing_field: workflow" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 20: Multi-phase depends_on (C depends on A and B)"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
mkdir -p "$TMPDIR/phase-c"
touch "$TMPDIR/phase-c/completion.md"
echo "# C1: Phase C task" > "$TMPDIR/phase-c/c1.md"
jq '. + {"workflow": "pr-create"} | .phases[0] += {"depends_on": []} | .phases[1] += {"depends_on": ["A"]} | .phases += [{"letter": "C", "name": "Integration", "status": "Not Started", "rationale": "Depends on A and B", "depends_on": ["A", "B"], "tasks": [{"id": "C1", "name": "Phase C task", "status": "pending", "depends_on": [], "files": {"create": ["src/c1.ts"], "modify": [], "test": ["tests/c1.test.ts"]}, "verification": "echo ok", "done_when": "C1 done", "success_criteria": []}]}]' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_pass "multi-phase depends_on C depends on A and B passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 21: depends_on references non-existent phase fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "pr-create"} | .phases[0] += {"depends_on": []} | .phases[1] += {"depends_on": ["Z"]}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "depends_on references non-existent phase" "invalid_depends_on" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 22: Circular phase dependency detected"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "pr-create"} | .phases[0] += {"depends_on": ["B"]} | .phases[1] += {"depends_on": ["A"]}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "circular phase dependency" "circular_dependency" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 23: Valid workflow plan-only passes"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"workflow": "plan-only"} | .phases[0] += {"depends_on": []} | .phases[1] += {"depends_on": ["A"]}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_pass "valid workflow plan-only passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
