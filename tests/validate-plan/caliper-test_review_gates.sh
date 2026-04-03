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

mark_tasks_complete() {
  local plan_json="$1" phase_letter="$2"
  local tmp="${plan_json}.tmp.$$"
  jq --arg letter "$phase_letter" '(.phases[] | select(.letter == $letter) | .tasks[].status) = "complete"' "$plan_json" > "$tmp" && mv "$tmp" "$plan_json"
}

all_task_reviews_for_phase() {
  local plan_json="$1" phase_letter="$2"
  jq -r --arg letter "$phase_letter" '[.phases[] | select(.letter == $letter) | .tasks[] | {"type":"task-review","scope":.id,"verdict":"pass","remaining":0}] | .[]' "$plan_json" | jq -s '.'
}

activate_plan() {
  local plan_json="$1"
  local tmp="${plan_json}.tmp.$$"
  jq '.status = "In Development" | .phases[0].status = "In Progress"' "$plan_json" > "$tmp" && mv "$tmp" "$plan_json"
}

echo "=== Task completion gates ==="

echo "Test T1: Task completion blocked without task-review"
setup_plan_dir
activate_plan "$TMPDIR/plan.json"
rm -f "$TMPDIR/reviews.json"
assert_fail "task complete blocked — no reviews.json" "cannot mark task A1 complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status complete

echo "Test T2: Task completion blocked with failing task-review"
setup_plan_dir
activate_plan "$TMPDIR/plan.json"
printf '[{"type":"task-review","scope":"A1","verdict":"fail","remaining":2}]' > "$TMPDIR/reviews.json"
assert_fail "task complete blocked — task-review verdict:fail" "cannot mark task A1 complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status complete

echo "Test T3: Task completion succeeds with passing task-review"
setup_plan_dir
activate_plan "$TMPDIR/plan.json"
printf '[{"type":"task-review","scope":"A1","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "task complete allowed with passing task-review" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status complete

echo "Test T4: Task in_progress not gated on reviews"
setup_plan_dir
activate_plan "$TMPDIR/plan.json"
rm -f "$TMPDIR/reviews.json"
assert_pass "task in_progress not gated on reviews" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status in_progress

echo "Test T5: Task skipped transition not gated"
setup_plan_dir
rm -f "$TMPDIR/reviews.json"
assert_pass "task skipped not gated" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status skipped

echo "Test T6: Task blocked when parent phase is Not Started"
setup_plan_dir
jq '.status = "In Development"' "$TMPDIR/plan.json" > "$TMPDIR/plan_tmp.json" && mv "$TMPDIR/plan_tmp.json" "$TMPDIR/plan.json"
assert_fail "task blocked — phase Not Started" "parent phase is 'Not Started'" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status in_progress

echo "Test T7: Task blocked when dependency not complete"
setup_plan_dir
activate_plan "$TMPDIR/plan.json"
assert_fail "task blocked — dependency A1 not complete" "dependencies not complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status in_progress

echo "Test T8: Task allowed when dependency is complete"
setup_plan_dir
activate_plan "$TMPDIR/plan.json"
printf '[{"type":"task-review","scope":"A1","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status complete
assert_pass "task allowed — dependency A1 is complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status in_progress

echo "Test T9: Task allowed when dependency is skipped"
setup_plan_dir
activate_plan "$TMPDIR/plan.json"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status skipped
assert_pass "task allowed — dependency A1 is skipped" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status in_progress

echo ""
echo "=== Phase completion gates ==="

activate_plan_only() {
  local plan_json="$1"
  local tmp="${plan_json}.tmp.$$"
  jq '.status = "In Development"' "$plan_json" > "$tmp" && mv "$tmp" "$plan_json"
}

echo "Test P1: Phase completion blocked without reviews.json"
setup_plan_dir
activate_plan_only "$TMPDIR/plan.json"
rm -f "$TMPDIR/reviews.json"
assert_fail "phase complete blocked — no reviews.json" "cannot mark phase A complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test P2: Phase completion blocked with failing impl-review"
setup_plan_dir
activate_plan_only "$TMPDIR/plan.json"
mark_tasks_complete "$TMPDIR/plan.json" A
local_reviews=$(all_task_reviews_for_phase "$TMPDIR/plan.json" A)
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"impl-review","scope":"phase-a","verdict":"fail","remaining":3}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "phase complete blocked — impl-review verdict:fail" "cannot mark phase A complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test P3: Phase completion blocked when tasks still pending"
setup_plan_dir
activate_plan_only "$TMPDIR/plan.json"
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "phase complete blocked — tasks pending" "cannot mark phase A complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test P4: Phase completion blocked when task-reviews missing"
setup_plan_dir
activate_plan_only "$TMPDIR/plan.json"
mark_tasks_complete "$TMPDIR/plan.json" A
printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "phase complete blocked — missing task-reviews" "cannot mark phase A complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test P5: Phase completion succeeds with all gates satisfied"
setup_plan_dir
activate_plan_only "$TMPDIR/plan.json"
mark_tasks_complete "$TMPDIR/plan.json" A
local_reviews=$(all_task_reviews_for_phase "$TMPDIR/plan.json" A)
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_pass "phase complete allowed with all gates" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test P6: Phase In Progress succeeds when plan is In Development"
setup_plan_dir
activate_plan_only "$TMPDIR/plan.json"
rm -f "$TMPDIR/reviews.json"
assert_pass "phase In Progress allowed when plan active" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "In Progress"

echo "Test P7: Phase completion allows skipped tasks without task-review"
setup_plan_dir
activate_plan_only "$TMPDIR/plan.json"
jq '(.phases[] | select(.letter == "A") | .tasks[0].status) = "complete" | (.phases[] | select(.letter == "A") | .tasks[1].status) = "skipped"' "$TMPDIR/plan.json" > "$TMPDIR/plan_tmp.json" && mv "$TMPDIR/plan_tmp.json" "$TMPDIR/plan.json"
printf '[{"type":"task-review","scope":"A1","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "phase complete with skipped task (no review needed for skipped)" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-23)"

echo "Test P8: Phase blocked when plan is Not Yet Started"
setup_plan_dir
assert_fail "phase blocked — plan Not Yet Started" "plan is 'Not Yet Started'" \
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

echo ""
echo "=== Plan completion gates ==="

echo "Test PL1: Plan completion blocked without design-review"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "plan complete blocked — missing design-review" "cannot mark plan complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test PL1b: Plan completion blocked when phases not complete"
setup_plan_dir
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"final","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "plan complete blocked — phases not complete" "phases not complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test PL2: Plan completion blocked without plan-review"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "plan complete blocked — missing plan-review" "cannot mark plan complete" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test PL3: Multi-phase plan completion blocked without final impl-review"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_fail "multi-phase plan complete blocked — missing final impl-review" "impl-review final" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test PL4: Multi-phase plan completion succeeds with all reviews including final"
setup_plan_dir
mark_all_phases_complete "$TMPDIR/plan.json"
local_reviews=$(all_phase_reviews "$TMPDIR/plan.json")
local_reviews=$(echo "$local_reviews" | jq '. + [{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"final","verdict":"pass","remaining":0}]')
echo "$local_reviews" > "$TMPDIR/reviews.json"
assert_pass "multi-phase plan complete succeeds with all reviews" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "Complete"

echo "Test PL5: Single-phase plan does not require final impl-review"
setup_plan_dir
jq '.phases = [.phases[0]] | .phases[0].status = "Complete (2026-03-23)"' "$TMPDIR/plan.json" > "$TMPDIR/plan_single.json"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "single-phase plan complete succeeds without final impl-review" \
  "$VALIDATE" --update-status "$TMPDIR/plan_single.json" --plan --status "Complete"

echo "Test PL6: Plan In Development transition not gated"
setup_plan_dir
rm -f "$TMPDIR/reviews.json"
assert_pass "plan In Development not gated" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "In Development"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
