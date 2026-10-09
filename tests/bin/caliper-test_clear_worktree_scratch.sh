#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/clear-worktree-scratch"
SEED="$REPO_ROOT/bin/seed-agent-memory"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'chmod -R u+w "$TMPDIR_BASE" 2>/dev/null; rm -rf "$TMPDIR_BASE"' EXIT

# Isolate from the host's git config: a global excludesfile that ignores
# .claude/settings.local.json (Claude Code's own setup does this) would hide the
# very scratch these tests need git to see as untracked.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMPDIR_BASE/xdg"

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc"; fail=$((fail + 1))
  fi
}

run_from() {
  local dir="$1"; shift
  (cd "$dir" && "$@")
}

check_fails() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $desc"; fail=$((fail + 1))
  else
    echo "PASS: $desc"; pass=$((pass + 1))
  fi
}

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

# A repo that does NOT ignore .claude/ (unlike caliper's own), so caliper's
# scratch is untracked content that blocks a bare `git worktree remove`.
new_fixture() {
  local raw="$TMPDIR_BASE/$1"
  mkdir -p "$raw"
  local fix
  fix="$(cd "$raw" && pwd -P)"
  git -C "$fix" init -q -b main
  git -C "$fix" config user.email "test@example.com"
  git -C "$fix" config user.name "test"
  (cd "$fix" && touch .gitignore && git add .gitignore && git -c commit.gpgsign=false commit -qm "init")
  git -C "$fix" worktree add -q "$fix/wt" -b wt-branch
  echo "$fix"
}

# Seed main's memory into the worktree, then add the rest of caliper's scratch.
add_scratch() {
  local fix="$1"
  mkdir -p "$fix/.claude/agent-memory/agent-x"
  echo "MAIN" > "$fix/.claude/agent-memory/agent-x/shared.md"
  echo '{"main":true}' > "$fix/.claude/settings.local.json"
  "$SEED" "$fix/wt"
  echo "learned in wt" > "$fix/wt/.claude/agent-memory/agent-x/new.md"
  mkdir -p "$fix/wt/.claude/caliper-draft"
  echo "{}" > "$fix/wt/.claude/caliper-draft/plan.json"
  echo '{"wt":true}' > "$fix/wt/.claude/settings.local.json"
}

# Test 1: run from the MAIN checkout's cwd (as pr-merge and orchestrate do) —
# the worktree's scratch is cleared, main's same-path files survive, memory is
# synced first, and a bare remove then succeeds.
fix="$(new_fixture t1)"
add_scratch "$fix"
check "t1: precondition — scratch shows as untracked in the worktree" test -n "$(git -C "$fix/wt" status --porcelain)"
check "t1: runs cleanly from main's cwd" run_from "$fix" "$SCRIPT" "$fix/wt"
check_eq "t1: main's same-path memory file survives" "MAIN" "$(cat "$fix/.claude/agent-memory/agent-x/shared.md" 2>/dev/null || true)"
check "t1: main's settings.local.json survives" test -f "$fix/.claude/settings.local.json"
check_eq "t1: worktree memory synced to main before deletion" "learned in wt" "$(cat "$fix/.claude/agent-memory/agent-x/new.md" 2>/dev/null || true)"
check "t1: worktree caliper-draft cleared" test ! -e "$fix/wt/.claude/caliper-draft/plan.json"
check "t1: worktree settings.local.json cleared" test ! -e "$fix/wt/.claude/settings.local.json"
check_eq "t1: worktree agent-memory files cleared" "" "$(find "$fix/wt/.claude/agent-memory" -type f 2>/dev/null)"
check "t1: bare git worktree remove succeeds" git -C "$fix" worktree remove "$fix/wt"
check "t1: worktree directory is gone" test ! -e "$fix/wt"

# Test 2: user content is never touched, so it still blocks the remove.
fix="$(new_fixture t2)"
add_scratch "$fix"
echo "mine" > "$fix/wt/notes.txt"
mkdir -p "$fix/wt/.claude/commands"
echo "mine" > "$fix/wt/.claude/commands/mine.md"
check "t2: runs cleanly from main's cwd" run_from "$fix" "$SCRIPT" "$fix/wt"
check "t2: untracked user file survives" test -f "$fix/wt/notes.txt"
check "t2: user's other .claude content survives" test -f "$fix/wt/.claude/commands/mine.md"
check_fails "t2: bare remove still refuses (user content present)" git -C "$fix" worktree remove "$fix/wt"

# Test 3: tracked agent memory (a repo that commits it) is left in place — only
# untracked scratch is deleted — so the worktree ends clean.
fix="$(new_fixture t3)"
mkdir -p "$fix/wt/.claude/agent-memory/agent-x"
echo "committed" > "$fix/wt/.claude/agent-memory/agent-x/tracked.md"
git -C "$fix/wt" add .claude/agent-memory/agent-x/tracked.md
git -C "$fix/wt" -c commit.gpgsign=false commit -qm "commit memory"
echo "{}" > "$fix/wt/.claude/settings.local.json"
check "t3: runs cleanly from main's cwd" run_from "$fix" "$SCRIPT" "$fix/wt"
check "t3: tracked memory file survives" test -f "$fix/wt/.claude/agent-memory/agent-x/tracked.md"
check_eq "t3: worktree is clean afterwards" "" "$(git -C "$fix/wt" status --porcelain)"

# Test 4: refuses the main checkout (or a path inside it) and deletes nothing.
fix="$(new_fixture t4)"
mkdir -p "$fix/.claude/caliper-draft"
echo "{}" > "$fix/.claude/caliper-draft/plan.json"
check_fails "t4: main checkout refused" "$SCRIPT" "$fix"
check_fails "t4: subdirectory of main refused" "$SCRIPT" "$fix/.claude"
check "t4: main's scratch untouched" test -f "$fix/.claude/caliper-draft/plan.json"
# A stray plain directory inside a linked worktree (e.g. a task-worktree path
# left behind) must not resolve to — and clear — the worktree containing it.
mkdir -p "$fix/wt/.claude/worktrees/a1" "$fix/wt/.claude/caliper-draft"
echo "{}" > "$fix/wt/.claude/caliper-draft/plan.json"
check_fails "t4: stray directory inside a worktree refused" "$SCRIPT" "$fix/wt/.claude/worktrees/a1"
check "t4: containing worktree's scratch untouched" test -f "$fix/wt/.claude/caliper-draft/plan.json"
# A main checkout whose git dir lives elsewhere (--separate-git-dir; submodules
# look the same) has no `/.git` to strip, so it must still be recognized as main.
sep="$TMPDIR_BASE/t4-sep"
git init -q --separate-git-dir "$sep-gitdir" "$sep"
mkdir -p "$sep/.claude/caliper-draft"
echo "{}" > "$sep/.claude/caliper-draft/plan.json"
check_fails "t4: --separate-git-dir main checkout refused" "$SCRIPT" "$sep"
check "t4: its scratch untouched" test -f "$sep/.claude/caliper-draft/plan.json"

# Test 5: a failed sync deletes nothing — the worktree copy may be the only one.
fix="$(new_fixture t5)"
mkdir -p "$fix/.claude" "$fix/wt/.claude/agent-memory/agent-x" "$fix/wt/.claude/caliper-draft"
echo "only copy" > "$fix/wt/.claude/agent-memory/agent-x/new.md"
echo "{}" > "$fix/wt/.claude/caliper-draft/plan.json"
chmod a-w "$fix/.claude"
if [[ -w "$fix/.claude" ]]; then
  echo "SKIP: t5 (running as root — chmod cannot force a sync failure)"
else
  check_fails "t5: exits non-zero when sync fails" "$SCRIPT" "$fix/wt"
  check "t5: unsynced memory kept" test -f "$fix/wt/.claude/agent-memory/agent-x/new.md"
  check "t5: other scratch kept" test -f "$fix/wt/.claude/caliper-draft/plan.json"
fi
chmod u+w "$fix/.claude"
# A sync skipped on a held lock counts as a failure too: nothing was persisted.
fix="$(new_fixture t5-lock)"
mkdir -p "$fix/.claude/agent-memory/.sync.lock.d" "$fix/wt/.claude/agent-memory/agent-x"
echo "only copy" > "$fix/wt/.claude/agent-memory/agent-x/new.md"
check_fails "t5: exits non-zero when sync skips on a held lock" env AGENT_MEMORY_LOCK_TRIES=2 "$SCRIPT" "$fix/wt"
check "t5: memory kept when the lock was held" test -f "$fix/wt/.claude/agent-memory/agent-x/new.md"

# Test 6: a leftover symlink from the retired link-agent-memory is unlinked,
# never followed — main's memory behind it survives.
fix="$(new_fixture t6)"
mkdir -p "$fix/.claude/agent-memory/agent-x" "$fix/wt/.claude"
echo "MAIN" > "$fix/.claude/agent-memory/agent-x/keep.md"
ln -s "$fix/.claude/agent-memory" "$fix/wt/.claude/agent-memory"
check "t6: runs cleanly from main's cwd" run_from "$fix" "$SCRIPT" "$fix/wt"
check "t6: worktree symlink removed" test ! -L "$fix/wt/.claude/agent-memory"
check_eq "t6: main's memory behind the link survives" "MAIN" "$(cat "$fix/.claude/agent-memory/agent-x/keep.md" 2>/dev/null || true)"

# Test 7: argument errors.
check_fails "t7: no args exits non-zero" "$SCRIPT"
check_fails "t7: nonexistent path exits non-zero" "$SCRIPT" "$TMPDIR_BASE/missing"
# A non-repo dir must not fall back to the caller's cwd (an empty `cd ""`) and
# clear the caller's scratch instead.
fix="$(new_fixture t7)"
mkdir -p "$TMPDIR_BASE/plain" "$fix/wt/.claude/caliper-draft"
echo "{}" > "$fix/wt/.claude/caliper-draft/plan.json"
check_fails "t7: non-repo directory exits non-zero" run_from "$fix/wt" "$SCRIPT" "$TMPDIR_BASE/plain"
check "t7: caller's worktree scratch untouched" test -f "$fix/wt/.claude/caliper-draft/plan.json"

echo ""
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
