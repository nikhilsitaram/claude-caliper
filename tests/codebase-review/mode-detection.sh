#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$REPO_ROOT/skills/codebase-review/mode-detect.sh"

pass=0
fail=0

# Each check runs the helper with given args/env, then asserts on
# stdout, stderr, and exit code.
run_helper() {
  # Args: env_assignments... -- helper_args...
  # Captures: STDOUT, STDERR, RC
  local env_kv=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    env_kv+=("$1"); shift
  done
  shift  # drop the --
  local tmp_out tmp_err
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  set +e
  env -i PATH="$PATH" "${env_kv[@]}" bash "$HELPER" "$@" \
    >"$tmp_out" 2>"$tmp_err"
  RC=$?
  set -e
  STDOUT="$(cat "$tmp_out")"; STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

assert() {
  local desc="$1"; local cond="$2"
  if eval "$cond"; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc"
    echo "  STDOUT: $STDOUT"
    echo "  STDERR: $STDERR"
    echo "  RC: $RC"
    fail=$((fail + 1))
  fi
}

# 1. No --mode: helper emits MODE=__ASK__ sentinel, exit 0
run_helper --
assert "no --mode emits ASK sentinel" '[[ "$STDOUT" == *"MODE=__ASK__"* && $RC -eq 0 ]]'

# 2. --mode=team with env var: MODE=team, empty stderr, exit 0
run_helper CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 -- --mode=team
assert "team mode with env var resolves to team" '[[ "$STDOUT" == *"MODE=team"* && -z "$STDERR" && $RC -eq 0 ]]'

# 3. --mode=team without env var: MODE=single, warning on stderr, exit 0
run_helper -- --mode=team
assert "team mode without env var downgrades to single" '[[ "$STDOUT" == *"MODE=single"* && "$STDERR" == *"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"* && $RC -eq 0 ]]'

# 4. --mode=foo: non-zero exit, stderr names valid values
run_helper -- --mode=foo
assert "invalid mode exits non-zero" '[[ $RC -ne 0 && "$STDERR" == *"single"* && "$STDERR" == *"team"* ]]'

# 5a. --mode= (empty value): invalid
run_helper -- --mode=
assert "empty --mode value is invalid" '[[ $RC -ne 0 ]]'

# 5b. --mode with no value: invalid
run_helper -- --mode
assert "bare --mode flag is invalid" '[[ $RC -ne 0 ]]'

# 6. Positional path + --mode=single: SCOPE_PATH and MODE both surface
run_helper -- path/to/dir --mode=single
assert "path arg surfaces as SCOPE_PATH" '[[ "$STDOUT" == *"SCOPE_PATH=path/to/dir"* && "$STDOUT" == *"MODE=single"* && $RC -eq 0 ]]'

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
