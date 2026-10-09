#!/usr/bin/env bash
# --set-base persists where the phase and final review ranges start, so a
# resumed orchestrate run reads the original base instead of re-capturing HEAD
# after tasks have merged (gh issue #296).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/bin/validate-plan"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$desc"; else fail "$desc (expected '$expected', got '$actual')"; fi
}

assert_fail() {
  local desc="$1"; shift
  local expected_error="$1"; shift
  local output
  if output=$("$@" 2>&1); then
    fail "$desc (expected failure, got success)"
  elif echo "$output" | grep -qF -- "$expected_error"; then
    pass "$desc"
  else
    fail "$desc (expected '$expected_error' in output, got: $output)"
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
REPO="$TMPDIR/repo"
PLAN="$TMPDIR/plan/plan.json"

git_commit() {
  git -C "$REPO" -c user.email="test@test.com" -c user.name="Test" commit --allow-empty -q -m "$1"
}

# The plan lives outside the repo (as it does under $MAIN_ROOT/.claude), and
# --set-base resolves its rev in the caller's CWD — the lead's worktree.
vp() { (cd "$REPO" && "$VALIDATE" "$@"); }

setup() {
  rm -rf "${TMPDIR:?}/"*
  mkdir -p "$REPO" "$TMPDIR/plan"
  git -C "$REPO" init -q -b main
  git_commit "init"
  cp -r "$FIXTURES/valid-plan/"* "$TMPDIR/plan/"
}

mutate() {
  jq "$1" "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
}

echo "=== plan level ==="

setup
head1=$(git -C "$REPO" rev-parse HEAD)
out=$(vp --set-base "$PLAN" --plan --sha HEAD)
assert_eq "first write prints the resolved SHA" "$head1" "$out"
assert_eq "first write stores the full SHA, not the rev" "$head1" "$(jq -r '.base_sha' "$PLAN")"

before=$(cat "$PLAN")
out=$(vp --set-base "$PLAN" --plan --sha HEAD)
assert_eq "identical repeat prints the stored SHA" "$head1" "$out"
assert_eq "identical repeat leaves plan.json untouched" "$before" "$(cat "$PLAN")"

out=$(vp --set-base "$PLAN" --plan --sha "${head1:0:10}")
assert_eq "abbreviated SHA of the stored base is an identical repeat" "$head1" "$out"

git_commit "task merged"
assert_fail "different SHA refused" "base_sha_conflict: plan base_sha is already $head1" \
  vp --set-base "$PLAN" --plan --sha HEAD
assert_eq "refused write keeps the first base" "$head1" "$(jq -r '.base_sha' "$PLAN")"

if [[ -e "$PLAN.lock" ]]; then fail "refusal leaves no lock behind"; else pass "refusal leaves no lock behind"; fi

echo "=== phase level ==="

setup
head1=$(git -C "$REPO" rev-parse HEAD)
vp --set-base "$PLAN" --phase A --sha HEAD > /dev/null
assert_eq "phase write stores base on that phase" "$head1" "$(jq -r '.phases[0].base_sha' "$PLAN")"
assert_eq "phase write leaves the plan base unset" "null" "$(jq -r '.base_sha' "$PLAN")"
assert_eq "phase write leaves other phases unset" "null" "$(jq -r '.phases[1].base_sha' "$PLAN")"

git_commit "A1 merged"
head2=$(git -C "$REPO" rev-parse HEAD)
assert_fail "phase: different SHA refused" "base_sha_conflict: phase A base_sha is already $head1" \
  vp --set-base "$PLAN" --phase A --sha HEAD
out=$(vp --set-base "$PLAN" --phase B --sha HEAD)
assert_eq "each phase keeps its own first write" "$head2" "$out"
assert_eq "phase A base survives phase B write" "$head1" "$(jq -r '.phases[0].base_sha' "$PLAN")"

echo "=== tasks and render unaffected ==="

setup
tasks_before=$(jq -c '[.phases[].tasks]' "$PLAN")
vp --render "$PLAN"
md_before=$(cat "$TMPDIR/plan/plan.md")
vp --set-base "$PLAN" --plan --sha HEAD > /dev/null
vp --set-base "$PLAN" --phase A --sha HEAD > /dev/null
assert_eq "tasks unchanged by --set-base" "$tasks_before" "$(jq -c '[.phases[].tasks]' "$PLAN")"
assert_eq "plan.md unchanged by --set-base (render ignores base_sha)" "$md_before" "$(cat "$TMPDIR/plan/plan.md")"
if vp --schema "$PLAN" > /dev/null 2>&1; then
  pass "plan with recorded bases passes --schema"
else
  fail "plan with recorded bases passes --schema ($(vp --schema "$PLAN" 2>&1))"
fi

echo "=== argument errors ==="

setup
before=$(cat "$PLAN")
assert_fail "unresolvable rev refused" "invalid_sha: 'no-such-ref'" \
  vp --set-base "$PLAN" --plan --sha no-such-ref
assert_fail "unknown phase refused" "phase_not_found: 'Z'" \
  vp --set-base "$PLAN" --phase Z --sha HEAD
assert_fail "missing --sha refused" "--set-base requires" \
  vp --set-base "$PLAN" --plan
assert_fail "missing target refused" "--set-base requires" \
  vp --set-base "$PLAN" --sha HEAD
assert_fail "--task target refused" "--set-base requires" \
  vp --set-base "$PLAN" --task A1 --sha HEAD
assert_eq "refused calls leave plan.json untouched" "$before" "$(cat "$PLAN")"

echo "=== --schema validates base_sha ==="

sha40=$(printf 'a%.0s' {1..40})
sha64=$(printf 'b%.0s' {1..64})
setup
mutate ".base_sha = \"$sha40\" | .phases[0].base_sha = \"$sha64\""
if vp --schema "$PLAN" > /dev/null 2>&1; then pass "40- and 64-hex base_sha accepted"; else fail "40- and 64-hex base_sha accepted ($(vp --schema "$PLAN" 2>&1))"; fi

setup
mutate '.base_sha = 42'
assert_fail "non-string plan base_sha rejected" "invalid_base_sha: plan" vp --schema "$PLAN"

setup
mutate '.base_sha = "HEAD"'
assert_fail "symbolic rev as plan base_sha rejected" "invalid_base_sha: plan" vp --schema "$PLAN"

setup
mutate '.phases[1].base_sha = ""'
assert_fail "empty phase base_sha rejected" "invalid_base_sha: phase B" vp --schema "$PLAN"

setup
mutate ".phases[0].base_sha = \"${sha40:0:12}\""
assert_fail "abbreviated phase base_sha rejected" "invalid_base_sha: phase A" vp --schema "$PLAN"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
