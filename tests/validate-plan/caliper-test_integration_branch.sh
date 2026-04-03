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

echo "=== integration_branch schema validation ==="

echo "Test 1: Plan without integration_branch passes (optional)"
setup_valid_plan "$TMPDIR"
assert_pass "no integration_branch passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Plan with valid integration_branch passes"
setup_valid_plan "$TMPDIR"
jq '.integration_branch = "integrate/my-feature"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_pass "valid integration_branch passes" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: Plan with whitespace-only integration_branch fails"
setup_valid_plan "$TMPDIR"
jq '.integration_branch = "  "' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "whitespace integration_branch fails" "invalid_integration_branch" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Plan with empty string integration_branch fails"
setup_valid_plan "$TMPDIR"
jq '.integration_branch = ""' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "empty integration_branch fails" "invalid_integration_branch" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 5: Plan with null integration_branch fails"
setup_valid_plan "$TMPDIR"
jq '.integration_branch = null' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "null integration_branch fails" "invalid_integration_branch" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
