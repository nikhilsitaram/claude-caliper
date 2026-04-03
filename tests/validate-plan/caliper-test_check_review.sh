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

assert_exit() {
  local desc="$1" expected_exit="$2"; shift 2
  local actual_exit=0
  "$@" > /dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

setup_plan_dir() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
}

echo "Test 1: Missing reviews.json"
setup_plan_dir
rm -f "$TMPDIR/reviews.json"
assert_fail "missing reviews.json exits 1 with error" "reviews.json not found" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 2: Empty reviews.json array"
setup_plan_dir
echo '[]' > "$TMPDIR/reviews.json"
assert_fail "empty reviews.json exits 1 with no record error" "no review record for" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 3: No matching type+scope"
setup_plan_dir
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "no matching type+scope exits 1" "no review record for" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 4: Matching record with verdict:fail"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"fail","remaining":3}]' > "$TMPDIR/reviews.json"
assert_fail "verdict:fail exits 1 with gate failed error" "review gate failed" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 5: Matching record with verdict:pass but remaining>0"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":2}]' > "$TMPDIR/reviews.json"
assert_fail "verdict:pass but remaining>0 exits 1" "review gate failed" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 6: Passing record (verdict:pass, remaining:0)"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "verdict:pass remaining:0 exits 0" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 7: Multiple records — latest wins (first fails, second passes)"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"fail","remaining":5},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "latest record passes even though first failed" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 8: Latest record fails (first passes, second fails)"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"fail","remaining":2}]' > "$TMPDIR/reviews.json"
assert_fail "latest record fails even though first passed" "review gate failed" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review --scope phase-a

echo "Test 9: Missing --type argument"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_exit "missing --type exits 2" 2 \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --scope phase-a

echo "Test 10: Missing --scope argument"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_exit "missing --scope exits 2" 2 \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type impl-review

echo "Test 11: Record with missing remaining field (defaults to 0)"
setup_plan_dir
printf '[{"type":"plan-review","scope":"plan","verdict":"pass"}]' > "$TMPDIR/reviews.json"
assert_pass "missing remaining field defaults to 0, passes" \
  "$VALIDATE" --check-review "$TMPDIR/plan.json" --type plan-review --scope plan

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
