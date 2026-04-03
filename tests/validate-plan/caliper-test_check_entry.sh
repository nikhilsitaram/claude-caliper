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

setup_valid_plan() {
  local dir="$1"
  rm -rf "${dir:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$dir/"
  cp "$FIXTURES/valid-plan/plan.json" "$dir/plan.json"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== --check-entry tests ==="

echo "Test 1: --check-entry without --stage exits 2"
setup_valid_plan "$TMPDIR"
assert_exit "--check-entry without --stage exits 2" 2 \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json"

echo "Test 2: --check-entry with unknown stage exits 2"
setup_valid_plan "$TMPDIR"
assert_exit "--check-entry unknown stage exits 2" 2 \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json" --stage "bogus"

echo "Test 3: draft-plan entry gate fails without design-review"
setup_valid_plan "$TMPDIR"
assert_fail "draft-plan fails without design-review" "entry gate failed" \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json" --stage draft-plan

echo "Test 4: draft-plan entry gate passes with design-review"
setup_valid_plan "$TMPDIR"
echo '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "draft-plan passes with design-review" \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json" --stage draft-plan

echo "Test 5: execution entry gate fails without both reviews"
setup_valid_plan "$TMPDIR"
assert_fail "execution fails without reviews" "entry gate failed" \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json" --stage execution

echo "Test 6: execution entry gate fails with only design-review"
setup_valid_plan "$TMPDIR"
echo '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "execution fails with only design-review" "entry gate failed" \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json" --stage execution

echo "Test 7: execution entry gate passes with both reviews"
setup_valid_plan "$TMPDIR"
echo '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "execution passes with both reviews" \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json" --stage execution

echo "Test 8: draft-plan passes without plan.json (only reviews.json needed)"
rm -rf "${TMPDIR:?}/"*
mkdir -p "$TMPDIR"
echo '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "draft-plan without plan.json but with reviews.json" \
  "$VALIDATE" --check-entry "$TMPDIR/plan.json" --stage draft-plan

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
