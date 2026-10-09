#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-main-root"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
BASE="$(cd "$TMPDIR_BASE" && pwd -P)"

# Isolate from the host's git config (a global core.worktree or excludes file
# would change what the layouts below look like).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

check_fails() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $desc"; fail=$((fail + 1))
  else
    echo "PASS: $desc"; pass=$((pass + 1))
  fi
}

g() { git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false -c protocol.file.allow=always "$@"; }

# stdout only; stderr goes to "$BASE/err" for the WARN assertions.
root_of() { "$SCRIPT" "$@" 2>"$BASE/err"; }

# Test 1: normal repo — main checkout, a subdirectory, and a nested linked worktree.
g init -q "$BASE/norm"
g -C "$BASE/norm" commit -q --allow-empty -m init
mkdir -p "$BASE/norm/src"
g -C "$BASE/norm" worktree add -q "$BASE/norm/.claude/worktrees/x" -b x
check_eq "t1: main checkout" "$BASE/norm" "$(root_of "$BASE/norm")"
check_eq "t1: subdirectory of main" "$BASE/norm" "$(root_of "$BASE/norm/src")"
check_eq "t1: nested linked worktree" "$BASE/norm" "$(root_of "$BASE/norm/.claude/worktrees/x")"
check_eq "t1: no warning for a normal repo" "" "$(cat "$BASE/err")"
check_eq "t1: defaults to the current directory" "$BASE/norm" "$(cd "$BASE/norm/.claude/worktrees/x" && "$SCRIPT" 2>/dev/null)"

# Test 2: submodule — its git dir lives in the superproject's .git/modules/, and
# core.worktree points back at the checkout.
g init -q "$BASE/subsrc"
g -C "$BASE/subsrc" commit -q --allow-empty -m init
g init -q "$BASE/super"
g -C "$BASE/super" submodule -q add "$BASE/subsrc" sub
g -C "$BASE/super/sub" worktree add -q "$BASE/sub-wt" -b w
check_eq "t2: submodule main checkout" "$BASE/super/sub" "$(root_of "$BASE/super/sub")"
check_eq "t2: submodule linked worktree" "$BASE/super/sub" "$(root_of "$BASE/sub-wt")"
check_eq "t2: no warning for a submodule" "" "$(cat "$BASE/err")"

# Test 3: --separate-git-dir — the main checkout resolves exactly; from a linked
# worktree git records no path back to it, so fall back to the git dir and warn.
g init -q --separate-git-dir "$BASE/sep.gitdir" "$BASE/sep"
g -C "$BASE/sep" commit -q --allow-empty -m init
g -C "$BASE/sep" worktree add -q "$BASE/sep-wt" -b w
check_eq "t3: separate-git-dir main checkout" "$BASE/sep" "$(root_of "$BASE/sep")"
check_eq "t3: linked worktree falls back to the git dir" "$BASE/sep.gitdir" "$(root_of "$BASE/sep-wt")"
check_eq "t3: fallback warns" "1" "$(grep -c '^WARN:' "$BASE/err" || true)"

# Test 4: bare repo with worktrees — there is no main checkout by design, so the
# git dir is the shared home and no warning is due.
g init -q --bare "$BASE/bare.git"
g -C "$BASE/norm" push -q "$BASE/bare.git" HEAD:refs/heads/main
g -C "$BASE/bare.git" worktree add -q "$BASE/bare-wt" main
check_eq "t4: bare repo's linked worktree resolves to the bare dir" "$BASE/bare.git" "$(root_of "$BASE/bare-wt")"
check_eq "t4: no warning for a bare repo" "" "$(cat "$BASE/err")"

# Test 5: errors.
mkdir -p "$BASE/plain"
check_fails "t5: non-repo directory exits non-zero" "$SCRIPT" "$BASE/plain"
check_fails "t5: nonexistent path exits non-zero" "$SCRIPT" "$BASE/missing"
check_fails "t5: extra arguments exit non-zero" "$SCRIPT" "$BASE/norm" extra

echo ""
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
