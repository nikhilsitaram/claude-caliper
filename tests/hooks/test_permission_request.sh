#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/permission-request-accept-edits.sh"
PASS=0
FAIL=0

assert_output_contains() {
  local desc="$1" output="$2" expected="$3"
  if echo "$output" | grep -qF "$expected"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected' in output)"
    ((FAIL++)) || true
  fi
}

assert_output_empty() {
  local desc="$1" output="$2"
  if [[ -z "$output" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected empty output, got: $output)"
    ((FAIL++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Test 1: Matching sentinel returns allow+setMode JSON"
SENTINEL_DIR1="$TMPDIR/docs/plans/2026-03-20-topic"
mkdir -p "$SENTINEL_DIR1"
printf 'sess-001' > "$SENTINEL_DIR1/.design-approved"
INPUT1=$(jq -n \
  --arg cwd "$TMPDIR" \
  '{session_id: "sess-001", cwd: $cwd}')
OUTPUT1=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null)
assert_output_contains "matching sentinel returns allow behavior" "$OUTPUT1" '"behavior": "allow"'
assert_output_contains "matching sentinel returns acceptEdits mode" "$OUTPUT1" '"mode": "acceptEdits"'
assert_output_contains "matching sentinel returns session destination" "$OUTPUT1" '"destination": "session"'

echo "Test 2: Mismatched session_id produces no output (passthrough)"
SENTINEL_DIR2="$TMPDIR/docs/plans/2026-03-20-mismatch"
mkdir -p "$SENTINEL_DIR2"
printf 'sess-old' > "$SENTINEL_DIR2/.design-approved"
INPUT2=$(jq -n \
  --arg cwd "$TMPDIR" \
  '{session_id: "sess-new", cwd: $cwd}')
OUTPUT2=$(echo "$INPUT2" | bash "$HOOK" 2>/dev/null)
assert_output_empty "mismatched session_id produces no output" "$OUTPUT2"

echo "Test 3: No sentinel file produces no output (passthrough)"
INPUT3=$(jq -n \
  --arg cwd "$TMPDIR/no-sentinel-here" \
  '{session_id: "sess-001", cwd: $cwd}')
OUTPUT3=$(echo "$INPUT3" | bash "$HOOK" 2>/dev/null)
assert_output_empty "missing sentinel produces no output" "$OUTPUT3"

echo "Test 4: Worktree search path finds sentinel"
WORKTREE_SENTINEL="$TMPDIR/.claude/worktrees/my-branch/docs/plans/2026-03-20-topic"
mkdir -p "$WORKTREE_SENTINEL"
printf 'sess-wt' > "$WORKTREE_SENTINEL/.design-approved"
INPUT4=$(jq -n \
  --arg cwd "$TMPDIR" \
  '{session_id: "sess-wt", cwd: $cwd}')
OUTPUT4=$(echo "$INPUT4" | bash "$HOOK" 2>/dev/null)
assert_output_contains "worktree sentinel found via glob path" "$OUTPUT4" '"behavior": "allow"'

echo "Test 5: Direct cwd path works (cwd IS the worktree)"
DIRECT_SENTINEL="$TMPDIR/docs/plans/2026-03-20-direct"
mkdir -p "$DIRECT_SENTINEL"
printf 'sess-direct' > "$DIRECT_SENTINEL/.design-approved"
INPUT5=$(jq -n \
  --arg cwd "$TMPDIR" \
  '{session_id: "sess-direct", cwd: $cwd}')
OUTPUT5=$(echo "$INPUT5" | bash "$HOOK" 2>/dev/null)
assert_output_contains "direct cwd sentinel found" "$OUTPUT5" '"behavior": "allow"'

echo "Test 6: Multiple sentinels, only matching session_id triggers"
MULTI_DIR1="$TMPDIR/docs/plans/2026-03-20-multi1"
MULTI_DIR2="$TMPDIR/docs/plans/2026-03-20-multi2"
mkdir -p "$MULTI_DIR1" "$MULTI_DIR2"
printf 'sess-old' > "$MULTI_DIR1/.design-approved"
printf 'sess-current' > "$MULTI_DIR2/.design-approved"
INPUT6=$(jq -n \
  --arg cwd "$TMPDIR" \
  '{session_id: "sess-current", cwd: $cwd}')
OUTPUT6=$(echo "$INPUT6" | bash "$HOOK" 2>/dev/null)
assert_output_contains "only matching sentinel triggers allow" "$OUTPUT6" '"behavior": "allow"'

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
