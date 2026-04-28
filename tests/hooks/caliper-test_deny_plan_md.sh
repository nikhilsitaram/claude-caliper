#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pretooluse-deny-plan-md.sh"
PASS=0
FAIL=0

assert_deny_contains() {
  local desc="$1" output="$2" needle="$3"
  if echo "$output" | grep -qF '"permissionDecision":"deny"' \
     && echo "$output" | grep -qF -- "$needle"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected deny + '$needle')"
    echo "  Got: $output"
    ((FAIL++)) || true
  fi
}

assert_allow() {
  local desc="$1" output="$2"
  if [[ -z "$output" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected empty output, got: $output)"
    ((FAIL++)) || true
  fi
}

run_hook() {
  local tool_name="$1" file_path="$2"
  jq -n --arg t "$tool_name" --arg p "$file_path" '{
    tool_name: $t,
    tool_input: { file_path: $p },
    session_id: "test-session"
  }' | "$HOOK" 2>/dev/null || true
}

echo "Test 1: Edit on caliper plan.md is denied"
out=$(run_hook "Edit" "/Users/foo/repo/.claude/claude-caliper/2026-04-28-topic/plan.md")
assert_deny_contains "Edit denied with --add-file hint" "$out" "--add-file"
assert_deny_contains "Edit denied with --render hint" "$out" "--render"

echo "Test 2: Write on caliper plan.md is denied"
out=$(run_hook "Write" "/Users/foo/repo/.claude/claude-caliper/2026-04-28-topic/plan.md")
assert_deny_contains "Write denied" "$out" "permissionDecision"

echo "Test 3: MultiEdit on caliper plan.md is denied"
out=$(run_hook "MultiEdit" "/Users/foo/repo/.claude/claude-caliper/2026-04-28-topic/plan.md")
assert_deny_contains "MultiEdit denied" "$out" "permissionDecision"

echo "Test 4: Edit on phase-a/completion.md is allowed"
out=$(run_hook "Edit" "/Users/foo/repo/.claude/claude-caliper/2026-04-28-topic/phase-a/completion.md")
assert_allow "completion.md is editable" "$out"

echo "Test 5: Edit on phase-a/a1.md is allowed"
out=$(run_hook "Edit" "/Users/foo/repo/.claude/claude-caliper/2026-04-28-topic/phase-a/a1.md")
assert_allow "task .md is editable" "$out"

echo "Test 6: Edit on plan.md outside caliper tree is allowed"
out=$(run_hook "Edit" "/Users/foo/some-other-repo/docs/plan.md")
assert_allow "plan.md outside caliper tree is editable" "$out"

echo "Test 7: Edit on unrelated path is allowed"
out=$(run_hook "Edit" "/Users/foo/repo/src/index.ts")
assert_allow "unrelated source file is editable" "$out"

echo "Test 8: Bash tool with file_path-shaped command is ignored"
out=$(jq -n '{
  tool_name: "Bash",
  tool_input: { command: "rm /tmp/.claude/claude-caliper/x/plan.md" },
  session_id: "test-session"
}' | "$HOOK" 2>/dev/null || true)
assert_allow "Bash tool ignored" "$out"

echo "Test 9: Edit on relative caliper plan.md is denied"
out=$(run_hook "Edit" ".claude/claude-caliper/2026-04-28-topic/plan.md")
assert_deny_contains "relative path denied" "$out" "--add-file"

echo "Test 10: Edit on ./.claude caliper plan.md is denied"
out=$(run_hook "Edit" "./.claude/claude-caliper/2026-04-28-topic/plan.md")
assert_deny_contains "explicit ./ relative path denied" "$out" "--add-file"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
