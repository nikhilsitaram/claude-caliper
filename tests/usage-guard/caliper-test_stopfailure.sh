#!/usr/bin/env bash
# Tests for the StopFailure backstop trio (#261):
#   guard-marker.sh (active-run marker) -> stopfailure-resume.sh (rate_limit hook)
#   -> pending-resume.sh (SessionStart surfacing).
# macOS/BSD only (stopfailure-resume.sh -> compute-fire.sh uses `date -r`).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MARKER_SH="$REPO_ROOT/skills/usage-guard/scripts/guard-marker.sh"
STOPFAIL_SH="$REPO_ROOT/skills/usage-guard/scripts/stopfailure-resume.sh"
PENDING_SH="$REPO_ROOT/skills/usage-guard/scripts/pending-resume.sh"

if ! date -r 0 >/dev/null 2>&1; then
  echo "SKIP: StopFailure backstop tests require BSD date (-r epoch); not available here."
  exit 0
fi

pass=0; fail=0
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
STATE="$DIR/state.json"
MARKER="$DIR/active-guard.json"
PENDING="$DIR/pending-resume.json"
now="$(date +%s)"
future=$(( (now/3600 + 2)*3600 + 17*60 ))     # a future :17, hours out

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
STDIN="" run "$MARKER_SH" clear
assert "marker clear removes the file"      '[[ ! -f "$MARKER" ]]'
STDIN="" run "$MARKER_SH" clear
assert "marker clear is idempotent (exit 0)" '[[ $RC -eq 0 ]]'
STDIN="" run "$MARKER_SH" bogus
assert "marker bad subcommand -> exit 64"   '[[ $RC -eq 64 ]]'

# --- stopfailure-resume.sh: NO-OP without an active marker ---
reset_files
printf '{"resets_at":%s,"captured_at":%s,"seven_day":{"resets_at":null,"used_percentage":null}}' "$future" "$now" > "$STATE"
STDIN='{"hook_event_name":"StopFailure"}' run "$STOPFAIL_SH"
assert "no marker -> exit 0"                '[[ $RC -eq 0 ]]'
assert "no marker -> no pending file"       '[[ ! -f "$PENDING" ]]'

# --- stopfailure-resume.sh: with marker, computes fire from last-known resets_at ---
STDIN="ORIGINAL TASK: grind Y
OPEN: z" run "$MARKER_SH" set
STDIN='{"hook_event_name":"StopFailure"}' run "$STOPFAIL_SH"
assert "marker present -> exit 0"           '[[ $RC -eq 0 ]]'
assert "marker present -> pending written"  '[[ -f "$PENDING" ]]'
assert "pending is valid JSON"              'jq -e . "$PENDING" >/dev/null'
assert "pending reason recorded"            '[[ "$(jq -r .reason "$PENDING")" == "stopfailure-rate_limit" ]]'
assert "pending fire_epoch from 5h reset"   "[[ \$(jq -r .fire_epoch \"\$PENDING\") -ge $future ]]"
assert "pending carries the payload"        '[[ "$(jq -r .payload "$PENDING")" == *"ORIGINAL TASK: grind Y"* ]]'

# --- stopfailure-resume.sh: no resets_at -> fire_epoch null (not lost) ---
reset_files
echo '{"captured_at":'"$now"'}' > "$STATE"     # no resets_at
STDIN="OPEN: w" run "$MARKER_SH" set
STDIN='{}' run "$STOPFAIL_SH"
assert "no resets_at -> pending still written" '[[ -f "$PENDING" ]]'
assert "no resets_at -> fire_epoch null"       '[[ "$(jq -r .fire_epoch "$PENDING")" == "null" ]]'

# --- pending-resume.sh: NO-OP when nothing pending ---
reset_files
STDIN='{"hook_event_name":"SessionStart"}' run "$PENDING_SH"
assert "no pending -> exit 0"               '[[ $RC -eq 0 ]]'
assert "no pending -> no output"            '[[ -z "$OUT" ]]'

# --- pending-resume.sh: DUE (fire in the past) -> resume instruction + payload ---
printf '{"created_at":%s,"reason":"stopfailure-rate_limit","fire_epoch":%s,"cron":null,"payload":"OPEN: finish the migration"}' \
  "$now" "$(( now - 120 ))" > "$PENDING"
STDIN='{}' run "$PENDING_SH"
assert "due pending -> valid JSON output"   'jq -e . <<<"$OUT" >/dev/null'
assert "due pending -> SessionStart context" '[[ "$(jq -r .hookSpecificOutput.hookEventName <<<"$OUT")" == "SessionStart" ]]'
assert "due pending -> says resume"         '[[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$OUT")" == *"Resume the remaining work"* ]]'
assert "due pending -> carries payload"     '[[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$OUT")" == *"finish the migration"* ]]'

# --- pending-resume.sh: NOT-due (fire in the future) -> hold, do not resume ---
printf '{"fire_epoch":%s,"payload":"OPEN: later"}' "$future" > "$PENDING"
STDIN='{}' run "$PENDING_SH"
assert "not-due pending -> says not due"    '[[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$OUT")" == *"Not due yet"* ]]'
assert "not-due pending -> does NOT say resume now" '[[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$OUT")" != *"Resume the remaining work"* ]]'

# --- pending-resume.sh: null fire_epoch -> treated as due ---
printf '{"fire_epoch":null,"payload":"OPEN: asap"}' > "$PENDING"
STDIN='{}' run "$PENDING_SH"
assert "null fire_epoch -> due (resume now)" '[[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$OUT")" == *"Resume the remaining work"* ]]'

echo "----"
echo "stopfailure-backstop: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
