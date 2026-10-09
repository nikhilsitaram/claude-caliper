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

# Fallthrough = {"continue": true} with no decision, so the normal prompt shows.
assert_falls_through() {
  local desc="$1" output="$2"
  if echo "$output" | grep -qF '"continue": true' && ! echo "$output" | grep -qF '"behavior"'; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected fallthrough, got: $output)"
    ((FAIL++)) || true
  fi
}

SID="11111111-2222-3333-4444-555555555555"

# Run the hook for an Edit/Write of $2 from session cwd $1, as session $3
# (default $SID).
run_hook_for() {
  jq -n --arg cwd "$1" --arg f "$2" --arg sid "${3-$SID}" \
    '{session_id: $sid, cwd: $cwd, tool_input: {file_path: $f}}' | bash "$HOOK" 2>/dev/null
}

# approve <plan dir> [session id] — write the sentinel as the design skill does.
approve() {
  mkdir -p "$1" && printf '%s\n' "${2-$SID}" > "$1/.design-approved"
}

assert_mode_switch() {
  assert_output_contains "$1 (allow)" "$2" '"behavior": "allow"'
  assert_output_contains "$1 (acceptEdits)" "$2" '"mode": "acceptEdits"'
}

assert_exists() {
  if [[ -e "$2" || -L "$2" ]]; then
    echo "PASS: $1"
    ((PASS++)) || true
  else
    echo "FAIL: $1 ($2 is gone)"
    ((FAIL++)) || true
  fi
}

assert_gone() {
  if [[ -e "$2" || -L "$2" ]]; then
    echo "FAIL: $1 ($2 still exists)"
    ((FAIL++)) || true
  else
    echo "PASS: $1"
    ((PASS++)) || true
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Test 1: Sentinel exists returns allow+setMode JSON and consumes sentinel"
SENTINEL_DIR1="$TMPDIR/.claude/claude-caliper/2026-03-20-topic"
approve "$SENTINEL_DIR1"
OUTPUT1=$(run_hook_for "$TMPDIR" "$TMPDIR/src/x.py")
assert_output_contains "sentinel exists returns allow behavior" "$OUTPUT1" '"behavior": "allow"'
assert_output_contains "sentinel exists returns acceptEdits mode" "$OUTPUT1" '"mode": "acceptEdits"'
assert_output_contains "sentinel exists returns session destination" "$OUTPUT1" '"destination": "session"'

echo "Test 1b: Sentinel consumed — second invocation defers via continue:true"
assert_falls_through "sentinel consumed, second call defers" "$(run_hook_for "$TMPDIR" "$TMPDIR/src/x.py")"

echo "Test 2: No sentinel file defers via continue:true (passthrough)"
INPUT2=$(jq -n --arg cwd "$TMPDIR/no-sentinel-here" '{cwd: $cwd}')
OUTPUT2=$(echo "$INPUT2" | bash "$HOOK" 2>/dev/null)
assert_output_contains "missing sentinel defers" "$OUTPUT2" '"continue": true'

echo "Test 3: Worktree search path finds sentinel and consumes it"
WORKTREE_SENTINEL="$TMPDIR/.claude/worktrees/my-branch/.claude/claude-caliper/2026-03-20-topic"
approve "$WORKTREE_SENTINEL"
OUTPUT3=$(run_hook_for "$TMPDIR" "$TMPDIR/src/x.py")
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

echo "Test 5: Auto-approve for a file under the cwd's .claude/claude-caliper/"
INPUT5=$(jq -n --arg cwd "$TMPDIR" '{cwd: $cwd, tool_input: {file_path: ($cwd + "/.claude/claude-caliper/2026-03-20-topic/plan.md")}}')
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
approve "$SENTINEL_DIR5B"
OUTPUT5B=$(run_hook_for "$TMPDIR/sentinel-with-caliper-edit" "$SENTINEL_DIR5B/design-topic.md")
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

echo "Test 6: A .claude/claude-caliper/ substring outside a plan root falls through (#307)"
# .claude/ exists but claude-caliper/ doesn't: a `..` in the not-yet-existing
# tail must still be refused, not appended after the existing prefix.
T6="$TMPDIR/t6"
mkdir -p "$T6/.claude"
for p in \
    "/x/.claude/claude-caliper/../../../Users/u/.bashrc" \
    "$T6/.claude/claude-caliper/../settings.json" \
    "$T6/.claude/claude-caliper/../../.git/hooks/pre-commit" \
    "/tmp/evil/.claude/claude-caliper/x.sh" \
    "$T6/.claude/claude-caliper/topic/../plan.json" \
    "$T6/.claude/claude-caliper-x/plan.json" \
    ".claude/claude-caliper/plan.json" \
    "$T6/.claude/claude-caliper/topic/.design-approved" \
    "$T6/.claude/claude-caliper/topic/reviews.json"; do
  assert_falls_through "falls through: $p" "$(run_hook_for "$T6" "$p")"
done

echo "Test 7: Plan roots of the cwd, its worktrees, and the main checkout are allowed"
T7="$TMPDIR/t7"
mkdir -p "$T7/.claude/worktrees/wt/.claude/claude-caliper"
ln -s "$T7" "$TMPDIR/t7-link"
assert_output_contains "cwd's plan dir via a symlinked cwd" \
  "$(run_hook_for "$TMPDIR/t7-link" "$TMPDIR/t7-link/.claude/claude-caliper/topic/plan.json")" '"behavior": "allow"'
assert_output_contains "physical path from a symlinked cwd" \
  "$(run_hook_for "$TMPDIR/t7-link" "$(cd "$T7" && pwd -P)/.claude/claude-caliper/topic/plan.json")" '"behavior": "allow"'
assert_output_contains "nested worktree's plan dir" \
  "$(run_hook_for "$T7" "$T7/.claude/worktrees/wt/.claude/claude-caliper/topic/plan.json")" '"behavior": "allow"'
MAIN7="$(cd "$TMPDIR" && pwd -P)/t7main"
git init -q "$MAIN7"
git -C "$MAIN7" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$MAIN7" worktree add -q "$MAIN7/.claude/worktrees/wt" -b w
git -C "$MAIN7" worktree add -q "$MAIN7/.claude/worktrees/wt2" -b w2
mkdir -p "$MAIN7/.claude/worktrees/wt2/.claude/claude-caliper"
assert_output_contains "main checkout's plan dir from a linked worktree" \
  "$(run_hook_for "$MAIN7/.claude/worktrees/wt" "$MAIN7/.claude/claude-caliper/topic/plan.json")" '"behavior": "allow"'
assert_output_contains "sibling worktree's plan dir via the main checkout" \
  "$(run_hook_for "$MAIN7/.claude/worktrees/wt" "$MAIN7/.claude/worktrees/wt2/.claude/claude-caliper/topic/plan.json")" '"behavior": "allow"'

echo "Test 8: A symlink that leads out of the plan root falls through"
OUTSIDE="$TMPDIR/outside"
mkdir -p "$OUTSIDE"
T8A="$TMPDIR/t8a"
mkdir -p "$T8A/.claude"
ln -s "$OUTSIDE" "$T8A/.claude/claude-caliper"
assert_falls_through "symlinked plan dir" "$(run_hook_for "$T8A" "$T8A/.claude/claude-caliper/plan.json")"
T8B="$TMPDIR/t8b"
mkdir -p "$T8B/.claude/claude-caliper/topic"
ln -s "$OUTSIDE/target" "$T8B/.claude/claude-caliper/topic/plan.json"
assert_falls_through "symlinked file" "$(run_hook_for "$T8B" "$T8B/.claude/claude-caliper/topic/plan.json")"
# A dangling directory symlink can't be resolved, but a write that creates its
# target first would follow it out of the plan dir.
ln -s "$OUTSIDE/newdir" "$T8B/.claude/claude-caliper/dangling"
assert_falls_through "dangling symlink partway down the path" \
  "$(run_hook_for "$T8B" "$T8B/.claude/claude-caliper/dangling/plan.json")"
# Command substitution drops a trailing newline, which would check design.md
# (absent) while the Write follows the symlink named design.md<newline>.
ln -s "$OUTSIDE/target" "$T8B/.claude/claude-caliper/topic/design.md"$'\n'
assert_falls_through "symlinked file whose name ends in a newline" \
  "$(run_hook_for "$T8B" "$T8B/.claude/claude-caliper/topic/design.md"$'\n')"

echo "Test 10: From a submodule's linked worktree, the sentinel in the submodule checkout is found"
# A submodule's git dir is <super>/.git/modules/<name>, so stripping /.git from
# the common dir never reaches the checkout that holds the plan dirs.
SUBBASE="$(cd "$TMPDIR" && pwd -P)/t10"
mkdir -p "$SUBBASE"
git -C "$SUBBASE" init -q subsrc
git -C "$SUBBASE/subsrc" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$SUBBASE" init -q super
git -C "$SUBBASE/super" -c protocol.file.allow=always submodule -q add "$SUBBASE/subsrc" sub
git -C "$SUBBASE/super/sub" worktree add -q "$SUBBASE/sub-wt" -b w
SUB_SENTINEL="$SUBBASE/super/sub/.claude/claude-caliper/2026-03-20-topic"
approve "$SUB_SENTINEL"
OUTPUT10=$(run_hook_for "$SUBBASE/sub-wt" "$SUBBASE/sub-wt/src/x.py")
assert_output_contains "submodule checkout's sentinel found from its linked worktree" "$OUTPUT10" '"behavior": "allow"'

echo "Test 11: Only this session's sentinel switches the mode (#311)"
T11="$(cd "$TMPDIR" && pwd -P)/t11"
git init -q "$T11"
mkdir -p "$T11/.claude/claude-caliper/committed"
touch "$T11/.claude/claude-caliper/committed/.design-approved"
printf '%s\n' "$SID" > "$T11/.claude/claude-caliper/committed/notes.txt"
git -C "$T11" add -f .claude
git -C "$T11" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -q -m "ship a sentinel"
assert_falls_through "a committed (empty) sentinel" "$(run_hook_for "$T11" "$T11/src/x.py")"
assert_exists "a committed sentinel is left in place" "$T11/.claude/claude-caliper/committed/.design-approved"
approve "$T11/.claude/claude-caliper/other" "99999999-0000-0000-0000-000000000000"
assert_falls_through "another session's sentinel" "$(run_hook_for "$T11" "$T11/src/x.py")"
assert_exists "another session's sentinel is left in place" "$T11/.claude/claude-caliper/other/.design-approved"
assert_falls_through "a payload with no session_id against an empty sentinel" \
  "$(jq -n --arg cwd "$T11" '{cwd: $cwd, tool_input: {file_path: ($cwd + "/src/x.py")}}' | bash "$HOOK" 2>/dev/null)"
mkdir -p "$T11/.claude/claude-caliper/linked"
ln -s "$T11/.claude/claude-caliper/committed/notes.txt" "$T11/.claude/claude-caliper/linked/.design-approved"
assert_falls_through "a symlinked sentinel, even to this session's id" "$(run_hook_for "$T11" "$T11/src/x.py")"
# Decoys sit in the cwd's plan dir, which the hook searches before a worktree's.
approve "$T11/.claude/worktrees/wt/.claude/claude-caliper/real"
assert_mode_switch "this session's sentinel behind decoys" "$(run_hook_for "$T11" "$T11/src/x.py")"
assert_gone "this session's sentinel is consumed" "$T11/.claude/worktrees/wt/.claude/claude-caliper/real/.design-approved"
assert_exists "the decoys are left in place" "$T11/.claude/claude-caliper/other/.design-approved"

echo "Test 12: The sentinel never approves a protected or outside target (#311)"
T12="$(cd "$TMPDIR" && pwd -P)/t12"
mkdir -p "$T12/.git/hooks" "$T12/.claude/claude-caliper/topic" "$TMPDIR/elsewhere"
approve "$T12/.claude/claude-caliper/topic"
for p in \
    "$T12/.claude/settings.json" \
    "$T12/.claude/claude-caliper/topic/reviews.json" \
    "$T12/.claude/claude-caliper/topic/.design-approved" \
    "$T12/.git/hooks/pre-commit" \
    "$T12/src/.hidden/x.py" \
    "$T12/.caliper-draft/.x" \
    "$T12/src/../.claude/settings.json" \
    "$TMPDIR/elsewhere/x.py" \
    "$T12/.claude/worktrees/wt/src/x.py" \
    ""; do
  assert_falls_through "sentinel held for: ${p:-<no file_path>}" "$(run_hook_for "$T12" "$p")"
done
assert_exists "the sentinel survives every refused target" "$T12/.claude/claude-caliper/topic/.design-approved"
assert_mode_switch "the next ordinary edit" "$(run_hook_for "$T12" "$T12/src/x.py")"
approve "$T12/.claude/claude-caliper/topic"
assert_mode_switch "a design draft" "$(run_hook_for "$T12" "$T12/.caliper-draft/design-topic.md")"

echo "Test 13: The design skill's own sentinel command arms the hook"
# Run the command skills/design/SKILL.md gives the agent, not approve()'s copy
# of it, so the two sides of the sentinel format can't drift apart.
SENTINEL_CMD=$(sed -n 's/.*On approval, create the sentinel[^`]*`\([^`]*\)`.*/\1/p' "$REPO_ROOT/skills/design/SKILL.md")
T13="$(cd "$TMPDIR" && pwd -P)/t13"
mkdir -p "$T13"
if [[ -z "$SENTINEL_CMD" ]]; then
  echo "FAIL: no sentinel command found in skills/design/SKILL.md"
  ((FAIL++)) || true
else
  PLAN_DIR="$T13/.claude/claude-caliper/topic" CLAUDE_CODE_SESSION_ID="$SID" bash -c "$SENTINEL_CMD"
  assert_mode_switch "the design skill's sentinel" "$(run_hook_for "$T13" "$T13/src/x.py")"
  if env -u CLAUDE_CODE_SESSION_ID PLAN_DIR="$T13/.claude/claude-caliper/unset" bash -c "$SENTINEL_CMD" 2>/dev/null; then
    echo "FAIL: the sentinel command succeeded without a session id"
    ((FAIL++)) || true
  else
    echo "PASS: the sentinel command fails without a session id"
    ((PASS++)) || true
  fi
fi

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
