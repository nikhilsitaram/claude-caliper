#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/bin/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    ((FAIL++)) || true
  fi
}

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
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
( cd "$TMPDIR" && git init -q 2>/dev/null ) || true
mkdir -p "$TMPDIR/src" "$TMPDIR/tests"
touch "$TMPDIR/src/core.ts" "$TMPDIR/src/validate.ts" "$TMPDIR/src/dashboard.ts"
touch "$TMPDIR/tests/core.test.ts" "$TMPDIR/tests/validate.test.ts" "$TMPDIR/tests/dashboard.test.ts"
cd "$TMPDIR"

check "initial schema validation" "$VALIDATE" --schema "$TMPDIR/plan.json"

rm -f "$TMPDIR/plan.md"
check "initial render" "$VALIDATE" --render "$TMPDIR/plan.json"
check "plan.md exists after render" test -f "$TMPDIR/plan.md"

"$VALIDATE" --update-status "$TMPDIR/plan.json" --plan --status "In Development"
assert_eq "plan status" "In Development" "$(jq -r '.status' "$TMPDIR/plan.json")"

"$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "In Progress"

# Task completion no longer requires a per-task review record (per-task review is retired) —
# reviews.json only needs to carry the phase-level impl-review record for phase completion below.
# Drive tasks the way orchestrate's dispatch loop does: dispatch what --ready
# lists, mark it in_progress, then done (stored as complete).
assert_eq "ready before any work" "A1" "$("$VALIDATE" --ready "$TMPDIR/plan.json" --phase A)"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status in_progress
assert_eq "in-flight A1 not re-listed; A2 still blocked" "" "$("$VALIDATE" --ready "$TMPDIR/plan.json" --phase A)"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A1 --status "done"
assert_eq "A2 ready once A1 is done" "A2" "$("$VALIDATE" --ready "$TMPDIR/plan.json" --phase A)"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status in_progress
"$VALIDATE" --update-status "$TMPDIR/plan.json" --task A2 --status "done"
assert_eq "phase A drained" "" "$("$VALIDATE" --ready "$TMPDIR/plan.json" --phase A)"

printf '[{"type":"impl-review","scope":"phase-a","verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
"$VALIDATE" --update-status "$TMPDIR/plan.json" --phase A --status "Complete (2026-03-19)"

assert_eq "A1 complete" "complete" "$(jq -r '.phases[0].tasks[0].status' "$TMPDIR/plan.json")"
assert_eq "A2 complete" "complete" "$(jq -r '.phases[0].tasks[1].status' "$TMPDIR/plan.json")"
check "plan.md has [x] A1" grep -q '\[x\] A1' "$TMPDIR/plan.md"
check "plan.md has [x] A2" grep -q '\[x\] A2' "$TMPDIR/plan.md"
check "plan.md has Complete" grep -q 'Complete (2026-03-19)' "$TMPDIR/plan.md"

check "schema validates after updates" "$VALIDATE" --schema "$TMPDIR/plan.json"

cp "$TMPDIR/plan.md" "$TMPDIR/plan-before.md"
"$VALIDATE" --render "$TMPDIR/plan.json"
check "render idempotent after updates" diff -q "$TMPDIR/plan-before.md" "$TMPDIR/plan.md"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
