#!/usr/bin/env bash
# gated_on: tasks waiting on external input (another team's PR, IT grants)
# must not dispatch or advance until the user clears the gate (gh issue #290).
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
  elif echo "$output" | grep -qF "$expected_error"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected_error' in output, got: $output)"
    ((FAIL++)) || true
  fi
}

assert_json() {
  local desc="$1" filter="$2"
  if jq -e "$filter" "$TMPDIR/plan.json" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (filter failed: $filter)"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

GATE="Platform team PR #812 merged"

mutate() {
  jq "$1" "$TMPDIR/plan.json" > "$TMPDIR/p.json" && mv "$TMPDIR/p.json" "$TMPDIR/plan.json"
}

# Valid plan, active, with A1 complete so A2's only dependency is satisfied —
# A2's gate is then the only thing holding it back.
setup_gated_a2() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
  jq --arg g "$GATE" '.status = "In Development" | .phases[0].status = "In Progress"
    | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].gated_on = [$g]' \
    "$TMPDIR/plan.json" > "$TMPDIR/p.json" && mv "$TMPDIR/p.json" "$TMPDIR/plan.json"
}

echo "=== Schema ==="

setup_gated_a2
assert_pass "gated_on array of strings is valid" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

setup_gated_a2
mutate '.phases[0].tasks[1].gated_on = "not an array"'
assert_fail "gated_on string rejected" "invalid_gated_on: task A2" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

setup_gated_a2
mutate '.phases[0].tasks[1].gated_on = [""]'
assert_fail "gated_on with empty string rejected" "invalid_gated_on: task A2" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

setup_gated_a2
mutate '.phases[0].tasks[1].gated_on = [42]'
assert_fail "gated_on with non-string entry rejected" "invalid_gated_on: task A2" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "=== --check-deps ==="

setup_gated_a2
assert_fail "gated task blocked even with deps complete" "task_gated: task A2 is gated on: $GATE" \
  "$VALIDATE" --check-deps "$TMPDIR/plan.json" --task A2

setup_gated_a2
mutate '.phases[1].tasks[0].depends_on = ["A1", "A2"] | .phases[0].tasks[0].status = "pending" | .phases[1].tasks[0].gated_on = ["vendor API key"]'
blockers=$("$VALIDATE" --check-deps "$TMPDIR/plan.json" --task B1 2>&1 || true)
if [[ "$blockers" == *"depends on A1 which has status 'pending'"* \
   && "$blockers" == *"depends on A2 which has status 'pending'"* \
   && "$blockers" == *"task_gated: task B1 is gated on: vendor API key"* ]]; then
  echo "PASS: check-deps lists every unmet dependency and the open gate"
  ((PASS++)) || true
else
  echo "FAIL: check-deps should list both deps and the gate (got: $blockers)"
  ((FAIL++)) || true
fi

echo "=== --update-status ==="

setup_gated_a2
assert_fail "gated task cannot go in_progress" "cannot advance task A2" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status in_progress

setup_gated_a2
assert_fail "gated task cannot be marked done" "gated on: $GATE" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status "done"

setup_gated_a2
assert_pass "gated task can be skipped" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status skipped

echo "=== --render ==="

setup_gated_a2
"$VALIDATE" --render "$TMPDIR/plan.json"
if grep -qF -- "- Gated on: $GATE" "$TMPDIR/plan.md"; then
  echo "PASS: plan.md shows the open gate under the task"
  ((PASS++)) || true
else
  echo "FAIL: plan.md should show '- Gated on: $GATE'"
  ((FAIL++)) || true
fi

echo "=== --clear-gate ==="

setup_gated_a2
assert_pass "clear-gate succeeds" \
  "$VALIDATE" --clear-gate "$TMPDIR/plan.json" --task A2
assert_json "gated_on removed from plan.json" '.phases[0].tasks[1] | has("gated_on") | not'
if grep -qF "Gated on:" "$TMPDIR/plan.md"; then
  echo "FAIL: plan.md should drop the gate after clear-gate"
  ((FAIL++)) || true
else
  echo "PASS: clear-gate re-renders plan.md without the gate"
  ((PASS++)) || true
fi
assert_pass "check-deps passes once the gate is cleared" \
  "$VALIDATE" --check-deps "$TMPDIR/plan.json" --task A2
assert_pass "task advances once the gate is cleared" \
  "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status in_progress
assert_pass "clear-gate on an ungated task is a no-op" \
  "$VALIDATE" --clear-gate "$TMPDIR/plan.json" --task A1

setup_gated_a2
assert_fail "clear-gate on unknown task" "task_not_found" \
  "$VALIDATE" --clear-gate "$TMPDIR/plan.json" --task Z9

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
