#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/seed-agent-memory"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'chmod -R u+w "$TMPDIR_BASE" 2>/dev/null; rm -rf "$TMPDIR_BASE"' EXIT

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc"; fail=$((fail + 1))
  fi
}

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=$expected actual=$actual)"; fail=$((fail + 1))
  fi
}

# Fresh main repo + nested worktree fixture (pwd -P canonicalized so macOS's
# /var -> /private/var symlink doesn't trip path-equality assertions).
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

# Seed a memory file into the main repo before seeding the worktree.
seed_main() {
  mkdir -p "$1/.claude/agent-memory/agent-x"
  echo "prior memory" > "$1/.claude/agent-memory/agent-x/prior.md"
  printf '# Memory Index\n\n- [Prior](prior.md) — hook\n' > "$1/.claude/agent-memory/agent-x/MEMORY.md"
}

# Test 1: creates a REAL dir (not a symlink) at the worktree
fix="$(new_fixture t1)"
seed_main "$fix"
"$SCRIPT" "$fix/wt"
check "t1: worktree agent-memory is a real dir" test -d "$fix/wt/.claude/agent-memory"
check "t1: worktree agent-memory is NOT a symlink" test ! -L "$fix/wt/.claude/agent-memory"

# Test 2: copies main's memory into the worktree
fix="$(new_fixture t2)"
seed_main "$fix"
"$SCRIPT" "$fix/wt"
check "t2: prior memory file copied into worktree" test -f "$fix/wt/.claude/agent-memory/agent-x/prior.md"
content="$(cat "$fix/wt/.claude/agent-memory/agent-x/prior.md" 2>/dev/null || true)"
check_eq "t2: copied content matches" "prior memory" "$content"

# Test 3: a write into the seeded (real) dir succeeds and stays local
fix="$(new_fixture t3)"
seed_main "$fix"
"$SCRIPT" "$fix/wt"
echo "new" > "$fix/wt/.claude/agent-memory/agent-x/new.md"
check "t3: write into seeded dir lands in worktree" test -f "$fix/wt/.claude/agent-memory/agent-x/new.md"
check "t3: write did NOT leak into main repo" test ! -f "$fix/.claude/agent-memory/agent-x/new.md"

# Test 4: replaces a stale symlink (left by the old link-agent-memory) with a real dir
fix="$(new_fixture t4)"
seed_main "$fix"
mkdir -p "$fix/wt/.claude"
ln -s "$fix/.claude/agent-memory" "$fix/wt/.claude/agent-memory"
"$SCRIPT" "$fix/wt"
check "t4: stale symlink replaced by real dir" test ! -L "$fix/wt/.claude/agent-memory"
check "t4: real dir present after replacement" test -d "$fix/wt/.claude/agent-memory"

# Test 5: no-op when run against the main repo (no self-symlink, no error)
fix="$(new_fixture t5)"
seed_main "$fix"
"$SCRIPT" "$fix"
check "t5: main repo agent-memory not a symlink" test ! -L "$fix/.claude/agent-memory"

# Test 6: idempotent — a second run is a no-op that keeps a real dir
fix="$(new_fixture t6)"
seed_main "$fix"
"$SCRIPT" "$fix/wt"
"$SCRIPT" "$fix/wt"
check "t6: still a real dir after re-run" test -d "$fix/wt/.claude/agent-memory"
check "t6: still not a symlink after re-run" test ! -L "$fix/wt/.claude/agent-memory"

# Test 7: main repo with no agent-memory yet — seed still yields a real dir
fix="$(new_fixture t7)"
"$SCRIPT" "$fix/wt"
check "t7: real dir created even when main has no memory" test -d "$fix/wt/.claude/agent-memory"

# Test 7b: re-seed does not clobber a newer worktree file (copy-if-newer), and the
# sync lock dir in main never leaks into the worktree.
fix="$(new_fixture t7b)"
seed_main "$fix"
"$SCRIPT" "$fix/wt"
echo "worktree edit" > "$fix/wt/.claude/agent-memory/agent-x/prior.md"
touch -t 202612310000 "$fix/wt/.claude/agent-memory/agent-x/prior.md"
mkdir -p "$fix/.claude/agent-memory/.sync.lock.d"   # simulate a stray lock in main
"$SCRIPT" "$fix/wt"
check_eq "t7b: newer worktree file survives re-seed" "worktree edit" "$(cat "$fix/wt/.claude/agent-memory/agent-x/prior.md")"
check "t7b: sync lock dir not copied into worktree" test ! -e "$fix/wt/.claude/agent-memory/.sync.lock.d"

# Test 8: errors when invoked without the required argument
if "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: t8: should error when invoked without arg"; fail=$((fail + 1))
else
  echo "PASS: t8: errors without arg"; pass=$((pass + 1))
fi

echo "---"
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
