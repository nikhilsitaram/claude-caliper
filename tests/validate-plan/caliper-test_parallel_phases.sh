#!/usr/bin/env bash
# Phase-level scheduling (gh issue #316): orchestrate starts every phase whose
# depends_on phases have merged, and merges phase PRs in letter order. Covers
# --ready-phases, --mark-merged, --check-merge-order, the `merged` marker's
# schema rules, and the cross-phase dependency / sibling-overlap checks.
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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected to contain '$needle', got '$haystack')"
    ((FAIL++)) || true
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected not to contain '$needle', got '$haystack')"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
PLAN="$TMPDIR/plan.json"
COMPLETE_STATUS="Complete (2026-01-01)"

# Base fixture: A (A1, A2), B depends_on [A] (B1 depends_on A2).
reset_fixture() {
  rm -rf "${TMPDIR:?}/"*
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
}

mutate() {
  jq "$1" "$PLAN" > "$TMPDIR/p.json" && mv "$TMPDIR/p.json" "$PLAN"
}

# Sibling fixture: adds phase C depends_on [A] with C1 depends_on A1, so B and C
# both depend only on A — the shape #316 ran by hand.
add_sibling_c() {
  mutate '.phases += [(.phases[1]
    | .letter = "C" | .name = "Sibling"
    | .tasks = [(.tasks[0] | .id = "C1" | .depends_on = ["A1"]
        | .files = {create: ["src/report.ts"], modify: [], test: ["tests/report.test.ts"]})])]'
}

# Captures stdout/stderr/exit of one validate-plan call into OUT/ERR/RC
run() {
  RC=0
  OUT=$("$VALIDATE" "$@" 2>"$TMPDIR/err") || RC=$?
  ERR=$(cat "$TMPDIR/err")
}

# --- --ready-phases ---------------------------------------------------------

reset_fixture
run --ready-phases "$PLAN"
assert_eq "fresh plan: only the dependency-free phase is ready" "A" "$OUT"
assert_eq "fresh plan: exit 0" "0" "$RC"

reset_fixture
mutate '.status = "In Development" | .phases[0].status = "'"$COMPLETE_STATUS"'" | .phases[0].tasks[].status = "complete"'
run --ready-phases "$PLAN"
assert_eq "Complete but unmerged dependency does not release its dependent" "" "$OUT"

mutate '.phases[0].merged = true'
run --ready-phases "$PLAN"
assert_eq "merged dependency releases its dependent; merged phase not listed" "B" "$OUT"

reset_fixture
add_sibling_c
mutate '.status = "In Development" | .phases[0].status = "'"$COMPLETE_STATUS"'" | .phases[0].tasks[].status = "complete" | .phases[0].merged = true'
run --ready-phases "$PLAN"
assert_eq "siblings depending only on a merged phase are ready together" "B
C" "$OUT"

mutate '.phases[1].status = "In Progress"'
run --ready-phases "$PLAN"
assert_eq "an In Progress phase stays listed so a resumed run picks it up" "B
C" "$OUT"

mutate '.phases[1].status = "'"$COMPLETE_STATUS"'" | .phases[1].tasks[].status = "complete"'
run --ready-phases "$PLAN"
assert_eq "a Complete (waiting-to-merge) phase is no longer listed" "C" "$OUT"

reset_fixture
run --ready-phases "$PLAN" --phase A
assert_eq "--ready-phases rejects extra arguments" "2" "$RC"

# --- --mark-merged ----------------------------------------------------------

reset_fixture
run --mark-merged "$PLAN" --phase A
assert_eq "mark-merged refuses a phase that isn't Complete" "1" "$RC"
assert_contains "mark-merged refusal names the status" "Not Started" "$ERR"
assert_eq "refused mark-merged leaves plan untouched" "null" "$(jq '.phases[0].merged' "$PLAN")"

mutate '.status = "In Development" | .phases[0].status = "'"$COMPLETE_STATUS"'" | .phases[0].tasks[].status = "complete"'
run --mark-merged "$PLAN" --phase A
assert_eq "mark-merged on a Complete phase exits 0" "0" "$RC"
assert_eq "mark-merged records merged: true" "true" "$(jq '.phases[0].merged' "$PLAN")"
assert_contains "plan.md shows the merged marker" "**Status:** $COMPLETE_STATUS (merged)" "$(cat "$TMPDIR/plan.md")"

run --mark-merged "$PLAN" --phase A
assert_eq "mark-merged is idempotent" "0" "$RC"

run --mark-merged "$PLAN" --phase Z
assert_eq "mark-merged on an unknown phase fails" "1" "$RC"
assert_contains "unknown phase error" "phase_not_found" "$ERR"

run --mark-merged "$PLAN"
assert_eq "mark-merged without --phase is a usage error" "2" "$RC"

run --update-status "$PLAN" --phase A --status "In Progress"
assert_eq "a merged phase can't be moved back out of Complete" "1" "$RC"
assert_contains "status refusal explains why" "merged" "$ERR"

printf '[{"type":"impl-review","scope":"phase-a","pass":1,"verdict":"pass","remaining":0}]' > "$TMPDIR/reviews.json"
run --update-status "$PLAN" --phase A --status "Complete (2026-02-02)"
assert_eq "a merged phase can still have its Complete date rewritten" "0" "$RC"

# --- --check-merge-order ----------------------------------------------------

reset_fixture
add_sibling_c
mutate '.status = "In Development" | .phases[0].status = "'"$COMPLETE_STATUS"'" | .phases[0].tasks[].status = "complete"'
run --check-merge-order "$PLAN" --phase A
assert_eq "first phase may always merge" "0" "$RC"

run --check-merge-order "$PLAN" --phase C
assert_eq "C must wait while earlier phases are unmerged" "1" "$RC"
assert_contains "merge-order error names the unmerged earlier phases" "A, B" "$ERR"

mutate '.phases[0].merged = true'
run --check-merge-order "$PLAN" --phase C
assert_eq "C still waits on unmerged sibling B" "1" "$RC"
assert_not_contains "merged A is no longer named" "A," "$ERR"

mutate '.phases[1].status = "'"$COMPLETE_STATUS"'" | .phases[1].tasks[].status = "complete" | .phases[1].merged = true'
run --check-merge-order "$PLAN" --phase C
assert_eq "C may merge once every earlier phase has merged" "0" "$RC"

run --check-merge-order "$PLAN" --phase Z
assert_eq "check-merge-order on unknown phase fails" "1" "$RC"

# --- schema: merged marker ---------------------------------------------------

reset_fixture
mutate '.phases[0].merged = "yes"'
run --schema "$PLAN"
assert_eq "non-boolean merged fails schema" "1" "$RC"
assert_contains "non-boolean merged error code" "invalid_merged" "$ERR"

reset_fixture
mutate '.phases[0].merged = true'
run --schema "$PLAN"
assert_eq "merged on a non-Complete phase fails schema" "1" "$RC"
assert_contains "merged-without-Complete error code" "invalid_merged" "$ERR"

# --- schema: cross-phase task deps need a phase dependency -------------------

reset_fixture
add_sibling_c
run --schema "$PLAN"
assert_eq "sibling fixture is valid" "0" "$RC"

mutate '.phases[2].tasks[0].depends_on = ["B1"]'
run --schema "$PLAN"
assert_eq "task dep on a phase its phase doesn't depend on fails schema" "1" "$RC"
assert_contains "cross-phase dep error code" "phase_dependency_missing" "$ERR"
assert_contains "cross-phase dep error names task, dep and phases" "C1 depends_on B1" "$ERR"

reset_fixture
add_sibling_c
mutate '.phases[2].depends_on = ["B"]'
run --schema "$PLAN"
assert_eq "transitive phase dependency (C->B->A) covers C1 depends_on A1" "0" "$RC"

# --- schema: sibling phase file overlap is a warning -------------------------

reset_fixture
add_sibling_c
mutate '.phases[2].tasks[0].files.modify = ["src/dashboard.ts"]'
run --schema "$PLAN"
assert_eq "sibling phases sharing a file still pass schema" "0" "$RC"
assert_contains "sibling overlap warns" "WARNING: sibling_fileset_overlap" "$ERR"
assert_contains "sibling overlap warning names the file and phases" "'src/dashboard.ts'" "$ERR"

mutate '.phases[2].depends_on = ["B"]'
run --schema "$PLAN"
assert_not_contains "phase-ordered overlap does not warn" "sibling_fileset_overlap" "$ERR"

# --- --add-dep honors phase dependencies --------------------------------------

reset_fixture
add_sibling_c
run --add-dep "$PLAN" --task C1 --depends-on B1
assert_eq "add-dep refuses a cross-phase edge its phase doesn't depend on" "1" "$RC"
assert_contains "add-dep refusal code" "phase_dependency_missing" "$ERR"
assert_eq "refused add-dep leaves deps untouched" '["A1"]' "$(jq -c '.phases[2].tasks[0].depends_on' "$PLAN")"

run --add-dep "$PLAN" --task C1 --depends-on A2
assert_eq "add-dep allows an edge into a phase dependency" "0" "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
