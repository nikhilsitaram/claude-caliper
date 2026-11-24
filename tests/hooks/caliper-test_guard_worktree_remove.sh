#!/usr/bin/env bash
set -euo pipefail

# Tests for hooks/pretooluse-guard-worktree-remove.sh (issue #317): a removal
# whose target is the session's cwd or an ancestor of it is denied; any other
# removal, and anything the hook can't resolve, passes through untouched.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/pretooluse-guard-worktree-remove.sh"
NEEDLE="is inside the worktree being removed"
PASS=0
FAIL=0

# The guard only compares paths, so plain directories stand in for worktrees.
RAW_TMP="$(mktemp -d)"
trap 'rm -rf "$RAW_TMP"' EXIT
TMP="$(cd "$RAW_TMP" && pwd -P)"
MAIN="$TMP/main"
WT="$MAIN/.claude/worktrees/feat"
PHASE="$WT/.claude/worktrees/phase-a"
SIB="$MAIN/.claude/worktrees/feat-2"
SPACED="$MAIN/.claude/worktrees/with space"
mkdir -p "$WT/src" "$PHASE" "$SIB" "$SPACED"
ln -s "$WT" "$TMP/wt-link"

# Prints the hook's output; a non-zero exit (exit 2 blocks the tool call) or
# any stderr is appended so both assert_deny and assert_allow fail on it.
feed_hook() {
  local out rc=0
  out="$(HOME="$TMP" "$HOOK" 2>&1)" || rc=$?
  printf '%s' "$out"
  [[ $rc -eq 0 ]] || printf ' EXIT:%s' "$rc"
}

run_hook() {
  local cwd="$1" cmd="$2" tool="${3:-Bash}"
  jq -n --arg t "$tool" --arg c "$cmd" --arg d "$cwd" '{
    tool_name: $t,
    tool_input: { command: $c },
    cwd: $d,
    session_id: "test-session"
  }' | feed_hook
}

assert_deny() {
  local desc="$1" output="$2"
  if echo "$output" | jq -e --arg n "$NEEDLE" '
       .hookSpecificOutput.hookEventName == "PreToolUse"
       and .hookSpecificOutput.permissionDecision == "deny"
       and (.hookSpecificOutput.permissionDecisionReason | contains($n))
       and (.hookSpecificOutput.permissionDecisionReason | contains("ExitWorktree"))' >/dev/null 2>&1; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected deny containing '$NEEDLE')"
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
    echo "FAIL: $desc (expected no output, got: $output)"
    ((FAIL++)) || true
  fi
}

echo "=== Denied: the target is the session cwd or an ancestor of it ==="
assert_deny "cwd equals the absolute target" \
  "$(run_hook "$WT" "git worktree remove $WT")"
assert_deny "cwd is a subdirectory of the target" \
  "$(run_hook "$WT/src" "git worktree remove $WT")"
assert_deny "chained cd out in the same call (pane 2 of #317)" \
  "$(run_hook "$WT" "cd $MAIN && git worktree remove $WT")"
assert_deny "git -C <main> with an absolute target" \
  "$(run_hook "$WT" "git -C $MAIN worktree remove $WT")"
assert_deny "--force flag before the target" \
  "$(run_hook "$WT" "git worktree remove --force $WT")"
assert_deny "relative '.' target" \
  "$(run_hook "$WT" "git worktree remove .")"
assert_deny "relative target resolved against a chained cd" \
  "$(run_hook "$WT" "cd $MAIN && git worktree remove .claude/worktrees/feat")"
assert_deny "relative target resolved against git -C" \
  "$(run_hook "$WT" "git -C $MAIN worktree remove .claude/worktrees/feat")"
assert_deny "tilde target" \
  "$(run_hook "$WT" "git worktree remove ~/main/.claude/worktrees/feat")"
assert_deny "double-quoted target containing a space" \
  "$(run_hook "$SPACED" "git worktree remove \"$SPACED\"")"
assert_deny "single-quoted target" \
  "$(run_hook "$WT" "git worktree remove '$WT'")"
assert_deny "cwd reached through a symlink, target given physically" \
  "$(run_hook "$TMP/wt-link" "git worktree remove $WT")"
assert_deny "removing the integration worktree from inside a nested phase worktree" \
  "$(run_hook "$PHASE" "git worktree remove $WT")"
assert_deny "relative target after cd -- (options parsed)" \
  "$(run_hook "$WT" "cd -- $MAIN && git worktree remove .claude/worktrees/feat")"
assert_deny "relative target after cd -P (options parsed)" \
  "$(run_hook "$WT" "cd -P $MAIN && git worktree remove .claude/worktrees/feat")"
assert_deny "relative target after pushd" \
  "$(run_hook "$WT" "pushd $MAIN && git worktree remove .claude/worktrees/feat")"
assert_deny "absolute cd after an earlier cd still sets the base" \
  "$(run_hook "$WT" "cd $SIB && cd $MAIN && git worktree remove .claude/worktrees/feat")"
assert_deny "git -C not adjacent, absolute target still checked" \
  "$(run_hook "$WT" "git -C $MAIN -c x=y worktree remove $WT")"
assert_deny "quoted target followed by a separator" \
  "$(run_hook "$SPACED" "git worktree remove \"$SPACED\"; echo ok")"
assert_deny "second removal in one call targets the cwd" \
  "$(run_hook "$WT" "git worktree remove $SIB && git worktree remove $WT")"

echo ""
echo "=== Allowed: the session stands outside the target ==="
assert_allow "removal from the main checkout" \
  "$(run_hook "$MAIN" "git worktree remove $WT")"
assert_allow "sibling sharing a name prefix (feat-2 vs feat)" \
  "$(run_hook "$SIB" "git worktree remove $WT")"
assert_allow "nested phase worktree removed from the integration worktree" \
  "$(run_hook "$WT" "git worktree remove $PHASE")"
assert_allow "heredoc commit message mentioning a placeholder removal" \
  "$(run_hook "$WT" "git commit -F - <<'EOF'
docs: run git worktree remove <WORKTREE_PATH> from the main checkout
EOF")"
assert_allow "'.' after pushd elsewhere" \
  "$(run_hook "$WT" "pushd $SIB && git worktree remove .")"
assert_allow "'.' after cd -P elsewhere" \
  "$(run_hook "$WT" "cd -P $SIB && git worktree remove .")"
assert_allow "'.' after cd - (unknown base fails open)" \
  "$(run_hook "$WT" "cd - && git worktree remove .")"
assert_allow "'.' after popd (unknown base fails open)" \
  "$(run_hook "$WT" "popd && git worktree remove .")"
assert_allow "quoted prefix concatenated into a sibling word" \
  "$(run_hook "$SPACED" "git worktree remove \"$SPACED\"-2")"
assert_allow "relative cd stacked on an earlier cd (base unknown fails open)" \
  "$(run_hook "$WT" "cd $MAIN/.claude && cd .. && git worktree remove feat")"
assert_allow "git -C not adjacent to worktree (base unknown fails open)" \
  "$(run_hook "$WT" "git -C $SIB -c x=y worktree remove .")"
assert_allow "relative cd stacked on an absolute cd elsewhere" \
  "$(run_hook "$WT" "cd $SIB && cd .. && git worktree remove feat-2")"
assert_allow "unresolvable variable target" \
  "$(run_hook "$WT" "git worktree remove \"\$WORKTREE_PATH\"")"
assert_allow "command substitution target" \
  "$(run_hook "$WT" "git worktree remove \$(pwd)")"
assert_allow "nonexistent target" \
  "$(run_hook "$WT" "git worktree remove $MAIN/.claude/worktrees/gone")"
assert_allow "other worktree subcommand" \
  "$(run_hook "$WT" "git worktree list --porcelain")"
assert_allow "non-Bash tool" \
  "$(run_hook "$WT" "git worktree remove $WT" Edit)"
assert_allow "missing cwd field" \
  "$(jq -n --arg c "git worktree remove $WT" '{tool_name:"Bash",tool_input:{command:$c}}' | feed_hook)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
