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
  elif echo "$output" | grep -q -- "$expected_error"; then
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
# Branch-dependent cases run from a scratch repo on a known branch, so they
# don't depend on the checkout the suite runs from (an integrate/* one takes
# the phase-PR path and prints other messages).
CWD_BRANCH="main"
CWD_REPO=$(mktemp -d)
git -C "$CWD_REPO" init -b "$CWD_BRANCH" >/dev/null 2>&1
git -C "$CWD_REPO" -c user.email="test@test.com" -c user.name="Test" commit --allow-empty -m "init" >/dev/null 2>&1
from_cwd_repo() { (cd "$CWD_REPO" && "$@"); }
CWD_INTEGRATE_BRANCH="integrate/cwd-checkout"
CWD_INTEGRATE_REPO=$(mktemp -d)
git -C "$CWD_INTEGRATE_REPO" init -b "$CWD_INTEGRATE_BRANCH" >/dev/null 2>&1
git -C "$CWD_INTEGRATE_REPO" -c user.email="test@test.com" -c user.name="Test" commit --allow-empty -m "init" >/dev/null 2>&1
from_cwd_integrate_repo() { (cd "$CWD_INTEGRATE_REPO" && "$@"); }
trap 'rm -rf "$TMPDIR" "$MOCK_BIN" "$CWD_REPO" "$CWD_INTEGRATE_REPO"' EXIT

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
echo "=== orchestrate workflow ==="

echo "Test 4a: orchestrate passes with all reviews and plan Complete"
setup_plan_dir
write_single_phase_plan "orchestrate" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "orchestrate with all reviews and Complete exits 0" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 4b: orchestrate fails when plan not Complete"
setup_plan_dir
write_single_phase_plan "orchestrate" "In Development"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "orchestrate with plan In Development exits 1" "plan status is" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 4c: orchestrate fails missing impl-review"
setup_plan_dir
write_single_phase_plan "orchestrate" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "orchestrate missing impl-review exits 1" "impl-review phase-a" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 4d: orchestrate does not require PR (no gh calls)"
setup_plan_dir
write_single_phase_plan "orchestrate" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
GH_MOCK_PR_COUNT=0 assert_pass "orchestrate passes without any PR" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 4e: multi-phase orchestrate requires final impl-review"
setup_plan_dir
write_two_phase_plan "orchestrate" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-b","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "orchestrate two-phase without final impl-review exits 1" "impl-review final" \
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

echo "Test 7a: pr-merge fails when the PR is open but not merged"
setup_plan_dir
write_single_phase_plan "pr-merge" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
GH_MOCK_PR_COUNT=1 GH_MOCK_MERGED_COUNT=0 assert_fail "pr-merge with open unmerged PR exits 1" "PR not merged" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "=== pr-ready workflow ==="

echo "Test 7b: pr-ready passes with an open, unmerged PR"
setup_plan_dir
write_single_phase_plan "pr-ready" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
GH_MOCK_PR_COUNT=1 GH_MOCK_MERGED_COUNT=0 assert_pass "pr-ready with open unmerged PR exits 0" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 7c: pr-ready fails when no PR exists"
setup_plan_dir
write_single_phase_plan "pr-ready" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
GH_MOCK_PR_COUNT=0 assert_fail "pr-ready with no PR exits 1" "no PR found" \
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
GH_MOCK_PR_COUNT=0 assert_fail "single-phase pr-create fails on PR state not final impl-review" "no PR found\|no final PR found\|gh pr list failed" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 9a: branch resolved from CWD, not plan dir (PR #210)"
GIT_PLAN_DIR=$(mktemp -d)
git -C "$GIT_PLAN_DIR" init -b fix/my-feature >/dev/null 2>&1
git -C "$GIT_PLAN_DIR" -c user.email="test@test.com" -c user.name="Test" commit --allow-empty -m "init" >/dev/null 2>&1
write_single_phase_plan "pr-create" "Complete"
cp "$TMPDIR/plan.json" "$GIT_PLAN_DIR/plan.json"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$GIT_PLAN_DIR/reviews.json"
GH_MOCK_PR_COUNT=0 assert_fail "branch from CWD not plan dir" "no PR found for $CWD_BRANCH" \
  from_cwd_repo "$VALIDATE" --check-workflow "$GIT_PLAN_DIR/plan.json"
rm -rf "$GIT_PLAN_DIR"

echo "Test 9b: single-phase pr-create fails when missing phase impl-review"
setup_plan_dir
write_single_phase_plan "pr-create" "Complete"
printf '[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_fail "single-phase pr-create without impl-review exits 1" "impl-review phase-a" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo ""
echo "=== --branch: check a branch other than the CWD's (gh #338) ==="
# After pr-merge cleans up, the CWD is back on the default branch; the gate must
# still find the merged PR for the branch that was merged. GH_MOCK_ONLY_BRANCH
# makes the mock answer only for that branch, so a pass proves which one was asked.
GONE_BRANCH="feat/merged-and-gone"
GONE_INTEGRATE="integrate/merged-and-gone"
SINGLE_REVIEWS='[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]'
MULTI_REVIEWS='[{"type":"design-review","scope":"design","verdict":"pass","remaining":0},{"type":"plan-review","scope":"plan","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-b","verdict":"pass","remaining":0},{"type":"impl-review","scope":"final","verdict":"pass","remaining":0}]'

echo "Test 11a: single-phase pr-merge without --branch checks the CWD branch and fails"
setup_plan_dir
write_single_phase_plan "pr-merge" "Complete"
printf '%s' "$SINGLE_REVIEWS" > "$TMPDIR/reviews.json"
GH_MOCK_ONLY_BRANCH="$GONE_BRANCH" GH_MOCK_PR_COUNT=1 assert_fail "default resolves the CWD branch" "no PR found for $CWD_BRANCH" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 11b: single-phase pr-merge with --branch finds the merged PR"
GH_MOCK_ONLY_BRANCH="$GONE_BRANCH" GH_MOCK_PR_COUNT=1 assert_pass "--branch <feature> passes from another branch" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch "$GONE_BRANCH"

echo "Test 11c: single-phase pr-merge with --branch names that branch when unmerged"
GH_MOCK_ONLY_BRANCH="$GONE_BRANCH" GH_MOCK_PR_COUNT=1 GH_MOCK_MERGED_COUNT=0 assert_fail "--branch used in the merged check" "PR not merged for $GONE_BRANCH" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch "$GONE_BRANCH"

echo "Test 11d: multi-phase pr-merge without --branch or integration_branch checks the CWD branch"
setup_plan_dir
write_two_phase_plan "pr-merge" "Complete"
printf '%s' "$MULTI_REVIEWS" > "$TMPDIR/reviews.json"
GH_MOCK_ONLY_BRANCH="$GONE_INTEGRATE" GH_MOCK_PR_COUNT=1 assert_fail "default misses the integration branch" "no PR found for $CWD_BRANCH" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 11e: multi-phase pr-merge with --branch integrate/* runs the phase and final PR checks"
GH_MOCK_ONLY_BRANCH="$GONE_INTEGRATE" GH_MOCK_PR_COUNT=1 assert_pass "--branch integrate/<feature> passes" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch "$GONE_INTEGRATE"

echo "Test 11e2: --branch integrate/* names that branch when the final PR is unmerged"
GH_MOCK_ONLY_BRANCH="$GONE_INTEGRATE" GH_MOCK_PR_COUNT=1 GH_MOCK_MERGED_COUNT=0 assert_fail "--branch used in the final merged check" "final PR not merged for $GONE_INTEGRATE" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch "$GONE_INTEGRATE"

echo "Test 11f: --branch integrate/* reports missing phase PRs against that branch"
GH_MOCK_PR_COUNT=0 assert_fail "phase PR check uses --branch as base" "no PR found for phase-a → $GONE_INTEGRATE" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch "$GONE_INTEGRATE"

echo "Test 11g: --branch needs a value"
assert_fail "--branch with no value exits non-zero" "--branch requires a branch name" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch
assert_fail "--branch with an empty value exits non-zero" "--branch requires a branch name" \
  "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch ""

echo "Test 11h: --branch is refused outside --check-workflow"
assert_fail "--branch with --consistency exits non-zero" "--branch only applies to --check-workflow" \
  "$VALIDATE" --consistency "$TMPDIR/plan.json" --branch "$GONE_BRANCH"

echo ""
echo "=== integration_branch fallback when --branch is omitted ==="

set_integration_branch() {
  jq --arg ib "$1" '.integration_branch = $ib' "$TMPDIR/plan.json" > "$TMPDIR/plan.json.tmp" && mv "$TMPDIR/plan.json.tmp" "$TMPDIR/plan.json"
}

echo "Test 12a: off an integrate/* checkout, the plan's integration_branch is checked"
setup_plan_dir
write_two_phase_plan "pr-merge" "Complete"
printf '%s' "$MULTI_REVIEWS" > "$TMPDIR/reviews.json"
set_integration_branch "$GONE_INTEGRATE"
GH_MOCK_ONLY_BRANCH="$GONE_INTEGRATE" GH_MOCK_PR_COUNT=1 assert_pass "falls back to integration_branch from the default branch" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 12b: the fallback runs the integrate/* phase-PR checks"
GH_MOCK_PR_COUNT=0 assert_fail "phase PR check uses integration_branch as base" "no PR found for phase-a → $GONE_INTEGRATE" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 12c: an integrate/* CWD branch wins over integration_branch"
GH_MOCK_ONLY_BRANCH="$CWD_INTEGRATE_BRANCH" GH_MOCK_PR_COUNT=1 assert_pass "integrate/* CWD branch is checked" \
  from_cwd_integrate_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json"

echo "Test 12d: --branch matching integration_branch passes"
GH_MOCK_ONLY_BRANCH="$GONE_INTEGRATE" GH_MOCK_PR_COUNT=1 assert_pass "--branch equal to integration_branch" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch "$GONE_INTEGRATE"

echo "Test 12e: --branch contradicting integration_branch is refused"
GH_MOCK_PR_COUNT=1 assert_fail "--branch differs from integration_branch" "contradicts plan.json's integration_branch '$GONE_INTEGRATE'" \
  from_cwd_repo "$VALIDATE" --check-workflow "$TMPDIR/plan.json" --branch "$GONE_BRANCH"

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
