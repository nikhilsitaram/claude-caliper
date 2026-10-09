#!/usr/bin/env bash
set -euo pipefail

# caliper-draft moves plan documents between $PLAN_DIR (main checkout) and the
# session's draft at <worktree>/.caliper-draft/ (gh issue #306). Its narrow
# `Bash(caliper-draft:*)` rule approves any arguments, so the confinement
# checks here are the security boundary.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-draft"

pass=0
fail=0
TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# A host-level excludesfile could hide the untracked files these tests look for.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMPDIR_BASE/xdg"

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc"; fail=$((fail + 1))
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

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

run_from() {
  local dir="$1"; shift
  (cd "$dir" && "$@")
}

# Caliper's layout: the feature worktree nests under main's .claude/worktrees/,
# and plan dirs live under main's .claude/claude-caliper/.
MAIN="$TMPDIR_BASE/main"
WT="$MAIN/.claude/worktrees/feat"
PLAN_DIR="$MAIN/.claude/claude-caliper/2026-01-01-topic"
git init -q -b main "$MAIN"
git -C "$MAIN" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q "$WT" -b feat
mkdir -p "$PLAN_DIR" "$TMPDIR_BASE/outside"

write_draft() {  # write_draft <name> <content> — what the Write tool does
  mkdir -p "$WT/.caliper-draft"
  printf '%s\n' "$2" > "$WT/.caliper-draft/$1"
}

# Test 1: push installs the draft into the plan dir and prints the target.
write_draft plan.json '{"v":1}'
out="$(run_from "$WT" "$SCRIPT" push "$PLAN_DIR/plan.json")"
check_eq "t1: push copies the draft into the plan dir" '{"v":1}' "$(cat "$PLAN_DIR/plan.json")"
check_eq "t1: push prints the installed path" "$PLAN_DIR/plan.json" "$out"
write_draft design-topic.md '# Design'
check "t1: push accepts a design-*.md doc" run_from "$WT" "$SCRIPT" push "$PLAN_DIR/design-topic.md"
check_eq "t1: design doc installed" '# Design' "$(cat "$PLAN_DIR/design-topic.md")"

# Test 2: the draft directory ignores itself, so a draft never shows as
# untracked — no accidental commit, no blocked bare `git worktree remove`.
check "t2: draft dir has a .gitignore" test -f "$WT/.caliper-draft/.gitignore"
check_eq "t2: worktree status is clean with drafts present" "" "$(git -C "$WT" status --porcelain)"

# Test 3: pull refreshes the draft from the plan dir and prints the draft path.
printf '%s\n' '{"v":2}' > "$PLAN_DIR/plan.json"
out="$(run_from "$WT" "$SCRIPT" pull "$PLAN_DIR/plan.json")"
check_eq "t3: pull overwrites the draft with the plan-dir copy" '{"v":2}' "$(cat "$WT/.caliper-draft/plan.json")"
check_eq "t3: pull prints the draft path" "$WT/.caliper-draft/plan.json" "$out"
# The draft lives at the worktree root whichever subdirectory the caller is in.
mkdir -p "$WT/sub/dir"
printf '%s\n' '{"v":3}' > "$PLAN_DIR/plan.json"
check "t3: pull from a subdirectory succeeds" run_from "$WT/sub/dir" "$SCRIPT" pull "$PLAN_DIR/plan.json"
check_eq "t3: subdirectory pull lands at the worktree root" '{"v":3}' "$(cat "$WT/.caliper-draft/plan.json")"
check "t3: no draft dir under the subdirectory" test ! -e "$WT/sub/dir/.caliper-draft"
# A first pull (no draft dir yet) creates the self-ignoring dir too.
rm -rf "$WT/.caliper-draft"
check "t3: pull creates a missing draft dir" run_from "$WT" "$SCRIPT" pull "$PLAN_DIR/plan.json"
check_eq "t3: first pull leaves the worktree clean" "" "$(git -C "$WT" status --porcelain)"

# Test 4: push refuses any target that resolves outside main's plan root, and
# writes nothing there.
write_draft plan.json '{"evil":true}'
mkdir -p "$MAIN/elsewhere" "$MAIN/.claude/claude-caliper/../escape"
check_fails "t4: target outside .claude/claude-caliper refused" run_from "$WT" "$SCRIPT" push "$MAIN/elsewhere/plan.json"
check "t4: nothing written outside the root" test ! -e "$MAIN/elsewhere/plan.json"
check_fails "t4: .. traversal out of the root refused" run_from "$WT" "$SCRIPT" push "$MAIN/.claude/claude-caliper/../escape/plan.json"
check "t4: nothing written via traversal" test ! -e "$MAIN/.claude/escape/plan.json"
ln -s "$TMPDIR_BASE/outside" "$MAIN/.claude/claude-caliper/linked"
check_fails "t4: plan dir symlinked outside the root refused" run_from "$WT" "$SCRIPT" push "$MAIN/.claude/claude-caliper/linked/plan.json"
check "t4: nothing written through the symlinked dir" test ! -e "$TMPDIR_BASE/outside/plan.json"
# A plan dir inside the worktree is deleted with it (#288) — not main's root.
mkdir -p "$WT/.claude/claude-caliper/2026-01-01-topic"
check_fails "t4: the worktree's own plan root refused" run_from "$WT" "$SCRIPT" push "$WT/.claude/claude-caliper/2026-01-01-topic/plan.json"
# Another repo's plan root is not this repo's.
OTHER="$TMPDIR_BASE/other"
git init -q -b main "$OTHER"
mkdir -p "$OTHER/.claude/claude-caliper/2026-01-01-topic"
check_fails "t4: another repo's plan root refused" run_from "$WT" "$SCRIPT" push "$OTHER/.claude/claude-caliper/2026-01-01-topic/plan.json"
check "t4: nothing written into the other repo" test ! -e "$OTHER/.claude/claude-caliper/2026-01-01-topic/plan.json"

# Test 5: only plan.json and design-*.md move — never the files that steer
# caliper (.design-approved flips the session to acceptEdits; reviews.json
# holds the review gates) or the rendered plan.md.
for name in .design-approved reviews.json plan.md notes.txt design-x.txt; do
  write_draft "$name" 'x'
  check_fails "t5: push refuses $name" run_from "$WT" "$SCRIPT" push "$PLAN_DIR/$name"
  check "t5: $name not written" test ! -e "$PLAN_DIR/$name"
done
printf 'x\n' > "$PLAN_DIR/reviews.json"
check_fails "t5: pull refuses reviews.json" run_from "$WT" "$SCRIPT" pull "$PLAN_DIR/reviews.json"

# Test 6: a symlink at the target is refused, never written through.
printf '%s\n' 'precious' > "$TMPDIR_BASE/outside/target"
ln -sf "$TMPDIR_BASE/outside/target" "$PLAN_DIR/design-link.md"
write_draft design-link.md 'overwrite'
check_fails "t6: symlinked target refused" run_from "$WT" "$SCRIPT" push "$PLAN_DIR/design-link.md"
check_eq "t6: symlink target untouched" "precious" "$(cat "$TMPDIR_BASE/outside/target")"
mkdir -p "$PLAN_DIR/design-dir.md"
write_draft design-dir.md 'x'
check_fails "t6: directory target refused" run_from "$WT" "$SCRIPT" push "$PLAN_DIR/design-dir.md"
check_eq "t6: nothing written into the directory" "" "$(ls -A "$PLAN_DIR/design-dir.md")"
# A symlinked source is refused too, so neither copy can read a file from
# outside the draft or the plan root.
printf '%s\n' 'secret' > "$TMPDIR_BASE/outside/secret"
rm -f "$WT/.caliper-draft/design-src.md"
ln -s "$TMPDIR_BASE/outside/secret" "$WT/.caliper-draft/design-src.md"
check_fails "t6: symlinked draft refused on push" run_from "$WT" "$SCRIPT" push "$PLAN_DIR/design-src.md"
check "t6: nothing pushed from the symlinked draft" test ! -e "$PLAN_DIR/design-src.md"
rm "$WT/.caliper-draft/design-src.md"
ln -s "$TMPDIR_BASE/outside/secret" "$PLAN_DIR/design-src.md"
check_fails "t6: symlinked plan-dir file refused on pull" run_from "$WT" "$SCRIPT" pull "$PLAN_DIR/design-src.md"
check "t6: nothing pulled from the symlinked plan-dir file" test ! -e "$WT/.caliper-draft/design-src.md"
# pull's target is the draft: a symlinked draft dir is refused too.
mv "$WT/.caliper-draft" "$TMPDIR_BASE/draft-moved"
ln -s "$TMPDIR_BASE/outside" "$WT/.caliper-draft"
check_fails "t6: symlinked draft dir refused" run_from "$WT" "$SCRIPT" pull "$PLAN_DIR/plan.json"
check "t6: nothing written through the draft-dir symlink" test ! -e "$TMPDIR_BASE/outside/plan.json"
rm "$WT/.caliper-draft"
mv "$TMPDIR_BASE/draft-moved" "$WT/.caliper-draft"

# Test 7: missing inputs.
rm -f "$WT/.caliper-draft/design-none.md"
check_fails "t7: push without a draft fails" run_from "$WT" "$SCRIPT" push "$PLAN_DIR/design-none.md"
check_fails "t7: pull of a missing plan-dir file fails" run_from "$WT" "$SCRIPT" pull "$PLAN_DIR/design-none.md"
check_fails "t7: missing plan dir fails" run_from "$WT" "$SCRIPT" push "$MAIN/.claude/claude-caliper/no-such-dir/plan.json"
check "t7: missing plan dir is not created" test ! -e "$MAIN/.claude/claude-caliper/no-such-dir"
mkdir -p "$TMPDIR_BASE/plain"
check_fails "t7: outside a git repo fails" run_from "$TMPDIR_BASE/plain" "$SCRIPT" push "$PLAN_DIR/plan.json"
NOROOT="$TMPDIR_BASE/noroot"
git init -q -b main "$NOROOT"
mkdir -p "$NOROOT/plans"
check_fails "t7: repo without a plan root fails" run_from "$NOROOT" "$SCRIPT" push "$NOROOT/plans/plan.json"

# Test 8: seam with clear-worktree-scratch — a worktree holding pushed drafts
# still takes a bare `git worktree remove`, and the plan survives in main.
WT2="$MAIN/.claude/worktrees/seam"
git -C "$MAIN" worktree add -q "$WT2" -b seam
mkdir -p "$WT2/.caliper-draft"
printf '%s\n' '{"seam":1}' > "$WT2/.caliper-draft/plan.json"
check "t8: push from the seam worktree" run_from "$WT2" "$SCRIPT" push "$PLAN_DIR/plan.json"
check "t8: clear-worktree-scratch succeeds" run_from "$MAIN" "$REPO_ROOT/bin/clear-worktree-scratch" "$WT2"
check "t8: bare git worktree remove succeeds" git -C "$MAIN" worktree remove "$WT2"
check_eq "t8: installed plan outlives the worktree" '{"seam":1}' "$(cat "$PLAN_DIR/plan.json")"

# Test 9: the plan root is the one design builds $PLAN_DIR under
# (caliper-main-root), also when the main checkout's git dir lives elsewhere
# (--separate-git-dir) and stripping `/.git` from the common dir would miss it.
SEP="$TMPDIR_BASE/sep"
git init -q -b main --separate-git-dir "$TMPDIR_BASE/sep.gitdir" "$SEP"
git -C "$SEP" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$SEP" worktree add -q "$SEP/.claude/worktrees/feat" -b feat
mkdir -p "$SEP/.claude/claude-caliper/2026-01-01-topic" "$SEP/.claude/worktrees/feat/.caliper-draft"
printf '%s\n' '{"sep":1}' > "$SEP/.claude/worktrees/feat/.caliper-draft/plan.json"
check "t9: push from a --separate-git-dir worktree" run_from "$SEP/.claude/worktrees/feat" "$SCRIPT" push "$SEP/.claude/claude-caliper/2026-01-01-topic/plan.json"
check_eq "t9: plan installed in the main checkout's root" '{"sep":1}' "$(cat "$SEP/.claude/claude-caliper/2026-01-01-topic/plan.json" 2>/dev/null || true)"

# Test 10: argument errors.
check_fails "t10: no args" run_from "$WT" "$SCRIPT"
check_fails "t10: unknown subcommand" run_from "$WT" "$SCRIPT" copy "$PLAN_DIR/plan.json"
check_fails "t10: missing path" run_from "$WT" "$SCRIPT" push
check_fails "t10: extra argument" run_from "$WT" "$SCRIPT" push "$PLAN_DIR/plan.json" extra

echo ""
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
