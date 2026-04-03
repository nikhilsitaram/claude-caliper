#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/bin/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

reset_fixture() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
}

reset_fixture
jq '.status = "In Development" | .phases[0].status = "In Progress"' "$TMPDIR/plan.json" > "$TMPDIR/plan_tmp.json" && mv "$TMPDIR/plan_tmp.json" "$TMPDIR/plan.json"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status in_progress
actual=$(jq -r '.phases[0].tasks[0].status' "$TMPDIR/plan.json")
assert_eq "task status updated to in_progress" "in_progress" "$actual"

if grep -q '\[ \] A1' "$TMPDIR/plan.md"; then
  echo "PASS: in_progress task renders as [ ]"
  ((PASS++)) || true
else
  echo "FAIL: in_progress task should render as [ ]"
  ((FAIL++)) || true
fi

printf '[{"type":"task-review","scope":"A1","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status complete
if grep -q '\[x\] A1' "$TMPDIR/plan.md"; then
  echo "PASS: complete task renders as [x]"
  ((PASS++)) || true
else
  echo "FAIL: complete task should render as [x]"
  ((FAIL++)) || true
fi

reset_fixture
jq '.status = "In Development"' "$TMPDIR/plan.json" > "$TMPDIR/plan_tmp.json" && mv "$TMPDIR/plan_tmp.json" "$TMPDIR/plan.json"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "In Progress"
actual=$(jq -r '.phases[0].status' "$TMPDIR/plan.json")
assert_eq "phase status updated" "In Progress" "$actual"

if grep -q 'In Progress' "$TMPDIR/plan.md"; then
  echo "PASS: phase status in plan.md"
  ((PASS++)) || true
else
  echo "FAIL: phase status not in plan.md"
  ((FAIL++)) || true
fi

reset_fixture
"$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "In Development"
actual=$(jq -r '.status' "$TMPDIR/plan.json")
assert_eq "plan status updated" "In Development" "$actual"

reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --task Z99 --status complete 2>/dev/null; then
  echo "FAIL: invalid task ID should fail"
  ((FAIL++)) || true
else
  echo "PASS: invalid task ID rejected"
  ((PASS++)) || true
fi

reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status bogus 2>/dev/null; then
  echo "FAIL: invalid task status should fail"
  ((FAIL++)) || true
else
  echo "PASS: invalid task status rejected"
  ((PASS++)) || true
fi

reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "bogus" 2>/dev/null; then
  echo "FAIL: invalid phase status should fail"
  ((FAIL++)) || true
else
  echo "PASS: invalid phase status rejected"
  ((PASS++)) || true
fi

reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --phase Z --status "In Progress" 2>/dev/null; then
  echo "FAIL: invalid phase letter should fail"
  ((FAIL++)) || true
else
  echo "PASS: invalid phase letter rejected"
  ((PASS++)) || true
fi

reset_fixture
if "$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "bogus" 2>/dev/null; then
  echo "FAIL: invalid plan status should fail"
  ((FAIL++)) || true
else
  echo "PASS: invalid plan status rejected"
  ((PASS++)) || true
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
