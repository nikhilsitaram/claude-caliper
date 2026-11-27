#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-phase-dispatch"
FIXTURE="$REPO_ROOT/tests/validate-plan/fixtures/valid-plan/plan.json"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
BASE="$(cd "$TMPDIR_BASE" && pwd -P)"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
  GIT_NAMESPACE GIT_PREFIX GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

check_match() {
  local desc="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # unquoted on purpose: $pattern is a glob
  if [[ "$actual" == $pattern ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (pattern=[$pattern] actual=[$actual])"; fail=$((fail + 1))
  fi
}

g() { git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"; }

# Main checkout with seedable agent memory and no .gitignore, so the seeded
# copy is untracked content a bare `worktree remove` would refuse — rollback
# has to cope with it.
MAIN="$BASE/main"
g init -q -b main "$MAIN"
g -C "$MAIN" commit -q --allow-empty -m base
mkdir -p "$MAIN/.claude/agent-memory/impl"
echo "remembered" > "$MAIN/.claude/agent-memory/impl/MEMORY.md"
FEAT="$MAIN/.claude/worktrees/feat"
g -C "$MAIN" worktree add -q "$FEAT" -b feat
g -C "$FEAT" commit -q --allow-empty -m feat-work
PHASE_B="$FEAT/.claude/worktrees/phase-b"
g -C "$FEAT" worktree add -q "$PHASE_B" -b phase-b
g -C "$PHASE_B" commit -q --allow-empty -m phase-b-work

PLAN_DIR="$BASE/plan"
mkdir -p "$PLAN_DIR"
PLAN="$PLAN_DIR/plan.json"
# One phase A, In Progress: A1 is dispatchable; A2 waits on A1.
single_plan() {
  jq '.status = "In Development" | .phases = [.phases[0] | .status = "In Progress"]' "$FIXTURE" > "$PLAN"
}
# Phases A (done) and B (In Progress): B1 is dispatchable from phase-b.
multi_plan() {
  jq '.status = "In Development"
      | .phases[0].status = "In Progress" | .phases[0].tasks[].status = "complete"
      | .phases[1].status = "In Progress"' "$FIXTURE" > "$PLAN"
}
status_of() { jq -r --arg id "$1" '.phases[].tasks[] | select(.id == $id) | .status' "$PLAN"; }
has_branch() { g -C "$MAIN" rev-parse --verify --quiet "refs/heads/$1" >/dev/null && echo yes || echo no; }

# Sets OUT (stdout), ERR (stderr) and RC. Runs from $RUN_CWD (default: main).
run() {
  RC=0
  OUT="$(cd "${RUN_CWD:-$MAIN}" && "$SCRIPT" "$@" 2>"$BASE/err")" || RC=$?
  ERR="$(cat "$BASE/err")"
}

remove_task_wt() {  # <parent> <branch>
  "$REPO_ROOT/bin/clear-worktree-scratch" "$1/.claude/worktrees/$2" >/dev/null
  g -C "$1" worktree remove "$1/.claude/worktrees/$2"
  g -C "$1" branch -D -q "$2"
}

echo "=== single-phase: feature worktree is the parent ==="
single_plan
RUN_CWD="$PHASE_B" run "$PLAN" "$FEAT" A1   # caller's CWD must not matter
check_eq "exit 0" 0 "$RC"
check_eq "stdout is exactly the task worktree path" "$FEAT/.claude/worktrees/a1" "$OUT"
check_eq "stdout is one line" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check_eq "task claimed in_progress" in_progress "$(status_of A1)"
check_eq "task branch forks from the parent's HEAD, not the caller's" \
  "$(g -C "$FEAT" rev-parse HEAD)" "$(g -C "$MAIN" rev-parse a1)"
check_eq "task worktree is on the task branch" a1 "$(g -C "$OUT" rev-parse --abbrev-ref HEAD)"
check_eq "agent memory seeded into the task worktree" remembered "$(cat "$OUT/.claude/agent-memory/impl/MEMORY.md" 2>/dev/null)"
remove_task_wt "$FEAT" a1

echo "=== multi-phase: nested phase worktree is the parent ==="
multi_plan
run "$PLAN" "$PHASE_B" B1
check_eq "exit 0" 0 "$RC"
check_eq "stdout is the path nested under the phase worktree" "$PHASE_B/.claude/worktrees/b1" "$OUT"
check_eq "task claimed in_progress" in_progress "$(status_of B1)"
check_eq "task branch forks from the phase HEAD" "$(g -C "$PHASE_B" rev-parse HEAD)" "$(g -C "$MAIN" rev-parse b1)"
remove_task_wt "$PHASE_B" b1

echo "=== multi-phase: parent on another phase's branch is refused ==="
multi_plan
jq '.phases[0].tasks[].status = "pending"' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
run "$PLAN" "$PHASE_B" A1
check_eq "exit 1" 1 "$RC"
check_match "names the phase worktree it needs" "*phase-a*" "$ERR"
check_eq "task stays pending" pending "$(status_of A1)"
check_eq "no branch created" no "$(has_branch a1)"

echo "=== multi-phase: integration (feature) worktree is refused ==="
multi_plan
run "$PLAN" "$FEAT" B1
check_eq "exit 1" 1 "$RC"
check_match "names the phase worktree it needs" "*phase-b*" "$ERR"
check_eq "task stays pending" pending "$(status_of B1)"
check_eq "no branch created" no "$(has_branch b1)"

echo "=== main checkout is refused ==="
single_plan
run "$PLAN" "$MAIN" A1
check_eq "exit 1" 1 "$RC"
check_match "says main checkout" "*main checkout*" "$ERR"
check_eq "task stays pending" pending "$(status_of A1)"
check_eq "no branch created" no "$(has_branch a1)"

echo "=== a subdirectory of a worktree is refused ==="
mkdir -p "$FEAT/sub"
run "$PLAN" "$FEAT/sub" A1
check_eq "exit 1" 1 "$RC"
check_match "says not a worktree root" "*not a worktree root*" "$ERR"
check_eq "no branch created" no "$(has_branch a1)"
rmdir "$FEAT/sub"

echo "=== detached parent is refused ==="
DET="$MAIN/.claude/worktrees/det"
g -C "$MAIN" worktree add -q --detach "$DET"
run "$PLAN" "$DET" A1
check_eq "exit 1" 1 "$RC"
check_match "says detached" "*detached*" "$ERR"
check_eq "no branch created" no "$(has_branch a1)"
g -C "$MAIN" worktree remove "$DET"

echo "=== only pending tasks are dispatched ==="
for st in in_progress complete skipped; do
  single_plan
  jq --arg s "$st" '.phases[0].tasks[0].status = $s' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
  run "$PLAN" "$FEAT" A1
  check_eq "$st task: exit 1" 1 "$RC"
  check_eq "$st task: status unchanged" "$st" "$(status_of A1)"
  check_eq "$st task: no branch created" no "$(has_branch a1)"
done

echo "=== unknown task is refused ==="
single_plan
run "$PLAN" "$FEAT" Z9
check_eq "exit 1" 1 "$RC"
check_match "says task_not_found" "*task_not_found*" "$ERR"

echo "=== a surviving task branch is refused and left intact ==="
single_plan
g -C "$FEAT" branch a1
STRANDED="$(g -C "$MAIN" commit-tree "$(g -C "$MAIN" rev-parse 'a1^{tree}')" -p a1 -m stranded)"
g -C "$MAIN" update-ref refs/heads/a1 "$STRANDED"
run "$PLAN" "$FEAT" A1
check_eq "exit 1" 1 "$RC"
check_match "points at Resuming" "*Resuming*" "$ERR"
check_eq "stranded branch keeps its commit" "$STRANDED" "$(g -C "$MAIN" rev-parse a1)"
check_eq "task stays pending" pending "$(status_of A1)"
g -C "$MAIN" branch -D -q a1

echo "=== an existing worktree directory is refused and left intact ==="
mkdir -p "$FEAT/.claude/worktrees/a1"
touch "$FEAT/.claude/worktrees/a1/keep"
run "$PLAN" "$FEAT" A1
check_eq "exit 1" 1 "$RC"
check_eq "directory content survives" yes "$([[ -e "$FEAT/.claude/worktrees/a1/keep" ]] && echo yes || echo no)"
check_eq "no branch created" no "$(has_branch a1)"
rm -rf "$FEAT/.claude/worktrees/a1"

echo "=== a failed claim rolls back the worktree and branch ==="
single_plan
run "$PLAN" "$FEAT" A2    # depends on A1, still pending: validate-plan refuses
check_eq "exit nonzero" 1 "$((RC != 0))"
check_eq "nothing on stdout" "" "$OUT"
check_match "relays the claim's refusal" "*dependencies not complete*" "$ERR"
check_eq "task stays pending" pending "$(status_of A2)"
check_eq "task branch removed" no "$(has_branch a2)"
check_eq "task worktree removed" no "$([[ -e "$FEAT/.claude/worktrees/a2" ]] && echo yes || echo no)"
check_eq "worktree unregistered" 0 "$(g -C "$MAIN" worktree list --porcelain | grep -c '/a2$' || true)"

echo "=== a failed seed rolls back before the claim ==="
single_plan
FAKE_BIN="$BASE/fakebin"
mkdir -p "$FAKE_BIN"
cp "$REPO_ROOT"/bin/* "$FAKE_BIN/"   # real siblings; only the seed is stubbed
printf '#!/usr/bin/env bash\necho "seed boom" >&2\nexit 1\n' > "$FAKE_BIN/seed-agent-memory"
chmod +x "$FAKE_BIN"/*
RC=0
OUT="$(cd "$MAIN" && "$FAKE_BIN/caliper-phase-dispatch" "$PLAN" "$FEAT" A1 2>"$BASE/err")" || RC=$?
check_eq "exit nonzero" 1 "$((RC != 0))"
check_eq "task never claimed" pending "$(status_of A1)"
check_eq "task branch removed" no "$(has_branch a1)"
check_eq "task worktree removed" no "$([[ -e "$FEAT/.claude/worktrees/a1" ]] && echo yes || echo no)"

echo "=== a claim that lands before validate-plan fails is kept, not rolled back ==="
single_plan
CLAIM_BIN="$BASE/claimbin"
mkdir -p "$CLAIM_BIN"
cp "$REPO_ROOT"/bin/* "$CLAIM_BIN/"   # real siblings; validate-plan writes, then fails
printf '#!/usr/bin/env bash\n"%s" "$@"\nexit 1\n' "$REPO_ROOT/bin/validate-plan" > "$CLAIM_BIN/validate-plan"
chmod +x "$CLAIM_BIN"/*
RC=0
OUT="$(cd "$MAIN" && "$CLAIM_BIN/caliper-phase-dispatch" "$PLAN" "$FEAT" A1 2>"$BASE/err")" || RC=$?
ERR="$(cat "$BASE/err")"
check_eq "exit nonzero" 1 "$((RC != 0))"
check_eq "task left claimed" in_progress "$(status_of A1)"
check_eq "task branch kept" yes "$(has_branch a1)"
check_eq "task worktree kept" yes "$([[ -d "$FEAT/.claude/worktrees/a1" ]] && echo yes || echo no)"
check_match "says to settle it" "*validate-plan failed after claiming A1*Resuming In-Flight Tasks*" "$ERR"
remove_task_wt "$FEAT" a1

echo "=== a worktree add that registers then fails is rolled back ==="
single_plan
mkdir -p "$BASE/hooks"
printf '#!/bin/sh\nexit 1\n' > "$BASE/hooks/post-checkout"
chmod +x "$BASE/hooks/post-checkout"
g -C "$MAIN" config core.hooksPath "$BASE/hooks"
run "$PLAN" "$FEAT" A1
g -C "$MAIN" config --unset core.hooksPath
check_eq "exit nonzero" 1 "$((RC != 0))"
check_eq "task never claimed" pending "$(status_of A1)"
check_eq "task branch removed" no "$(has_branch a1)"
check_eq "task worktree removed" no "$([[ -e "$FEAT/.claude/worktrees/a1" ]] && echo yes || echo no)"
check_eq "worktree unregistered" 0 "$(g -C "$MAIN" worktree list --porcelain | grep -c '/a1$' || true)"

echo "=== an inherited GIT_DIR doesn't redirect the helper ==="
single_plan
RC=0
OUT="$(cd "$MAIN" && GIT_DIR="$BASE/nowhere" "$SCRIPT" "$PLAN" "$FEAT" A1 2>"$BASE/err")" || RC=$?
check_eq "exit 0" 0 "$RC"
check_eq "task worktree created under the named parent" "$FEAT/.claude/worktrees/a1" "$OUT"
remove_task_wt "$FEAT" a1

# Python .venv mirroring (issue #337). The stub stands in for
# caliper-python-bootstrap: it logs its target and builds a .venv there with
# the helper's self-ignoring .gitignore. PY_FAIL makes it fail.
VENV_BIN="$BASE/venvbin"
mkdir -p "$VENV_BIN"
cp "$REPO_ROOT"/bin/* "$VENV_BIN/"   # real siblings; only the Python bootstrap is stubbed
cat > "$VENV_BIN/caliper-python-bootstrap" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$BASE/pylog"
echo "installing…"
[[ -z "\${PY_FAIL:-}" ]] || { echo "py boom" >&2; exit 1; }
mkdir -p "\$1/.venv/bin" && echo '*' > "\$1/.venv/.gitignore" && touch "\$1/.venv/bin/python"
EOF
chmod +x "$VENV_BIN"/*
run_venv() {
  : > "$BASE/pylog"
  RC=0
  OUT="$(cd "$MAIN" && "$VENV_BIN/caliper-phase-dispatch" "$@" 2>"$BASE/err")" || RC=$?
  ERR="$(cat "$BASE/err")"
}

echo "=== a parent .venv is mirrored by a task-local one ==="
single_plan
mkdir -p "$FEAT/.venv"
run_venv "$PLAN" "$FEAT" A1
check_eq "exit 0" 0 "$RC"
check_eq "stdout is still exactly the task worktree path" "$FEAT/.claude/worktrees/a1" "$OUT"
check_eq "bootstrap ran on the task worktree" "$FEAT/.claude/worktrees/a1" "$(cat "$BASE/pylog")"
check_eq "task worktree has its own .venv" yes "$([[ -d "$OUT/.venv" && ! -L "$OUT/.venv" ]] && echo yes || echo no)"
check_eq "task claimed in_progress" in_progress "$(status_of A1)"
remove_task_wt "$FEAT" a1   # no-force remove succeeds: the .venv ignores itself

echo "=== no parent .venv: no bootstrap ==="
rm -rf "$FEAT/.venv"
single_plan
run_venv "$PLAN" "$FEAT" A1
check_eq "exit 0" 0 "$RC"
check_eq "bootstrap not run" "" "$(cat "$BASE/pylog")"
remove_task_wt "$FEAT" a1

echo "=== a symlinked parent .venv is left alone ==="
single_plan
mkdir -p "$BASE/shared-venv"
ln -s "$BASE/shared-venv" "$FEAT/.venv"
run_venv "$PLAN" "$FEAT" A1
check_eq "exit 0" 0 "$RC"
check_eq "bootstrap not run" "" "$(cat "$BASE/pylog")"
remove_task_wt "$FEAT" a1
rm "$FEAT/.venv"

echo "=== a failed bootstrap rolls back before the claim ==="
single_plan
mkdir -p "$FEAT/.venv"
PY_FAIL=1 run_venv "$PLAN" "$FEAT" A1
check_eq "exit nonzero" 1 "$((RC != 0))"
check_eq "nothing on stdout" "" "$OUT"
check_match "relays the bootstrap's error" "*py boom*" "$ERR"
check_eq "task never claimed" pending "$(status_of A1)"
check_eq "task branch removed" no "$(has_branch a1)"
check_eq "task worktree removed" no "$([[ -e "$FEAT/.claude/worktrees/a1" ]] && echo yes || echo no)"

echo "=== a failed claim rolls back a worktree holding a built .venv ==="
single_plan
run_venv "$PLAN" "$FEAT" A2    # depends on A1: the claim refuses after the bootstrap
check_eq "exit nonzero" 1 "$((RC != 0))"
check_eq "bootstrap ran first" "$FEAT/.claude/worktrees/a2" "$(cat "$BASE/pylog")"
check_eq "task stays pending" pending "$(status_of A2)"
check_eq "task branch removed" no "$(has_branch a2)"
check_eq "task worktree removed" no "$([[ -e "$FEAT/.claude/worktrees/a2" ]] && echo yes || echo no)"
rm -rf "$FEAT/.venv"

echo "=== usage ==="
run "$PLAN" "$FEAT"
check_eq "two args: exit 1" 1 "$RC"
check_match "prints usage" "Usage:*" "$ERR"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
