#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/.github/scripts/check-version-bump"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
BASE="$(cd "$TMPDIR_BASE" && pwd -P)"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
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

R="$BASE/repo"
g() { git -C "$R" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"; }
set_version() {
  mkdir -p "$R/.claude-plugin"
  jq -n --arg v "$1" '{name: "m", plugins: [{name: "caliper", version: $v, source: "./"}]}' \
    > "$R/.claude-plugin/marketplace.json"
}
# Fresh repo: main at <base-version> with one file in each tree, then a
# `feature` branch checked out from it.
fresh() {
  local f
  rm -rf "$R"; mkdir -p "$R"
  git init -q -b main "$R"
  set_version "$1"
  mkdir -p "$R/skills/x" "$R/agents" "$R/bin" "$R/hooks" "$R/docs" "$R/tests"
  for f in skills/x/SKILL.md agents/a.md bin/b hooks/h.sh docs/d.md tests/t.sh defaults.json README.md CLAUDE.md; do
    echo base > "$R/$f"
  done
  g add -A; g commit -q -m base
  g checkout -q -b feature
}
change() {  # <msg> <file>...
  local msg="$1" f; shift
  for f in "$@"; do echo "changed" >> "$R/$f"; done
  g add -A; g commit -q -m "$msg"
}
# Sets OUT (stdout+stderr) and RC.
run() {
  RC=0
  OUT="$(cd "$R" && "$SCRIPT" "$@" 2>&1)" || RC=$?
}

echo "=== shipped change with a bump passes ==="
fresh 3.0.4
set_version 3.0.5
change skill skills/x/SKILL.md
run main
check_eq "exit 0" 0 "$RC"

echo "=== shipped change without a bump fails ==="
fresh 3.0.4
change skill skills/x/SKILL.md
run main
check_eq "exit 1" 1 "$RC"
check_match "names both versions" "*3.0.4*3.0.4*" "$OUT"
check_match "names the shipped file" "*skills/x/SKILL.md*" "$OUT"

echo "=== every shipped tree requires a bump ==="
for f in agents/a.md bin/b hooks/h.sh defaults.json; do
  fresh 3.0.4
  change "touch $f" "$f"
  run main
  check_eq "$f: exit 1" 1 "$RC"
done

echo "=== non-shipped changes need no bump ==="
fresh 3.0.4
change docs docs/d.md tests/t.sh README.md CLAUDE.md
mkdir -p "$R/.github/workflows" && echo x > "$R/.github/workflows/w.yml"
g add -A; g commit -q -m ci
run main
check_eq "exit 0" 0 "$RC"

echo "=== moving a file out of a shipped tree requires a bump ==="
fresh 3.0.4
g mv skills/x/SKILL.md docs/moved.md
g commit -q -m "retire skill"
run main
check_eq "exit 1 (the old shipped path counts, not just the rename target)" 1 "$RC"
check_match "names the removed shipped path" "*skills/x/SKILL.md*" "$OUT"

echo "=== base moved to the PR's version after it forked ==="
fresh 3.0.4
set_version 3.0.5
change skill skills/x/SKILL.md
g checkout -q main
set_version 3.0.5
change other agents/a.md
g checkout -q feature
run main
check_eq "exit 1 (equal to the base tip, though above the merge-base)" 1 "$RC"

echo "=== version below the base fails ==="
fresh 3.0.4
set_version 3.0.3
change skill skills/x/SKILL.md
run main
check_eq "exit 1" 1 "$RC"

echo "=== comparison is numeric, field by field ==="
fresh 3.0.9
set_version 3.0.10
change skill skills/x/SKILL.md
run main
check_eq "3.0.9 -> 3.0.10: exit 0" 0 "$RC"
fresh 3.9.0
set_version 3.10.0
change skill skills/x/SKILL.md
run main
check_eq "3.9.0 -> 3.10.0: exit 0" 0 "$RC"
fresh 3.1.0
set_version 3.0.99
change skill skills/x/SKILL.md
run main
check_eq "3.1.0 -> 3.0.99: exit 1" 1 "$RC"

echo "=== errors ==="
run
check_eq "no args: exit 2" 2 "$RC"
run nosuchref
check_eq "unknown base ref: exit 2" 2 "$RC"
fresh 3.0.4
set_version banana
change skill skills/x/SKILL.md
run main
check_eq "non-numeric version: exit 2" 2 "$RC"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
