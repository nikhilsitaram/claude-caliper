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

echo "Test 1: Sentinel exists returns allow+setMode JSON and consumes sentinel"
SENTINEL_DIR1="$TMPDIR/docs/plans/2026-03-20-topic"
mkdir -p "$SENTINEL_DIR1"
touch "$SENTINEL_DIR1/.design-approved"
INPUT1=$(jq -n --arg cwd "$TMPDIR" '{cwd: $cwd}')
OUTPUT1=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null)
assert_output_contains "sentinel exists returns allow behavior" "$OUTPUT1" '"behavior": "allow"'
assert_output_contains "sentinel exists returns acceptEdits mode" "$OUTPUT1" '"mode": "acceptEdits"'
assert_output_contains "sentinel exists returns session destination" "$OUTPUT1" '"destination": "session"'

echo "Test 1b: Sentinel consumed — second invocation produces no output"
OUTPUT1B=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null)
assert_output_empty "sentinel consumed, second call produces no output" "$OUTPUT1B"

echo "Test 2: No sentinel file produces no output (passthrough)"
INPUT2=$(jq -n --arg cwd "$TMPDIR/no-sentinel-here" '{cwd: $cwd}')
OUTPUT2=$(echo "$INPUT2" | bash "$HOOK" 2>/dev/null)
assert_output_empty "missing sentinel produces no output" "$OUTPUT2"

echo "Test 3: Worktree search path finds sentinel and consumes it"
WORKTREE_SENTINEL="$TMPDIR/.claude/worktrees/my-branch/docs/plans/2026-03-20-topic"
mkdir -p "$WORKTREE_SENTINEL"
touch "$WORKTREE_SENTINEL/.design-approved"
INPUT3=$(jq -n --arg cwd "$TMPDIR" '{cwd: $cwd}')
OUTPUT3=$(echo "$INPUT3" | bash "$HOOK" 2>/dev/null)
assert_output_contains "worktree sentinel found via glob path" "$OUTPUT3" '"behavior": "allow"'
if [[ -f "$WORKTREE_SENTINEL/.design-approved" ]]; then
  echo "FAIL: worktree sentinel not consumed"
  ((FAIL++)) || true
else
  echo "PASS: worktree sentinel consumed"
  ((PASS++)) || true
fi

echo "Test 4: Empty cwd produces no output"
INPUT4=$(jq -n '{cwd: ""}')
OUTPUT4=$(echo "$INPUT4" | bash "$HOOK" 2>/dev/null)
assert_output_empty "empty cwd produces no output" "$OUTPUT4"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
