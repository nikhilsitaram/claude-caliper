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

echo "Test 1b: Sentinel consumed — second invocation produces no output"
OUTPUT1B=$(echo "$INPUT1" | bash "$HOOK" 2>/dev/null)
assert_output_empty "sentinel consumed, second call produces no output" "$OUTPUT1B"

echo "Test 2: No sentinel file produces no output (passthrough)"
INPUT2=$(jq -n --arg cwd "$TMPDIR/no-sentinel-here" '{cwd: $cwd}')
OUTPUT2=$(echo "$INPUT2" | bash "$HOOK" 2>/dev/null)
assert_output_empty "missing sentinel produces no output" "$OUTPUT2"

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

echo "Test 4: Empty cwd produces no output"
INPUT4=$(jq -n '{cwd: ""}')
OUTPUT4=$(echo "$INPUT4" | bash "$HOOK" 2>/dev/null)
assert_output_empty "empty cwd produces no output" "$OUTPUT4"

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

PRETOOLUSE_HOOK="$REPO_ROOT/hooks/pretooluse-safe-commands.sh"

run_pretooluse() {
  local command="$1"
  local json
  json=$(jq -n --arg cmd "$command" '{tool_name: "Bash", tool_input: {command: $cmd}, session_id: "test-session"}')
  echo "$json" | CLAUDE_SAFE_COMMANDS_FILE="$REPO_ROOT/hooks/safe-commands.txt" CLAUDE_SAFE_CMDS_LOG="/dev/null" bash "$PRETOOLUSE_HOOK" 2>/dev/null || true
}

echo "Test 6: Bash rm on .claude/claude-caliper/ path auto-allowed via PreToolUse"
OUTPUT6=$(run_pretooluse "rm /some/project/.claude/claude-caliper/2026-03-31-topic/phase-a/a7.md")
assert_output_contains "Bash rm on plan path auto-allowed" "$OUTPUT6" '"permissionDecision":"allow"'

echo "Test 7: Bash mkdir on .claude/claude-caliper/ path auto-allowed via PreToolUse"
OUTPUT7=$(run_pretooluse "mkdir -p /project/.claude/claude-caliper/2026-03-31-topic/phase-b")
assert_output_contains "Bash mkdir on plan path auto-allowed" "$OUTPUT7" '"permissionDecision":"allow"'

echo "Test 8: Bash on non-plan .claude/ path NOT auto-allowed (falls through)"
OUTPUT8=$(run_pretooluse "rm /project/.claude/settings.json")
if echo "$OUTPUT8" | grep -qF '"permissionDecision":"allow"'; then
  echo "FAIL: non-plan .claude/ path should not be auto-allowed"
  ((FAIL++)) || true
else
  echo "PASS: non-plan .claude/ path not auto-allowed"
  ((PASS++)) || true
fi

echo "Test 9: Non-Bash tool ignored by PreToolUse hook"
INPUT9=$(jq -n '{tool_name: "Edit", tool_input: {file_path: "/.claude/claude-caliper/foo"}, session_id: "test-session"}')
OUTPUT9=$(echo "$INPUT9" | CLAUDE_SAFE_COMMANDS_FILE="$REPO_ROOT/hooks/safe-commands.txt" CLAUDE_SAFE_CMDS_LOG="/dev/null" bash "$PRETOOLUSE_HOOK" 2>/dev/null || true)
assert_output_empty "non-Bash tool ignored" "$OUTPUT9"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
