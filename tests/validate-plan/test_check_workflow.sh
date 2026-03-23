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

setup_plan_dir() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
}

write_single_phase_plan() {
  local workflow="$1" status="${2:-Not Yet Started}"
  cat > "$TMPDIR/plan.json" <<JSON
{
  "schema": 1,
  "status": "$status",
  "workflow": "$workflow",
  "goal": "Test workflow gate",
  "architecture": "Single phase test",
  "tech_stack": "Bash",
  "phases": [
    {
      "letter": "A",
      "name": "Foundation",
      "status": "Not Started",
      "depends_on": [],
      "rationale": "Test phase",
      "tasks": [
        {
          "id": "A1",
          "name": "Core task",
          "status": "pending",
          "depends_on": [],
          "files": { "create": [], "modify": [], "test": [] },
          "verification": "echo ok",
          "done_when": "Always done"
        }
      ]
    }
  ]
}
JSON
  mkdir -p "$TMPDIR/phase-a"
  touch "$TMPDIR/phase-a/completion.md"
}

write_two_phase_plan() {
  local workflow="$1" status="${2:-Not Yet Started}"
  cat > "$TMPDIR/plan.json" <<JSON
{
  "schema": 1,
  "status": "$status",
  "workflow": "$workflow",
  "goal": "Test workflow gate two-phase",
  "architecture": "Two phase test",
  "tech_stack": "Bash",
  "phases": [
    {
      "letter": "A",
      "name": "Foundation",
      "status": "Not Started",
      "depends_on": [],
      "rationale": "Phase A",
      "tasks": [
        {
          "id": "A1",
          "name": "Core task",
          "status": "pending",
          "depends_on": [],
          "files": { "create": [], "modify": [], "test": [] },
          "verification": "echo ok",
          "done_when": "Always done"
        }
      ]
    },
    {
      "letter": "B",
      "name": "Consumer",
      "status": "Not Started",
      "depends_on": ["A"],
      "rationale": "Phase B",
      "tasks": [
        {
          "id": "B1",
          "name": "Consumer task",
          "status": "pending",
          "depends_on": ["A1"],
          "files": { "create": [], "modify": [], "test": [] },
          "verification": "echo ok",
          "done_when": "Always done"
        }
      ]
    }
  ]
}
JSON
  mkdir -p "$TMPDIR/phase-a" "$TMPDIR/phase-b"
  touch "$TMPDIR/phase-a/completion.md" "$TMPDIR/phase-b/completion.md"
}

echo "=== plan-only workflow ==="

echo "Test 1: plan-only passes with both reviews"
setup_plan_dir
write_single_phase_plan "plan-only"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "plan-only with both reviews exits 0" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 2: plan-only fails missing design-review"
setup_plan_dir
write_single_phase_plan "plan-only"
printf '[{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "plan-only missing design-review exits 1" "design-review not passed" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 3: plan-only fails missing plan-review"
setup_plan_dir
write_single_phase_plan "plan-only"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "plan-only missing plan-review exits 1" "plan-review not passed" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 4: plan-only fails missing reviews.json"
setup_plan_dir
write_single_phase_plan "plan-only"
rm -f "$TMPDIR/reviews.json"
assert_fail "plan-only missing reviews.json exits 1" "reviews.json not found" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "=== create-pr workflow ==="

echo "Test 5: create-pr fails when plan not Complete"
setup_plan_dir
write_single_phase_plan "create-pr" "In Development"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "create-pr with plan In Development exits 1" "plan status is" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 6: create-pr fails missing impl-review"
setup_plan_dir
write_single_phase_plan "create-pr" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "create-pr missing impl-review for phase-a exits 1" "impl-review phase-a" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "=== merge-pr workflow ==="

echo "Test 7: merge-pr requires PR merged (skipped if gh not available)"
if ! command -v gh >/dev/null 2>&1; then
  echo "SKIP: gh CLI not available — skipping PR check tests"
else
  setup_plan_dir
  write_single_phase_plan "merge-pr" "Complete"
  printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
  assert_fail "merge-pr with all reviews but no merged PR exits 1" "PR not merged\|no PR found\|gh pr list failed" \
    "$VALIDATE" --check-workflow "$TMPDIR/plan.json"
fi

echo ""
echo "=== multi-phase specifics ==="

echo "Test 8: multi-phase create-pr requires final impl-review"
setup_plan_dir
write_two_phase_plan "create-pr" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-b","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "create-pr two-phase without final impl-review exits 1" "impl-review final" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 9: single-phase create-pr does not require final impl-review (fails on PR state, not reviews)"
if ! command -v gh >/dev/null 2>&1; then
  echo "SKIP: gh CLI not available"
else
  setup_plan_dir
  write_single_phase_plan "create-pr" "Complete"
  printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
  assert_fail "single-phase create-pr fails on PR state not final impl-review" "no PR found\|no final PR found\|gh pr list failed" \
    "$VALIDATE" --check-workflow "$TMPDIR/plan.json"
fi

echo "Test 9b: single-phase create-pr fails when missing phase impl-review"
setup_plan_dir
write_single_phase_plan "create-pr" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "single-phase create-pr without impl-review exits 1" "impl-review phase-a" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "=== error handling ==="

echo "Test 10: missing workflow field"
setup_plan_dir
write_single_phase_plan "plan-only"
jq 'del(.workflow)' "$TMPDIR/plan.json" > "$TMPDIR/plan.json.tmp" && mv "$TMPDIR/plan.json.tmp" "$TMPDIR/plan.json"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "missing workflow field exits 1" "missing workflow field" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
