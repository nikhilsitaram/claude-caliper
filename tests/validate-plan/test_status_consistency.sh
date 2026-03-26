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

echo "Test 1: Phase marked Complete with all tasks complete passes"
setup_valid_plan "$TMPDIR"
jq '.status = "In Development" | .phases[0].status = "Complete (2026-03-24)" | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
echo "# A2 Completion" > "$TMPDIR/phase-a/a2-completion.md"
echo '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "phase complete with all tasks complete" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Phase marked Complete with a task still pending fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].status = "Complete (2026-03-24)" | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "pending"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
assert_fail "phase complete with pending task" "status_inconsistency" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 3: Plan marked Complete with all phases complete passes"
setup_valid_plan "$TMPDIR"
jq '.status = "Complete" | .phases[0].status = "Complete (2026-03-24)" | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "complete" | .phases[1].status = "Complete (2026-03-24)" | .phases[1].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a" "$TMPDIR/phase-b"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
echo "# A2 Completion" > "$TMPDIR/phase-a/a2-completion.md"
echo "# B1 Completion" > "$TMPDIR/phase-b/b1-completion.md"
echo '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0},{"type":"impl-review","scope":"phase-b","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
assert_pass "plan complete with all phases complete" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 4: Plan marked Complete with a phase still Not Started fails"
setup_valid_plan "$TMPDIR"
jq '.status = "Complete" | .phases[0].status = "Complete (2026-03-24)" | .phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
echo "# A2 Completion" > "$TMPDIR/phase-a/a2-completion.md"
assert_fail "plan complete with not-started phase" "status_inconsistency" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 5: Task marked complete with completion file present passes"
setup_valid_plan "$TMPDIR"
jq '.status = "In Development" | .phases[0].status = "In Progress" | .phases[0].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
assert_pass "task complete with completion file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 6: Task marked complete without completion file fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "task complete without completion file" "missing_task_completion_file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 7: Orphaned .md file in phase directory fails"
setup_valid_plan "$TMPDIR"
echo "# Orphan" > "$TMPDIR/phase-a/orphan.md"
assert_fail "orphaned md file in phase directory" "orphaned_task_file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 8: Files listed in files.create exist on disk when task is complete passes"
setup_valid_plan "$TMPDIR"
jq '.status = "In Development" | .phases[0].status = "In Progress" | .phases[0].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
git -C "$TMPDIR" init -q 2>/dev/null || true
mkdir -p "$TMPDIR/src"
echo "// core" > "$TMPDIR/src/core.ts"
assert_pass "files.create exist on disk for complete task" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 9: Files listed in files.create missing on disk when task is complete fails"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
mkdir -p "$TMPDIR/phase-a"
echo "# A1 Completion" > "$TMPDIR/phase-a/a1-completion.md"
git -C "$TMPDIR" init -q 2>/dev/null || true
assert_fail "files.create missing on disk for complete task" "missing_created_file" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
