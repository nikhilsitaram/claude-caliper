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
MOCK_BIN=$(mktemp -d)
ln -s "$FIXTURES/gh-mock.sh" "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
trap 'rm -rf "$TMPDIR" "$MOCK_BIN"' EXIT

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
echo "=== pr-create workflow ==="

echo "Test 5: pr-create fails when plan not Complete"
setup_plan_dir
write_single_phase_plan "pr-create" "In Development"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "pr-create with plan In Development exits 1" "plan status is" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 6: pr-create fails missing impl-review"
setup_plan_dir
write_single_phase_plan "pr-create" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "pr-create missing impl-review for phase-a exits 1" "impl-review phase-a" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "=== pr-merge workflow ==="

echo "Test 7: pr-merge requires PR merged"
setup_plan_dir
write_single_phase_plan "pr-merge" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
GH_MOCK_PR_COUNT=0 assert_fail "pr-merge with all reviews but no merged PR exits 1" "PR not merged\|no PR found\|gh pr list failed" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "=== multi-phase specifics ==="

echo "Test 8: multi-phase pr-create requires final impl-review"
setup_plan_dir
write_two_phase_plan "pr-create" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-b","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "pr-create two-phase without final impl-review exits 1" "impl-review final" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 9: single-phase pr-create does not require final impl-review (fails on PR state, not reviews)"
setup_plan_dir
write_single_phase_plan "pr-create" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
GIT_TMPDIR=$(mktemp -d)
git -C "$GIT_TMPDIR" init -b test-no-pr-branch >/dev/null 2>&1
git -C "$GIT_TMPDIR" commit --allow-empty -m "init" >/dev/null 2>&1
pushd "$GIT_TMPDIR" >/dev/null
GH_MOCK_PR_COUNT=0 assert_fail "single-phase pr-create fails on PR state not final impl-review" "no PR found\|no final PR found\|gh pr list failed" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"
popd >/dev/null
rm -rf "$GIT_TMPDIR"

echo "Test 9b: single-phase pr-create fails when missing phase impl-review"
setup_plan_dir
write_single_phase_plan "pr-create" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "single-phase pr-create without impl-review exits 1" "impl-review phase-a" \
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
