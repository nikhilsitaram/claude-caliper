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

echo "Test 1: Existing plan without supervision field still passes"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
assert_pass "plan without supervision field passes schema check" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Valid full supervision object passes"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {"orchestrator_poll_seconds": 60, "dispatcher_poll_seconds": 30, "max_intervention_attempts": 2}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_pass "plan with valid supervision object passes schema check" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: Partial supervision object passes (only one field)"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {"orchestrator_poll_seconds": 120}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_pass "plan with partial supervision object passes schema check" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Empty supervision object passes"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_pass "plan with empty supervision object passes schema check" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 5: Non-integer orchestrator_poll_seconds fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {"orchestrator_poll_seconds": "sixty"}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "non-integer orchestrator_poll_seconds fails" "invalid_supervision_field" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 6: Negative dispatcher_poll_seconds fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {"dispatcher_poll_seconds": -1}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "negative dispatcher_poll_seconds fails" "invalid_supervision_field" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 7: Zero max_intervention_attempts fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {"max_intervention_attempts": 0}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "zero max_intervention_attempts fails" "invalid_supervision_field" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 8: Unknown key in supervision fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {"unknown_key": 42}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "unknown supervision key fails" "unknown_supervision_field" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 9: Non-object supervision type fails"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": 42}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_fail "non-object supervision type fails" "invalid_supervision_type" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
