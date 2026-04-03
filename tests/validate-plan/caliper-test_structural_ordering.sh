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
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Test 1: Valid plan with matching task ID prefixes passes"
setup_valid_plan "$TMPDIR"
assert_pass "valid plan with matching task ID prefixes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Task with mismatched prefix (B1 in Phase A) fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[1].id = "B1" | .phases[0].tasks[1].name = "Mismatched task"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# B1: Mismatched task" > "$TMPDIR/phase-a/b1.md"
assert_fail "task with mismatched prefix in phase" "task_id_phase_mismatch" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: Out-of-order phases (B before A) fails"
setup_valid_plan "$TMPDIR"
jq '.phases = [.phases[1], .phases[0]] | .phases[0].depends_on = [] | .phases[1].depends_on = ["B"]' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "out-of-order phases" "phase_order" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Valid multi-phase plan (A then B) passes"
setup_valid_plan "$TMPDIR"
assert_pass "valid multi-phase plan (A then B)" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
