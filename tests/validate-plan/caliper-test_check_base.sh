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

echo "=== --check-base tests ==="

init_git_repo() {
  local dir="$1"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.email="test@test.com" -c user.name="Test" commit --allow-empty -m "init" -q
}

# shellcheck disable=SC2329
run_in_dir() {
  (cd "$1" && shift && "$@")
}

echo "Test 1: Feature branch without integration_branch passes"
setup_valid_plan "$TMPDIR"
rm -rf "$TMPDIR/.git"
init_git_repo "$TMPDIR"
git -C "$TMPDIR" checkout -b feat/test -q 2>/dev/null
assert_pass "feature branch passes" \
  run_in_dir "$TMPDIR" "$VALIDATE" --check-base "$TMPDIR/plan.json"

echo "Test 2: main branch without integration_branch fails"
setup_valid_plan "$TMPDIR"
rm -rf "$TMPDIR/.git"
init_git_repo "$TMPDIR"
assert_fail "main branch fails" "base_branch_mismatch" \
  run_in_dir "$TMPDIR" "$VALIDATE" --check-base "$TMPDIR/plan.json"

echo "Test 3: integration_branch matches current branch passes"
setup_valid_plan "$TMPDIR"
rm -rf "$TMPDIR/.git"
init_git_repo "$TMPDIR"
git -C "$TMPDIR" checkout -b integrate/my-feature -q 2>/dev/null
jq '.integration_branch = "integrate/my-feature"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_pass "integration branch matches" \
  run_in_dir "$TMPDIR" "$VALIDATE" --check-base "$TMPDIR/plan.json"

echo "Test 4: integration_branch doesn't match current branch fails"
setup_valid_plan "$TMPDIR"
rm -rf "$TMPDIR/.git"
init_git_repo "$TMPDIR"
git -C "$TMPDIR" checkout -b feat/wrong -q 2>/dev/null
jq '.integration_branch = "integrate/my-feature"' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "integration branch mismatch" "base_branch_mismatch" \
  run_in_dir "$TMPDIR" "$VALIDATE" --check-base "$TMPDIR/plan.json"

echo "Test 5: empty integration_branch fails"
setup_valid_plan "$TMPDIR"
rm -rf "$TMPDIR/.git"
init_git_repo "$TMPDIR"
git -C "$TMPDIR" checkout -b feat/test -q 2>/dev/null
jq '.integration_branch = ""' "$TMPDIR/plan.json" > "$TMPDIR/plan2.json" && mv "$TMPDIR/plan2.json" "$TMPDIR/plan.json"
assert_fail "empty integration_branch fails" "base_branch_mismatch" \
  run_in_dir "$TMPDIR" "$VALIDATE" --check-base "$TMPDIR/plan.json"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
