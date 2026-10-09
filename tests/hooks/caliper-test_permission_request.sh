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
SENTINEL_DIR1="$TMPDIR/.claude/claude-caliper/2026-03-20-topic"
mkdir -p "$SENTINEL_DIR1"
touch "$SENTINEL_DIR1/.design-approved"
INPUT1=$(jq -n --arg cwd "$TMPDIR" '{cwd: $cwd}')
OUTPUT1=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null)
assert_output_contains "sentinel exists returns allow behavior" "$OUTPUT1" '"behavior": "allow"'
assert_output_contains "sentinel exists returns acceptEdits mode" "$OUTPUT1" '"mode": "acceptEdits"'
assert_output_contains "sentinel exists returns session destination" "$OUTPUT1" '"destination": "session"'

echo "Test 1b: Sentinel consumed — second invocation defers via continue:true"
OUTPUT1B=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null)
assert_output_contains "sentinel consumed, second call defers" "$OUTPUT1B" '"continue": true'

echo "Test 2: No sentinel file defers via continue:true (passthrough)"
INPUT2=$(jq -n --arg cwd "$TMPDIR/no-sentinel-here" '{cwd: $cwd}')
OUTPUT2=$(echo "$INPUT2" | bash "$HOOK" 2>/dev/null)
assert_output_contains "missing sentinel defers" "$OUTPUT2" '"continue": true'

echo "Test 3: Worktree search path finds sentinel and consumes it"
WORKTREE_SENTINEL="$TMPDIR/.claude/worktrees/my-branch/.claude/claude-caliper/2026-03-20-topic"
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

echo "Test 4: Empty cwd defers via continue:true"
INPUT4=$(jq -n '{cwd: ""}')
OUTPUT4=$(echo "$INPUT4" | bash "$HOOK" 2>/dev/null)
assert_output_contains "empty cwd defers" "$OUTPUT4" '"continue": true'

echo "Test 5: Auto-approve for .claude/claude-caliper/ file paths"
INPUT5=$(jq -n --arg cwd "$TMPDIR" '{cwd: $cwd, tool_input: {file_path: "/some/project/.claude/claude-caliper/2026-03-20-topic/plan.md"}}')
OUTPUT5=$(echo "$INPUT5" | bash "$HOOK" 2>/dev/null)
assert_output_contains "auto-approve allows .claude/claude-caliper/ path" "$OUTPUT5" '"behavior": "allow"'
if echo "$OUTPUT5" | grep -qF '"updatedPermissions"'; then
  echo "FAIL: auto-approve should not include updatedPermissions"
  ((FAIL++)) || true
else
  echo "PASS: auto-approve does not include updatedPermissions"
  ((PASS++)) || true
fi

echo "Test 5b: Sentinel + caliper file_path — sentinel wins (consume + setMode)"
SENTINEL_DIR5B="$TMPDIR/sentinel-with-caliper-edit/.claude/claude-caliper/2026-04-27-topic"
mkdir -p "$SENTINEL_DIR5B"
touch "$SENTINEL_DIR5B/.design-approved"
INPUT5B=$(jq -n --arg cwd "$TMPDIR/sentinel-with-caliper-edit" '{cwd: $cwd, tool_input: {file_path: ($cwd + "/.claude/claude-caliper/2026-04-27-topic/design-topic.md")}}')
OUTPUT5B=$(echo "$INPUT5B" | bash "$HOOK" 2>/dev/null)
assert_output_contains "sentinel + caliper edit returns allow" "$OUTPUT5B" '"behavior": "allow"'
assert_output_contains "sentinel + caliper edit returns acceptEdits mode" "$OUTPUT5B" '"mode": "acceptEdits"'
if [[ -f "$SENTINEL_DIR5B/.design-approved" ]]; then
  echo "FAIL: sentinel not consumed when file_path is in caliper dir"
  ((FAIL++)) || true
else
  echo "PASS: sentinel consumed even when file_path is in caliper dir"
  ((PASS++)) || true
fi

echo "Test 5c: Non-caliper Edit/Write path defers via continue:true (bug #12070 — silent exit was treated as deny)"
INPUT5C=$(jq -n --arg cwd "$TMPDIR" '{cwd: $cwd, tool_input: {file_path: "/some/project/src/foo.py"}}')
OUTPUT5C=$(echo "$INPUT5C" | bash "$HOOK" 2>/dev/null)
assert_output_contains "non-caliper file_path defers" "$OUTPUT5C" '"continue": true'
if echo "$OUTPUT5C" | grep -qF '"behavior"'; then
  echo "FAIL: non-caliper file should not emit a decision"
  ((FAIL++)) || true
else
  echo "PASS: non-caliper file emits no decision"
  ((PASS++)) || true
fi
echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
