#!/usr/bin/env bash
set -euo pipefail

# validate-plan warns (stderr, exit unchanged) when the plan dir lives inside a
# linked git worktree — it is deleted with that worktree (gh issue #288).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/bin/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
WARNING="inside a linked git worktree"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

# pwd -P: git reports physical paths (macOS /var -> /private/var).
TMPDIR=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMPDIR"' EXIT

MAIN="$TMPDIR/main"
WT="$MAIN/.claude/worktrees/feature"
git init -q "$MAIN"
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q "$WT" -b feature

seed_plan() {
  mkdir -p "$1"
  cp -r "$FIXTURES/valid-plan/"* "$1/"
}

MAIN_PLAN="$MAIN/.claude/claude-caliper/2026-01-01-topic"
WT_PLAN="$WT/.claude/claude-caliper/2026-01-01-topic"
NOGIT_PLAN="$TMPDIR/nogit/plan"
seed_plan "$MAIN_PLAN"
seed_plan "$WT_PLAN"
seed_plan "$NOGIT_PLAN"

echo "=== plan location warning ==="

echo "Test 1: --schema warns on stderr for a plan inside a linked worktree, exit unchanged"
rc=0
stderr=$("$VALIDATE" --schema "$WT_PLAN/plan.json" 2>&1 >/dev/null) || rc=$?
if [[ $rc -eq 0 && "$stderr" == *"$WARNING"* ]]; then pass "worktree plan warns, exit 0"; else fail "worktree plan: rc=$rc stderr=$stderr"; fi

echo "Test 2: the warning names the main-checkout plan dir to move to"
if [[ "$stderr" == *"$MAIN/.claude/claude-caliper"* ]]; then pass "warning names main-checkout path"; else fail "warning lacks main path: $stderr"; fi

echo "Test 3: the warning stays off stdout"
stdout=$("$VALIDATE" --schema "$WT_PLAN/plan.json" 2>/dev/null)
if [[ "$stdout" != *"$WARNING"* ]]; then pass "stdout clean"; else fail "warning leaked to stdout"; fi

echo "Test 4: --schema is silent for a plan in the main checkout"
stderr=$("$VALIDATE" --schema "$MAIN_PLAN/plan.json" 2>&1 >/dev/null) || true
if [[ "$stderr" != *"$WARNING"* ]]; then pass "main checkout silent"; else fail "main checkout warned: $stderr"; fi

echo "Test 5: --schema is silent outside any git repo"
stderr=$("$VALIDATE" --schema "$NOGIT_PLAN/plan.json" 2>&1 >/dev/null) || true
if [[ "$stderr" != *"$WARNING"* ]]; then pass "non-git silent"; else fail "non-git warned: $stderr"; fi

echo "Test 6: --check-entry warns even before plan.json exists (draft-plan entry gate)"
rm "$WT_PLAN/plan.json"
stderr=$("$VALIDATE" --check-entry "$WT_PLAN/plan.json" --stage draft-plan 2>&1 >/dev/null) || true
if [[ "$stderr" == *"$WARNING"* ]]; then pass "check-entry warns without plan.json"; else fail "check-entry silent: $stderr"; fi

echo "Test 7: in a submodule, the warning names the submodule checkout, not its git dir"
# A submodule's git dir is <super>/.git/modules/<name>, so stripping /.git from
# it would point the user inside the git dir.
git init -q "$TMPDIR/subsrc"
git -C "$TMPDIR/subsrc" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git init -q "$TMPDIR/super"
git -C "$TMPDIR/super" -c protocol.file.allow=always submodule -q add "$TMPDIR/subsrc" sub
SUB_WT="$TMPDIR/super/sub/.claude/worktrees/feature"
git -C "$TMPDIR/super/sub" worktree add -q "$SUB_WT" -b feature
seed_plan "$SUB_WT/.claude/claude-caliper/2026-01-01-topic"
stderr=$("$VALIDATE" --schema "$SUB_WT/.claude/claude-caliper/2026-01-01-topic/plan.json" 2>&1 >/dev/null) || true
if [[ "$stderr" == *"main checkout under $TMPDIR/super/sub/.claude/claude-caliper/"* ]]; then pass "submodule warning names the submodule checkout"; else fail "submodule warning: $stderr"; fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
