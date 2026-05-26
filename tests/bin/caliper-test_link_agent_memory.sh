#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/link-agent-memory"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'chmod -R u+w "$TMPDIR_BASE" 2>/dev/null; rm -rf "$TMPDIR_BASE"' EXIT

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc"
    fail=$((fail + 1))
  fi
}

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=$expected actual=$actual)"
    fail=$((fail + 1))
  fi
}

# Build a fresh main repo + nested worktree fixture. Returns the main-repo path,
# canonicalized via `pwd -P` so macOS's /var → /private/var symlink does not
# trip path-equality assertions (git rev-parse resolves to the canonical form).
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

# Test 1: creates symlink pointing at the main repo's agent-memory dir
fix="$(new_fixture t1)"
"$SCRIPT" "$fix/wt"
check "t1: symlink created at worktree path" test -L "$fix/wt/.claude/agent-memory"
check "t1: target dir exists in main repo" test -d "$fix/.claude/agent-memory"
target="$(readlink -- "$fix/wt/.claude/agent-memory")"
check_eq "t1: symlink target matches main repo path" "$fix/.claude/agent-memory" "$target"

# Test 2: idempotent — second invocation is a silent no-op
fix="$(new_fixture t2)"
"$SCRIPT" "$fix/wt"
"$SCRIPT" "$fix/wt"
check "t2: idempotent (still a symlink after re-run)" test -L "$fix/wt/.claude/agent-memory"

# Test 3: fails loudly when a real directory already occupies the link path
fix="$(new_fixture t3)"
mkdir -p "$fix/wt/.claude/agent-memory"
if "$SCRIPT" "$fix/wt" >/dev/null 2>&1; then
  echo "FAIL: t3: should fail when real dir exists at link path"
  fail=$((fail + 1))
else
  echo "PASS: t3: fails loudly on real-dir conflict"
  pass=$((pass + 1))
fi

# Test 4: no-op when run against the main repo itself
fix="$(new_fixture t4)"
"$SCRIPT" "$fix"
check "t4: main repo unchanged (no self-symlink)" test ! -L "$fix/.claude/agent-memory"

# Test 5: writes through the symlink land in the main repo
fix="$(new_fixture t5)"
"$SCRIPT" "$fix/wt"
mkdir -p "$fix/wt/.claude/agent-memory/some-agent"
echo "memory content" > "$fix/wt/.claude/agent-memory/some-agent/MEMORY.md"
check "t5: write through symlink reaches main repo" test -f "$fix/.claude/agent-memory/some-agent/MEMORY.md"
content="$(cat "$fix/.claude/agent-memory/some-agent/MEMORY.md" 2>/dev/null || true)"
check_eq "t5: content preserved through symlink" "memory content" "$content"

# Test 6: memory survives `git worktree remove`
fix="$(new_fixture t6)"
"$SCRIPT" "$fix/wt"
mkdir -p "$fix/wt/.claude/agent-memory/agent-x"
echo "persistent" > "$fix/wt/.claude/agent-memory/agent-x/MEMORY.md"
git -C "$fix" worktree remove "$fix/wt" --force >/dev/null
check "t6: main repo memory file survives worktree removal" test -f "$fix/.claude/agent-memory/agent-x/MEMORY.md"

# Test 7: errors when invoked without the required argument
if "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: t7: should error when invoked without arg"
  fail=$((fail + 1))
else
  echo "PASS: t7: errors without arg"
  pass=$((pass + 1))
fi

echo "---"
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
