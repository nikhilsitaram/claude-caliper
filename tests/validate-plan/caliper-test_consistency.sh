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

setup_valid_plan() {
  local dir="$1"
  rm -rf "${dir:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$dir/"
  cp "$FIXTURES/valid-plan/plan.json" "$dir/plan.json"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== --consistency mode tests ==="

echo "Test 1: Valid plan passes --consistency"
setup_valid_plan "$TMPDIR"
assert_pass "valid plan passes consistency" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 2: Rule 1 - Phase 'Not Started' but task is in_progress"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "in_progress"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "phase not started but task in_progress" "status_inconsistency" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 3: Rule 1 - Phase 'Not Started' but task is complete"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "phase not started but task complete" "status_inconsistency" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 4: Rule 2 - Phase 'Complete' but task pending (via --consistency)"
setup_valid_plan "$TMPDIR"
jq '.phases[0].status = "Complete (2026-03-24)" | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "pending"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
assert_fail "phase complete with pending task via --consistency" "status_inconsistency" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 5: Rule 3 - Task complete but dependency is pending"
setup_valid_plan "$TMPDIR"
jq '.status = "In Development" | .phases[0].status = "In Progress" | .phases[0].tasks[0].status = "pending" | .phases[0].tasks[1].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A2 Completion" > "$TMPDIR/phase-a/a2-completion.md"
assert_fail "task complete but dep pending" "but dependency A1 is" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 6: Rule 3 - Task complete but dependency is in_progress"
setup_valid_plan "$TMPDIR"
jq '.status = "In Development" | .phases[0].status = "In Progress" | .phases[0].tasks[0].status = "in_progress" | .phases[0].tasks[1].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A2 Completion" > "$TMPDIR/phase-a/a2-completion.md"
assert_fail "task complete but dep in_progress" "but dependency A1 is" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 7: Rule 4 - Plan 'Not Yet Started' but phase is In Progress"
setup_valid_plan "$TMPDIR"
jq '.phases[0].status = "In Progress"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "plan not yet started but phase in progress" "status_inconsistency" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 8: Rule 5 - Plan 'Complete' but phase not Complete (via --consistency)"
setup_valid_plan "$TMPDIR"
jq '.status = "Complete" | .phases[0].status = "Complete (2026-03-24)" | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
echo "# A2 Completion" > "$TMPDIR/phase-a/a2-completion.md"
assert_fail "plan complete but phase not complete via --consistency" "status_inconsistency" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 9: Rule 6 - Phase Complete without impl-review (now enforced at transition time, not consistency)"
setup_valid_plan "$TMPDIR"
jq '.status = "In Development" | .phases[0].status = "Complete (2026-03-24)" | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
echo '[]' > "$TMPDIR/reviews.json"
assert_pass "phase complete without impl-review passes consistency (gate moved to --update-status)" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json"

echo "Test 10: --schema still catches status_inconsistency (chains to consistency)"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "in_progress"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "schema catches phase not started but task in_progress" "status_inconsistency" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
