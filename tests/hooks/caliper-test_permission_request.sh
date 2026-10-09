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

# Run the hook for an Edit/Write of $2 from session cwd $1.
run_hook_for() {
  jq -n --arg cwd "$1" --arg f "$2" '{cwd: $cwd, tool_input: {file_path: $f}}' | bash "$HOOK" 2>/dev/null
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
    ".claude/claude-caliper/plan.json"; do
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
mkdir -p "$SUB_SENTINEL"
touch "$SUB_SENTINEL/.design-approved"
INPUT10=$(jq -n --arg cwd "$SUBBASE/sub-wt" '{cwd: $cwd}')
OUTPUT10=$(echo "$INPUT10" | bash "$HOOK" 2>/dev/null)
assert_output_contains "submodule checkout's sentinel found from its linked worktree" "$OUTPUT10" '"behavior": "allow"'

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
