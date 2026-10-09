#!/usr/bin/env bash
# --ready lists the dispatchable tasks (pending, deps complete/skipped, no open
# gated_on) so the orchestrate lead doesn't loop --check-deps per task (gh issue #290).
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

# Fixture: A1 (no deps), A2 (depends_on A1), B1 (depends_on A2).
reset_fixture() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
}

mutate() {
  jq "$1" "$TMPDIR/plan.json" > "$TMPDIR/p.json" && mv "$TMPDIR/p.json" "$TMPDIR/plan.json"
}

# Captures stdout/stderr/exit of one --ready call into OUT/ERR/RC
run_ready() {
  RC=0
  OUT=$("$VALIDATE" --ready "$TMPDIR/plan.json" "$@" 2>"$TMPDIR/err") || RC=$?
  ERR=$(cat "$TMPDIR/err")
}

reset_fixture
run_ready
assert_eq "fresh plan: only the dependency-free task is ready" "A1" "$OUT"
assert_eq "fresh plan: exit 0" "0" "$RC"

reset_fixture
mutate '.phases[0].tasks[0].status = "complete"'
run_ready
assert_eq "A1 complete: A2 becomes ready, A1 no longer listed" "A2" "$OUT"

reset_fixture
mutate '.phases[0].tasks[0].status = "skipped"'
run_ready
assert_eq "skipped dependency satisfies readiness" "A2" "$OUT"

reset_fixture
mutate '.phases[0].tasks[0].status = "in_progress"'
run_ready
assert_eq "in-flight task is not re-listed and blocks its dependent" "" "$OUT"
assert_eq "nothing ready still exits 0" "0" "$RC"

reset_fixture
mutate '.phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].status = "complete"'
run_ready --phase A
assert_eq "--phase A excludes ready tasks in other phases" "" "$OUT"
run_ready --phase B
assert_eq "--phase B lists B1 once A2 is complete" "B1" "$OUT"
run_ready
assert_eq "no --phase lists ready tasks across all phases" "B1" "$OUT"

reset_fixture
mutate '.phases[0].tasks[0].status = "complete" | .phases[0].tasks[1].gated_on = ["IT grant for prod read access"]'
run_ready
assert_eq "gated task is withheld from stdout" "" "$OUT"
if [[ "$ERR" == *"GATED: A2"*"IT grant for prod read access"* ]]; then
  echo "PASS: gated task reported on stderr with its gate"
  ((PASS++)) || true
else
  echo "FAIL: gated task should be reported on stderr (got: $ERR)"
  ((FAIL++)) || true
fi
assert_eq "gated-only phase still exits 0" "0" "$RC"

reset_fixture
mutate '.phases[0].tasks[0].gated_on = ["vendor API key"]'
run_ready
if [[ "$ERR" != *"A2"* ]]; then
  echo "PASS: tasks blocked behind a gated dependency aren't reported as gated"
  ((PASS++)) || true
else
  echo "FAIL: only the gated root should be reported (got: $ERR)"
  ((FAIL++)) || true
fi

reset_fixture
run_ready --phase Z
assert_eq "unknown phase exits 1" "1" "$RC"
if [[ "$ERR" == *"phase_not_found"* ]]; then
  echo "PASS: unknown phase reports phase_not_found"
  ((PASS++)) || true
else
  echo "FAIL: unknown phase should report phase_not_found (got: $ERR)"
  ((FAIL++)) || true
fi

reset_fixture
run_ready --task A1
assert_eq "--ready rejects --task with a usage error" "2" "$RC"

# An empty, exit-0 listing means "nothing to dispatch"; a plan --ready can't
# evaluate must not masquerade as one.
reset_fixture
mutate '.phases[0].tasks[1].depends_on = "A1"'
run_ready
assert_eq "malformed plan exits non-zero" "1" "$RC"
assert_eq "malformed plan prints no partial listing" "" "$OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
