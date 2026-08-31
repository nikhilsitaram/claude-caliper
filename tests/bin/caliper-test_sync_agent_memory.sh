#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/sync-agent-memory"

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
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

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

# Test 1: individual memory files written in the worktree are copied into main
fix="$(new_fixture t1)"
mkdir -p "$fix/wt/.claude/agent-memory/agent-x"
echo "learned" > "$fix/wt/.claude/agent-memory/agent-x/learned.md"
"$SCRIPT" "$fix/wt"
check "t1: worktree memory file copied to main" test -f "$fix/.claude/agent-memory/agent-x/learned.md"
check_eq "t1: content preserved" "learned" "$(cat "$fix/.claude/agent-memory/agent-x/learned.md" 2>/dev/null || true)"

# Test 2: MEMORY.md is union-merged — main's entry AND the worktree's entry survive,
# with a single header line.
fix="$(new_fixture t2)"
mkdir -p "$fix/.claude/agent-memory/agent-x" "$fix/wt/.claude/agent-memory/agent-x"
printf '# Memory Index\n\n- [Main entry](main.md) — from main\n' > "$fix/.claude/agent-memory/agent-x/MEMORY.md"
printf '# Memory Index\n\n- [WT entry](wt.md) — from worktree\n' > "$fix/wt/.claude/agent-memory/agent-x/MEMORY.md"
"$SCRIPT" "$fix/wt"
merged="$fix/.claude/agent-memory/agent-x/MEMORY.md"
check "t2: main entry retained in merged MEMORY.md" grep -q "Main entry" "$merged"
check "t2: worktree entry added to merged MEMORY.md" grep -q "WT entry" "$merged"
header_count="$(grep -c '^# Memory Index$' "$merged" 2>/dev/null || echo 0)"
check_eq "t2: single header after union-merge" "1" "$header_count"

# Test 3: copy-if-newer — a main file NEWER than the worktree's copy is not clobbered
fix="$(new_fixture t3)"
mkdir -p "$fix/.claude/agent-memory/agent-x" "$fix/wt/.claude/agent-memory/agent-x"
echo "old worktree" > "$fix/wt/.claude/agent-memory/agent-x/shared.md"
touch -t 202601010000 "$fix/wt/.claude/agent-memory/agent-x/shared.md"
echo "newer main" > "$fix/.claude/agent-memory/agent-x/shared.md"
touch -t 202612310000 "$fix/.claude/agent-memory/agent-x/shared.md"
"$SCRIPT" "$fix/wt"
check_eq "t3: newer main file not clobbered by older worktree file" "newer main" "$(cat "$fix/.claude/agent-memory/agent-x/shared.md")"

# Test 3b: copy-if-newer — a worktree file NEWER than main's copy DOES update main
fix="$(new_fixture t3b)"
mkdir -p "$fix/.claude/agent-memory/agent-x" "$fix/wt/.claude/agent-memory/agent-x"
echo "old main" > "$fix/.claude/agent-memory/agent-x/shared.md"
touch -t 202601010000 "$fix/.claude/agent-memory/agent-x/shared.md"
echo "newer worktree" > "$fix/wt/.claude/agent-memory/agent-x/shared.md"
touch -t 202612310000 "$fix/wt/.claude/agent-memory/agent-x/shared.md"
"$SCRIPT" "$fix/wt"
check_eq "t3b: newer worktree file updates main" "newer worktree" "$(cat "$fix/.claude/agent-memory/agent-x/shared.md")"

# Test 4: memory survives `git worktree remove` after a sync
fix="$(new_fixture t4)"
mkdir -p "$fix/wt/.claude/agent-memory/agent-x"
echo "persistent" > "$fix/wt/.claude/agent-memory/agent-x/persistent.md"
"$SCRIPT" "$fix/wt"
git -C "$fix" worktree remove "$fix/wt" --force >/dev/null
check "t4: synced memory survives worktree removal" test -f "$fix/.claude/agent-memory/agent-x/persistent.md"

# Test 5: no-op when run against the main repo
fix="$(new_fixture t5)"
mkdir -p "$fix/.claude/agent-memory/agent-x"
echo "main only" > "$fix/.claude/agent-memory/agent-x/m.md"
"$SCRIPT" "$fix"
check "t5: main repo run leaves file intact" test -f "$fix/.claude/agent-memory/agent-x/m.md"

# Test 6: worktree agent-memory is a symlink (old broken state) — skip gracefully
fix="$(new_fixture t6)"
mkdir -p "$fix/.claude/agent-memory" "$fix/wt/.claude"
ln -s "$fix/.claude/agent-memory" "$fix/wt/.claude/agent-memory"
if "$SCRIPT" "$fix/wt" >/dev/null 2>&1; then
  echo "PASS: t6: symlinked worktree memory skipped without error"; pass=$((pass + 1))
else
  echo "FAIL: t6: errored on symlinked worktree memory"; fail=$((fail + 1))
fi

# Test 7: worktree has no agent-memory dir — no-op, no error
fix="$(new_fixture t7)"
if "$SCRIPT" "$fix/wt" >/dev/null 2>&1; then
  echo "PASS: t7: no-op when worktree has no memory"; pass=$((pass + 1))
else
  echo "FAIL: t7: errored when worktree has no memory"; fail=$((fail + 1))
fi

# Test 8: two worktrees syncing sequentially both persist (additive merge)
fix="$(new_fixture t8)"
git -C "$fix" worktree add -q "$fix/wt2" -b wt2-branch
mkdir -p "$fix/wt/.claude/agent-memory/agent-x" "$fix/wt2/.claude/agent-memory/agent-x"
echo "from wt1" > "$fix/wt/.claude/agent-memory/agent-x/wt1.md"
echo "from wt2" > "$fix/wt2/.claude/agent-memory/agent-x/wt2.md"
"$SCRIPT" "$fix/wt"
"$SCRIPT" "$fix/wt2"
check "t8: first worktree's memory persisted" test -f "$fix/.claude/agent-memory/agent-x/wt1.md"
check "t8: second worktree's memory persisted" test -f "$fix/.claude/agent-memory/agent-x/wt2.md"

# Test 9: errors without the required argument
if "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: t9: should error when invoked without arg"; fail=$((fail + 1))
else
  echo "PASS: t9: errors without arg"; pass=$((pass + 1))
fi

echo "---"
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
