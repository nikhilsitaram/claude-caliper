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

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Test 1: Plan without supervision field passes"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
cp "$FIXTURES/valid-plan/plan.json" "$TMPDIR/plan.json"
assert_pass "plan without supervision field passes schema check" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo "Test 2: Plan with legacy supervision field still passes (field is ignored)"
rm -rf "${TMPDIR:?}/"*
cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/"
jq '. + {"supervision": {"orchestrator_poll_seconds": 60, "dispatcher_poll_seconds": 30, "max_intervention_attempts": 2}}' \
  "$FIXTURES/valid-plan/plan.json" > "$TMPDIR/plan.json"
assert_pass "plan with legacy supervision field passes (ignored)" \
  "$VALIDATE" --schema "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
