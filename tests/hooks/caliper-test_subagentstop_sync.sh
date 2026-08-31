#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/subagentstop-sync-agent-memory.sh"

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

# Feed the hook a SubagentStop stdin payload.
run_hook() {
  echo "{\"cwd\": \"$1\", \"hook_event_name\": \"SubagentStop\"}" | "$HOOK"
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

# Test 1: hook syncs the worktree's memory to the main repo using cwd from stdin
fix="$(new_fixture t1)"
mkdir -p "$fix/wt/.claude/agent-memory/agent-x"
echo "learned" > "$fix/wt/.claude/agent-memory/agent-x/learned.md"
run_hook "$fix/wt"
check "t1: hook synced worktree memory to main" test -f "$fix/.claude/agent-memory/agent-x/learned.md"

# Test 2: memory survives worktree removal after the hook fires
fix="$(new_fixture t2)"
mkdir -p "$fix/wt/.claude/agent-memory/agent-x"
echo "persistent" > "$fix/wt/.claude/agent-memory/agent-x/persistent.md"
run_hook "$fix/wt"
git -C "$fix" worktree remove "$fix/wt" --force >/dev/null
check "t2: memory survives worktree removal" test -f "$fix/.claude/agent-memory/agent-x/persistent.md"

# Test 3: missing cwd field -> exit 0, no error
if echo '{"hook_event_name": "SubagentStop"}' | "$HOOK" >/dev/null 2>&1; then
  echo "PASS: t3: exits 0 when cwd absent"; pass=$((pass + 1))
else
  echo "FAIL: t3: errored when cwd absent"; fail=$((fail + 1))
fi

# Test 3b: malformed (non-JSON) stdin -> exit 0, never the blocking code. jq exits
# non-zero on bad input; under set -e that would propagate as exit 2 (the
# SubagentStop blocking code) unless swallowed.
if printf 'not json at all' | "$HOOK" >/dev/null 2>&1; then
  echo "PASS: t3b: exits 0 on malformed stdin (does not block)"; pass=$((pass + 1))
else
  echo "FAIL: t3b: blocked on malformed stdin"; fail=$((fail + 1))
fi

# Test 4: non-existent / non-git cwd -> exit 0, non-blocking
if run_hook "$TMPDIR_BASE/does-not-exist" >/dev/null 2>&1; then
  echo "PASS: t4: exits 0 for non-existent cwd"; pass=$((pass + 1))
else
  echo "FAIL: t4: errored on non-existent cwd"; fail=$((fail + 1))
fi

# Test 5: cwd is the main repo -> no-op, exits 0
fix="$(new_fixture t5)"
if run_hook "$fix" >/dev/null 2>&1; then
  echo "PASS: t5: exits 0 when cwd is the main repo"; pass=$((pass + 1))
else
  echo "FAIL: t5: errored when cwd is the main repo"; fail=$((fail + 1))
fi

echo "---"
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
