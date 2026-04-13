#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/bin/validate-design"
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

assert_pass "valid design passes all checks" "$VALIDATE" --check "$FIXTURES/valid-design.md"
assert_fail "missing section detected" "missing_section" "$VALIDATE" --check "$FIXTURES/missing-section.md"
assert_fail "out-of-order sections detected" "section_order" "$VALIDATE" --check "$FIXTURES/bad-order.md"
assert_fail "empty section detected" "empty_section" "$VALIDATE" --check "$FIXTURES/empty-section.md"
assert_fail "cross-reference mismatch detected" "cross_ref_mismatch" "$VALIDATE" --check "$FIXTURES/cross-ref-mismatch.md"
assert_fail "non-goal without rationale detected" "non_goal_rationale" "$VALIDATE" --check "$FIXTURES/no-rationale.md"
assert_fail "missing scope estimate phase count" "does not mention phase count" "$VALIDATE" --check "$FIXTURES/missing-scope.md"
assert_fail "missing scope estimate task count" "does not mention task count" "$VALIDATE" --check "$FIXTURES/missing-task-count.md"
assert_pass "multi-line non-goal rationale accepted" "$VALIDATE" --check "$FIXTURES/multiline-rationale.md"
assert_fail "missing path after --check" "requires a path argument" "$VALIDATE" --check

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
