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
jq '.phases[0].tasks[1].files.create = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "same file in create of two tasks in same phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: Same file in modify of two tasks in same phase fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].files.modify = ["src/shared.ts"] | .phases[0].tasks[1].files.modify = ["src/shared.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "same file in modify of two tasks in same phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Same file in test of two tasks in same phase fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].files.test = ["tests/shared.test.ts"] | .phases[0].tasks[1].files.test = ["tests/shared.test.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "same file in test of two tasks in same phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 5: Cross-array overlap within phase fails (A1 creates, A2 modifies same file)"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].files.modify = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "cross-array overlap within phase" "fileset_overlap" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 6: Cross-phase overlap passes (A1 creates in Phase A, B1 modifies in Phase B)"
setup_valid_plan "$TMPDIR"
jq '.phases[1].tasks[0].files.modify = ["src/core.ts"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_pass "cross-phase overlap passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
