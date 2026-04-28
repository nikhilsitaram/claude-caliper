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

assert_json() {
  local desc="$1" plan="$2" filter="$3"
  if jq -e "$filter" "$plan" > /dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (filter failed: $filter on $plan)"
    ((FAIL++)) || true
  fi
}

assert_file_contains() {
  local desc="$1" file="$2" needle="$3"
  if grep -qF "$needle" "$file"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$needle' in $file)"
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

echo "Test 1: --add-file create succeeds and re-renders plan.md"
setup_valid_plan "$TMPDIR"
assert_pass "add-file create on A1" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind create --path "src/extra.ts"
assert_json "src/extra.ts present in A1.files.create" "$TMPDIR/plan.json" \
  '.phases[0].tasks[0].files.create | index("src/extra.ts")'
assert_file_contains "plan.md re-rendered after create add" "$TMPDIR/plan.md" "A1: Create core module"

echo "Test 2: --add-file modify succeeds"
setup_valid_plan "$TMPDIR"
assert_pass "add-file modify on A1" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind modify --path "src/util.ts"
assert_json "src/util.ts present in A1.files.modify" "$TMPDIR/plan.json" \
  '.phases[0].tasks[0].files.modify | index("src/util.ts")'

echo "Test 3: --add-file test succeeds"
setup_valid_plan "$TMPDIR"
assert_pass "add-file test on A1" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind test --path "tests/extra.test.ts"
assert_json "tests/extra.test.ts present in A1.files.test" "$TMPDIR/plan.json" \
  '.phases[0].tasks[0].files.test | index("tests/extra.test.ts")'

echo "Test 4: --add-file is idempotent (re-add same path is no-op)"
setup_valid_plan "$TMPDIR"
"$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind modify --path "src/util.ts" > /dev/null 2>&1
assert_pass "re-add same path exits 0" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind modify --path "src/util.ts"
assert_json "src/util.ts appears exactly once" "$TMPDIR/plan.json" \
  '.phases[0].tasks[0].files.modify | map(select(. == "src/util.ts")) | length == 1'

echo "Test 5: --remove-file is idempotent (absent path is no-op)"
setup_valid_plan "$TMPDIR"
assert_pass "remove absent path exits 0" \
  "$VALIDATE" --remove-file "$TMPDIR/plan.json" --task A1 --kind modify --path "src/never-existed.ts"

echo "Test 6: --remove-file create succeeds and re-renders plan.md"
setup_valid_plan "$TMPDIR"
rm -f "$TMPDIR/plan.md"
assert_pass "remove existing create path" \
  "$VALIDATE" --remove-file "$TMPDIR/plan.json" --task A1 --kind create --path "src/core.ts"
assert_json "src/core.ts removed from A1.files.create" "$TMPDIR/plan.json" \
  '(.phases[0].tasks[0].files.create | index("src/core.ts")) == null'
assert_file_contains "plan.md re-rendered after create remove" "$TMPDIR/plan.md" "A1: Create core module"

echo "Test 7: --remove-file test succeeds"
setup_valid_plan "$TMPDIR"
rm -f "$TMPDIR/plan.md"
assert_pass "remove existing test path" \
  "$VALIDATE" --remove-file "$TMPDIR/plan.json" --task A1 --kind test --path "tests/core.test.ts"
assert_json "tests/core.test.ts removed from A1.files.test" "$TMPDIR/plan.json" \
  '(.phases[0].tasks[0].files.test | index("tests/core.test.ts")) == null'
assert_file_contains "plan.md re-rendered after test remove" "$TMPDIR/plan.md" "A1: Create core module"

echo "Test 8: invalid kind is rejected"
setup_valid_plan "$TMPDIR"
assert_fail "add-file with --kind bogus" "invalid_kind" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind bogus --path "src/x.ts"

echo "Test 9: unknown task is rejected"
setup_valid_plan "$TMPDIR"
assert_fail "add-file on Z9" "task_not_found" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task Z9 --kind create --path "src/x.ts"

echo "Test 10: completed task rejects --add-file"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/p.json" && mv "$TMPDIR/p.json" "$TMPDIR/plan.json"
assert_fail "add-file on complete task" "cannot_modify_files" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind create --path "src/x.ts"

echo "Test 11: skipped task rejects --add-file"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "skipped"' "$TMPDIR/plan.json" > "$TMPDIR/p.json" && mv "$TMPDIR/p.json" "$TMPDIR/plan.json"
assert_fail "add-file on skipped task" "cannot_modify_files" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind create --path "src/x.ts"

echo "Test 12: completed task rejects --remove-file"
setup_valid_plan "$TMPDIR"
jq '.phases[0].tasks[0].status = "complete"' "$TMPDIR/plan.json" > "$TMPDIR/p.json" && mv "$TMPDIR/p.json" "$TMPDIR/plan.json"
assert_fail "remove-file on complete task" "cannot_modify_files" \
  "$VALIDATE" --remove-file "$TMPDIR/plan.json" --task A1 --kind create --path "src/core.ts"

echo "Test 13: cross-kind conflict on same task is rejected"
setup_valid_plan "$TMPDIR"
assert_fail "add to modify when already in create on same task" "cross_kind_conflict" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A1 --kind modify --path "src/core.ts"

echo "Test 14: per-phase overlap is rejected (same kind, different task)"
setup_valid_plan "$TMPDIR"
assert_fail "add to A2.create path already in A1.create" "fileset_overlap_add" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A2 --kind create --path "src/core.ts"

echo "Test 15: per-phase overlap is rejected (different kinds, different tasks)"
setup_valid_plan "$TMPDIR"
assert_fail "add to A2.modify path already in A1.create" "fileset_overlap_add" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task A2 --kind modify --path "src/core.ts"

echo "Test 16: global create duplication is rejected (cross-phase)"
setup_valid_plan "$TMPDIR"
assert_fail "add to B1.create path already in A1.create" "duplicate_create_path_add" \
  "$VALIDATE" --add-file "$TMPDIR/plan.json" --task B1 --kind create --path "src/core.ts"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
