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
  local output
  if output=$("$@" 2>&1); then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (got: $output)"
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

setup_plan_dir() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
}

all_phase_reviews() {
  local plan_json="$1"
  local phase_count
  phase_count=$(jq '.phases | length' "$plan_json")
  local reviews="[]"
  for ((p=0; p<phase_count; p++)); do
    local letter letter_lower
    letter=$(jq -r ".phases[$p].letter" "$plan_json")
    letter_lower=$(echo "$letter" | tr '[:upper:]' '[:lower:]')
    reviews=$(echo "$reviews" | jq ". + [{\"type\":\"impl-review\",\"scope\":\"phase-$letter_lower\",\"verdict\":\"pass\",\"remaining\":0}]")
  done
  echo "$reviews"
}

echo "Test 1: Phase completion blocked without impl-review"
setup_plan_dir
rm -f "$TMPDIR/reviews.json"
assert_fail "phase complete blocked — no reviews.json" "cannot mark phase A complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test 2: Phase completion blocked with failing impl-review"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"fail","remaining":3}]' > "$TMPDIR/reviews.json"
assert_fail "phase complete blocked — impl-review verdict:fail" "cannot mark phase A complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test 3: Phase completion succeeds with passing impl-review"
setup_plan_dir
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "phase complete allowed with passing impl-review" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test 4: Phase In Progress transition not gated"
setup_plan_dir
rm -f "$TMPDIR/reviews.json"
assert_pass "phase In Progress not gated — no reviews.json needed" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "In Progress"

mark_all_phases_complete() {
  local plan_json="$1"
  local phase_count
  phase_count=$(jq '.phases | length' "$plan_json")
  local tmp="${plan_json}.tmp.$$"
  cp "$plan_json" "$tmp"
  for ((p=0; p<phase_count; p++)); do
    jq --argjson idx "$p" '.phases[$idx].status = "Complete (2026-03-23)"' "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"
  done
  mv "$tmp" "$plan_json"
}

echo "Test 5: Plan completion blocked without design-review"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "plan complete blocked — missing design-review" "cannot mark plan complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test 5b: Plan completion blocked when phases not complete"
setup_plan_dir
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"final","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "plan complete blocked — phases not complete" "phases not complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test 6: Plan completion blocked without plan-review"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "plan complete blocked — missing plan-review" "cannot mark plan complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test 7: Multi-phase plan completion blocked without final impl-review"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "multi-phase plan complete blocked — missing final impl-review" "impl-review final" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test 8: Multi-phase plan completion succeeds with all reviews including final"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"final","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_pass "multi-phase plan complete succeeds with all reviews" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test 9: Single-phase plan does not require final impl-review"
setup_plan_dir
jq '.phases = [.phases[0]] | .phases[0].status = "Complete (2026-03-23)"' "$TMPDIR/plan.json" > "$TMPDIR/plan_single.json"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "single-phase plan complete succeeds without final impl-review" \
  "$VALIDATE" --update-status "$TMPDIR/plan_single.json" --plan --status "Complete"

echo "Test 10: Plan In Development transition not gated"
setup_plan_dir
rm -f "$TMPDIR/reviews.json"
assert_pass "plan In Development not gated" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "In Development"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
