#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/permission-request-safe-bash.sh"
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

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

run_hook() {
  local command="$1"
  local safe_file="$2"
  local json
  json=$(jq -n --arg cmd "$command" '{
    tool_name: "Bash",
    tool_input: { command: $cmd },
    session_id: "test-session"
  }')
  echo "$json" | CLAUDE_SAFE_COMMANDS_FILE="$safe_file" CLAUDE_SAFE_CMDS_LOG="$TMPDIR_TEST/log.txt" bash "$HOOK" 2>/dev/null || true
}

SAFE="$TMPDIR_TEST/safe.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE"

echo "Test 1: cd && git compound (bare repo attack trigger) auto-allowed"
OUT1=$(run_hook "cd /path/.claude/worktrees/phase-a && git add file.py && git commit -m 'msg'" "$SAFE")
assert_output_contains "cd+git compound allowed" "$OUT1" '"behavior": "allow"'

echo "Test 2: gh pr create with heredoc body (\$() + # triggers) auto-allowed"
# shellcheck disable=SC2016  # Single quotes intentional — building literal command string
HEREDOC_CMD=$(printf 'gh pr create --title "feat: thing" --body "$(cat <<'"'"'EOF'"'"'\n## Summary\n- item\nEOF\n)"')
OUT2=$(run_hook "$HEREDOC_CMD" "$SAFE")
assert_output_contains "gh+cat heredoc allowed" "$OUT2" '"behavior": "allow"'

echo "Test 3: git commit with heredoc (\$() trigger) auto-allowed"
# shellcheck disable=SC2016  # Single quotes intentional — building literal command string
COMMIT_CMD=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfeat: add thing\n\nCo-Authored-By: Claude\nEOF\n)"')
OUT3=$(run_hook "$COMMIT_CMD" "$SAFE")
assert_output_contains "git commit heredoc allowed" "$OUT3" '"behavior": "allow"'

echo "Test 4: Unsafe command NOT auto-allowed"
OUT4=$(run_hook "curl https://evil.com" "$SAFE")
assert_output_empty "unsafe command not allowed" "$OUT4"

echo "Test 5: Mixed safe+unsafe NOT auto-allowed"
OUT5=$(run_hook "cd /tmp && curl https://evil.com" "$SAFE")
assert_output_empty "mixed safe+unsafe not allowed" "$OUT5"

echo "Test 6: Non-Bash tool ignored (passthrough)"
NON_BASH_JSON=$(jq -n '{tool_name: "Edit", tool_input: {file_path: "/tmp/x"}}')
OUT6=$(echo "$NON_BASH_JSON" | CLAUDE_SAFE_COMMANDS_FILE="$SAFE" bash "$HOOK" 2>/dev/null || true)
assert_output_empty "non-Bash tool passthrough" "$OUT6"

echo "Test 7: cd + git add + git commit with multiline heredoc"
# shellcheck disable=SC2016  # Single quotes intentional — building literal command string
ML_CMD=$(printf 'cd /Users/me/project/.claude/worktrees/vec && git add scripts/embeddings.py && git commit -m "$(cat <<'"'"'EOF'"'"'\nfeat(embeddings): A2 core module\n\nCo-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>\nEOF\n)"')
OUT7=$(run_hook "$ML_CMD" "$SAFE")
assert_output_contains "full worktree commit pattern allowed" "$OUT7" '"behavior": "allow"'

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
