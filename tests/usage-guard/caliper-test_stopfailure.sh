#!/usr/bin/env bash
# Tests for the StopFailure breadcrumb backstop (#261):
#   guard-marker.sh (active-run marker) -> stopfailure-resume.sh (rate_limit hook
#   that records an interrupted --queue run). The skill picks the breadcrumb up on
#   the next /usage-guard run; there is no SessionStart auto-resume hook.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MARKER_SH="$REPO_ROOT/skills/usage-guard/scripts/guard-marker.sh"
STOPFAIL_SH="$REPO_ROOT/skills/usage-guard/scripts/stopfailure-resume.sh"

pass=0; fail=0
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
STATE="$DIR/state.json"
MARKER="$DIR/active-guard.json"
PENDING="$DIR/pending-resume.json"

assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "PASS: $desc"; pass=$((pass+1))
  else echo "FAIL: $desc"; echo "  cond: $cond"; fail=$((fail+1)); fi
}
# Run a helper with QUEUE_STATE_FILE pointed at the temp dir; capture out/rc.
run() {
  local helper="$1"; shift
  local tmp_out; tmp_out="$(mktemp)"
  set +e
  printf '%s' "${STDIN:-}" | env QUEUE_STATE_FILE="$STATE" PATH="$PATH" HOME="$HOME" \
    bash "$helper" "$@" >"$tmp_out" 2>/dev/null
  RC=$?
  set -e
  OUT="$(cat "$tmp_out")"; rm -f "$tmp_out"
}
reset_files() { rm -f "$MARKER" "$PENDING"; }

# --- guard-marker.sh set / clear ---
STDIN="ORIGINAL TASK: refactor X
DONE: a, b
OPEN: c, d" run "$MARKER_SH" set
assert "marker set exits 0"                 '[[ $RC -eq 0 ]]'
assert "marker file written"                '[[ -f "$MARKER" ]]'
assert "marker is valid JSON"               'jq -e . "$MARKER" >/dev/null'
assert "marker carries the payload"         '[[ "$(jq -r .payload "$MARKER")" == *"ORIGINAL TASK: refactor X"* ]]'
assert "marker stamps the cwd"              '[[ "$(jq -r .cwd "$MARKER")" == "$PWD" ]]'
STDIN="" run "$MARKER_SH" clear
assert "marker clear removes the file"      '[[ ! -f "$MARKER" ]]'
STDIN="" run "$MARKER_SH" clear
assert "marker clear is idempotent (exit 0)" '[[ $RC -eq 0 ]]'
STDIN="" run "$MARKER_SH" bogus
assert "marker bad subcommand -> exit 64"   '[[ $RC -eq 64 ]]'

# --- stopfailure-resume.sh: NO-OP without an active marker ---
reset_files
STDIN='{"hook_event_name":"StopFailure"}' run "$STOPFAIL_SH"
assert "no marker -> exit 0"                '[[ $RC -eq 0 ]]'
assert "no marker -> no breadcrumb file"    '[[ ! -f "$PENDING" ]]'

# --- stopfailure-resume.sh: with marker, records a breadcrumb ---
STDIN="ORIGINAL TASK: grind Y
OPEN: z" run "$MARKER_SH" set
STDIN='{"hook_event_name":"StopFailure"}' run "$STOPFAIL_SH"
assert "marker present -> exit 0"           '[[ $RC -eq 0 ]]'
assert "marker present -> breadcrumb written" '[[ -f "$PENDING" ]]'
assert "breadcrumb is valid JSON"           'jq -e . "$PENDING" >/dev/null'
assert "breadcrumb reason recorded"         '[[ "$(jq -r .reason "$PENDING")" == "stopfailure-rate_limit" ]]'
assert "breadcrumb stamps interrupted_at"   '[[ "$(jq -r .interrupted_at "$PENDING")" -gt 0 ]]'
assert "breadcrumb carries the task payload" '[[ "$(jq -r .payload "$PENDING")" == *"ORIGINAL TASK: grind Y"* ]]'
assert "breadcrumb carries the cwd"         '[[ "$(jq -r .cwd "$PENDING")" == "$PWD" ]]'

# --- breadcrumb does not depend on the state file (no fire-time computation) ---
reset_files
rm -f "$STATE"                               # no state file at all
STDIN="OPEN: w" run "$MARKER_SH" set
STDIN='{}' run "$STOPFAIL_SH"
assert "no state file -> breadcrumb still written" '[[ -f "$PENDING" ]]'
assert "no state file -> exit 0"            '[[ $RC -eq 0 ]]'

echo "----"
echo "stopfailure-breadcrumb: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
