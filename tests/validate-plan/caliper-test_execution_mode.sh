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

make_plan() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
  cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
}

echo "=== execution_mode validation ==="

echo "Test 1: Plan with execution_mode 'subagents' passes"
make_plan
jq '. + {"execution_mode": "subagents"}' "$TMPDIR/plan.json" > "$TMPDIR/plan.tmp" && mv "$TMPDIR/plan.tmp" "$TMPDIR/plan.json"
assert_pass "execution_mode 'subagents' accepted" "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Plan with execution_mode 'agent-teams' passes"
make_plan
jq '. + {"execution_mode": "agent-teams"}' "$TMPDIR/plan.json" > "$TMPDIR/plan.tmp" && mv "$TMPDIR/plan.tmp" "$TMPDIR/plan.json"
assert_pass "execution_mode 'agent-teams' accepted" "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: Plan missing execution_mode fails"
make_plan
jq 'del(.execution_mode)' "$TMPDIR/plan.json" > "$TMPDIR/plan.tmp" && mv "$TMPDIR/plan.tmp" "$TMPDIR/plan.json"
assert_fail "missing execution_mode rejected" "missing_field: execution_mode" "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Plan with invalid execution_mode 'parallel' fails"
make_plan
jq '. + {"execution_mode": "parallel"}' "$TMPDIR/plan.json" > "$TMPDIR/plan.tmp" && mv "$TMPDIR/plan.tmp" "$TMPDIR/plan.json"
assert_fail "invalid execution_mode 'parallel' rejected" "invalid_execution_mode" "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 5: Plan with invalid execution_mode 'main' fails"
make_plan
jq '. + {"execution_mode": "main"}' "$TMPDIR/plan.json" > "$TMPDIR/plan.tmp" && mv "$TMPDIR/plan.tmp" "$TMPDIR/plan.json"
assert_fail "invalid execution_mode 'main' rejected" "invalid_execution_mode" "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 6: Plan with empty execution_mode fails"
make_plan
jq '. + {"execution_mode": ""}' "$TMPDIR/plan.json" > "$TMPDIR/plan.tmp" && mv "$TMPDIR/plan.tmp" "$TMPDIR/plan.json"
assert_fail "empty execution_mode rejected" "missing_field: execution_mode" "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
