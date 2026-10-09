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

setup_valid_plan() {
  local dir="$1"
  rm -rf "${dir:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$dir/"
  cp "$FIXTURES/valid-plan/plan.json" "$dir/plan.json"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Test 1: Plan with no file-set overlap passes"
setup_valid_plan "$TMPDIR"
assert_pass "plan with no overlap passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Same file in create of two tasks in same phase fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].depends_on = [] | .phases[0].tasks[1].files.create = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "same file in create of two tasks in same phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: Same file in modify of two tasks in same phase fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].depends_on = [] | .phases[0].tasks[0].files.modify = ["src/shared.ts"] | .phases[0].tasks[1].files.modify = ["src/shared.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "same file in modify of two tasks in same phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Same file in test of two tasks in same phase fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].depends_on = [] | .phases[0].tasks[0].files.test = ["tests/shared.test.ts"] | .phases[0].tasks[1].files.test = ["tests/shared.test.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "same file in test of two tasks in same phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 5: Cross-array overlap within phase fails (A1 creates, A2 modifies same file)"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].depends_on = [] | .phases[0].tasks[1].files.modify = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "cross-array overlap within phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 6: Cross-phase overlap passes (A1 creates in Phase A, B1 modifies in Phase B)"
setup_valid_plan "$TMPDIR"
jq '.phases[1].tasks[0].files.modify = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_pass "cross-phase overlap passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# Same-phase overlap is legal when a depends_on path orders the two tasks:
# orchestrate dispatches a dependent only after its prerequisite merges, so
# they never run concurrently (gh issue #290).

# Appends task A3 (a copy of A2) with the given depends_on and files.modify
add_a3() {
  local deps="$1" modify="$2"
  jq --argjson deps "$deps" --argjson mod "$modify" '.phases[0].tasks += [(.phases[0].tasks[1]
    | .id = "A3" | .name = "Third task" | .depends_on = $deps
    | .files = {create: [], modify: $mod, test: []})]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
}

echo "Test 7: Same-phase overlap passes when one task depends_on the other"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].files.modify = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_pass "A2 (depends_on A1) modifies A1's file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 8: Same-phase overlap passes through a transitive depends_on path"
setup_valid_plan "$TMPDIR"
add_a3 '["A2"]' '["src/core.ts"]'
assert_pass "A3 -> A2 -> A1 orders A3 after A1" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 9: Siblings ordered after a common task but not each other still fail"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].files.modify = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
add_a3 '["A1"]' '["src/core.ts"]'
assert_fail "A2 and A3 both depend only on A1 and share A1's file" "fileset_overlap: file 'src/core.ts' claimed by tasks A2 and A3" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 10: Ordering does not legalize two tasks creating the same file"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].files.create = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "ordered create+create still rejected" "duplicate_create_path" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

# depends_on now decides whether tasks may share a file, so a malformed value
# must fail loudly rather than abort the overlap check and pass the plan.
echo "Test 11: string depends_on is rejected, not silently skipped"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].depends_on = "A1" | .phases[0].tasks[1].files.modify = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "string depends_on rejected" "invalid_dependency: task A2 depends_on must be an array" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 12: string files.test is rejected, not silently skipped"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].files.test = "tests/core.test.ts"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "string files.test rejected" "invalid_files: task A1 files.test must be an array" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
