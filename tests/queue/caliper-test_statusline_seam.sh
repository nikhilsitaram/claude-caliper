#!/usr/bin/env bash
# Integration test for the state-file contract: statusline-wrapper.sh (the sole
# PRODUCER) -> ~/.claude/queue/state.json -> compute-fire.sh + check-usage.sh
# (the two CONSUMERS). Unit tests cover each consumer with hand-built fixtures;
# this one feeds a representative Claude Code statusline JSON blob through the
# real wrapper and then runs both consumers against the file it actually wrote,
# so the producer/consumer JSON shape is verified end-to-end (not mocked).
#
# macOS/BSD only: the consumers use `date -r <epoch>`; skips on GNU date.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="$REPO_ROOT/skills/queue/scripts/statusline-wrapper.sh"
COMPUTE_FIRE="$REPO_ROOT/skills/queue/scripts/compute-fire.sh"
CHECK_USAGE="$REPO_ROOT/skills/usage-guard/scripts/check-usage.sh"

# The consumers require BSD `date -r <epoch>`; skip the whole seam if absent.
if ! date -r 0 >/dev/null 2>&1; then
  echo "SKIP: state-file seam test requires BSD date (-r epoch); not available here."
  exit 0
fi

pass=0; fail=0
STATE="$(mktemp)"; rm -f "$STATE"            # start with NO file; wrapper creates it
trap 'rm -f "$STATE"' EXIT
now="$(date +%s)"
future=$(( (now/3600 + 2)*3600 + 17*60 ))    # a future :17 local, hours out

assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "PASS: $desc"; pass=$((pass+1))
  else echo "FAIL: $desc"; echo "  cond: $cond"; fail=$((fail+1)); fi
}

# Pipe a statusline JSON blob through the real wrapper with an EXTERNAL renderer
# (QUEUE_STATUSLINE=cat) — lets us assert the wrapper forwards stdin unchanged.
# Returns the renderer's stdout in FWD.
produce() {
  rm -f "$STATE"
  FWD="$(printf '%s' "$1" | env QUEUE_STATE_FILE="$STATE" QUEUE_STATUSLINE="cat" \
    PATH="$PATH" HOME="$HOME" bash "$WRAPPER")"
}
# Pipe a blob through the wrapper with NO external renderer (QUEUE_STATUSLINE
# unset) — exercises the built-in line. Returns the rendered line in OUT.
render() {
  rm -f "$STATE"
  OUT="$(printf '%s' "$1" | env -u QUEUE_STATUSLINE QUEUE_STATE_FILE="$STATE" \
    PATH="$PATH" HOME="$HOME" bash "$WRAPPER")"
}
# Run a consumer against whatever the wrapper wrote; capture out/err/rc.
run() {
  local helper="$1"; shift
  local tmp_out tmp_err
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  set +e
  env QUEUE_STATE_FILE="$STATE" PATH="$PATH" HOME="$HOME" bash "$helper" "$@" \
    >"$tmp_out" 2>"$tmp_err"
  RC=$?
  set -e
  STDOUT="$(cat "$tmp_out")"; STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}
field() { echo "$STDOUT" | sed -n "s/^$1=//p"; }

# --- Producer writes a consumable state file from a full blob ---
blob="{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future,\"used_percentage\":40.5}},\"model\":{\"id\":\"x\"}}"
produce "$blob"
assert "wrapper creates the state file"        '[[ -f "$STATE" ]]'
assert "wrapper writes valid JSON"             'jq -e . "$STATE" >/dev/null'
assert "state resets_at matches input"         "[[ \"\$(jq -r .resets_at \"\$STATE\")\" == \"$future\" ]]"
assert "state used_percentage matches input"   '[[ "$(jq -r .used_percentage "$STATE")" == "40.5" ]]'
assert "state captured_at is recent"           '[[ "$(jq -r .captured_at "$STATE")" -ge '"$(( now - 5 ))"' ]]'
assert "wrapper forwards stdin unchanged"       '[[ "$FWD" == "$blob" ]]'

# --- Consumer 1: compute-fire consumes the real producer output ---
run "$COMPUTE_FIRE"
assert "compute-fire consumes wrapper output (exit 0)" '[[ $RC -eq 0 ]]'
assert "compute-fire MODE=reset"                       '[[ "$(field MODE)" == "reset" ]]'
assert "compute-fire emits a CRON"                     '[[ -n "$(field CRON)" ]]'
assert "compute-fire sees fresh capture (STALE=no)"    '[[ "$(field STALE)" == "no" ]]'

# --- Consumer 2: check-usage consumes the real producer output ---
run "$CHECK_USAGE"
assert "check-usage consumes wrapper output (exit 0 under 99)" '[[ $RC -eq 0 ]]'
assert "check-usage reads the used_percentage (40.5)"          '[[ "$(field USED_PCT)" == "40.5" ]]'
assert "check-usage VERDICT=UNDER"                             '[[ "$(field VERDICT)" == "UNDER" ]]'
assert "check-usage emits STALE=no on fresh capture"           '[[ "$(field STALE)" == "no" ]]'

# --- Producer emits used_percentage:null when the field is absent ---
# (the shape the consumer unit-tests hand-build as a missing key — assert the
#  wrapper's REAL output is what the consumers actually face.)
produce "{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future}}}"
assert "wrapper always writes used_percentage key"  '[[ "$(jq -r "has(\"used_percentage\")" "$STATE")" == "true" ]]'
assert "absent used_percentage -> null"             '[[ "$(jq -r .used_percentage "$STATE")" == "null" ]]'
run "$COMPUTE_FIRE"
assert "compute-fire still works without used_pct"  '[[ $RC -eq 0 ]]'
run "$CHECK_USAGE"
assert "check-usage -> exit 2 on null used_pct"     '[[ $RC -eq 2 ]]'

# --- Producer sanitizes a non-numeric used_percentage to null (still valid JSON) ---
produce "{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future,\"used_percentage\":\"N/A\"}}}"
assert "non-numeric used_percentage -> still valid JSON" 'jq -e . "$STATE" >/dev/null'
assert "non-numeric used_percentage -> null"             '[[ "$(jq -r .used_percentage "$STATE")" == "null" ]]'
run "$CHECK_USAGE"
assert "check-usage -> exit 2 on sanitized-null used_pct" '[[ $RC -eq 2 ]]'

# Leading/trailing-dot forms (.5, 40., .) are invalid JSON numbers AND not a
# usable percentage — they must reduce to null, never be interpolated raw.
for bad in '"40."' '".5"' '"."'; do
  produce "{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future,\"used_percentage\":$bad}}}"
  assert "malformed used_percentage $bad -> valid JSON" 'jq -e . "$STATE" >/dev/null'
  assert "malformed used_percentage $bad -> null"       '[[ "$(jq -r .used_percentage "$STATE")" == "null" ]]'
done

# --- Producer guards a non-numeric resets_at instead of writing corrupt JSON ---
# Without the guard, an ISO-8601 resets_at would be interpolated raw and produce
# an unparseable file that misleads both consumers.
produce "{\"rate_limits\":{\"five_hour\":{\"resets_at\":\"2026-06-24T21:00:00Z\",\"used_percentage\":40}}}"
assert "non-numeric resets_at -> no state file written" '[[ ! -f "$STATE" ]]'
run "$COMPUTE_FIRE"
assert "compute-fire reports no-data (exit 1) not corruption" '[[ $RC -eq 1 ]]'

# --- No rate_limits at all (free tier / pre-first-response): nothing written ---
produce '{"model":{"id":"x"}}'
assert "blob without rate_limits -> no state file" '[[ ! -f "$STATE" ]]'

# --- seven_day window captured alongside five_hour (#260) ---
future7=$(( future + 7*86400 ))              # a distinct 7-day reset, a week out
produce "{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future,\"used_percentage\":40.5},\"seven_day\":{\"resets_at\":$future7,\"used_percentage\":12.3}}}"
assert "both windows -> valid JSON"               'jq -e . "$STATE" >/dev/null'
assert "five_hour stays top-level (backcompat)"   "[[ \"\$(jq -r .resets_at \"\$STATE\")\" == \"$future\" ]]"
assert "seven_day.resets_at captured"             "[[ \"\$(jq -r .seven_day.resets_at \"\$STATE\")\" == \"$future7\" ]]"
assert "seven_day.used_percentage captured"       '[[ "$(jq -r .seven_day.used_percentage "$STATE")" == "12.3" ]]'
# check-usage targets each window independently via --window.
run "$CHECK_USAGE"
assert "check-usage default reads 5h (40.5)"      '[[ "$(field USED_PCT)" == "40.5" ]]'
assert "check-usage default WINDOW=5h"            '[[ "$(field WINDOW)" == "5h" ]]'
run "$CHECK_USAGE" --window 7d
assert "check-usage --window 7d reads 7d (12.3)"  '[[ "$(field USED_PCT)" == "12.3" ]]'
assert "check-usage --window 7d WINDOW=7d"        '[[ "$(field WINDOW)" == "7d" ]]'
assert "check-usage --window 7d UNDER (exit 0)"   '[[ $RC -eq 0 ]]'
# compute-fire reset mode can target the weekly reset.
run "$COMPUTE_FIRE" --window 7d
assert "compute-fire --window 7d exit 0"          '[[ $RC -eq 0 ]]'
assert "compute-fire --window 7d MODE=reset"      '[[ "$(field MODE)" == "reset" ]]'
assert "compute-fire --window 7d WINDOW=7d"       '[[ "$(field WINDOW)" == "7d" ]]'

# --- five_hour present, seven_day absent: stable shape, 7d reads as unavailable ---
produce "{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future,\"used_percentage\":40.5}}}"
assert "seven_day sub-object always written"      '[[ "$(jq -r "has(\"seven_day\")" "$STATE")" == "true" ]]'
assert "absent 7d -> seven_day.resets_at null"    '[[ "$(jq -r .seven_day.resets_at "$STATE")" == "null" ]]'
run "$CHECK_USAGE" --window 7d
assert "check-usage --window 7d -> exit 2 (no 7d)" '[[ $RC -eq 2 ]]'
run "$COMPUTE_FIRE" --window 7d
assert "compute-fire --window 7d -> exit 2 (no 7d)" '[[ $RC -eq 2 ]]'

# --- seven_day present, five_hour absent: file still written, 5h reads as null ---
produce "{\"rate_limits\":{\"seven_day\":{\"resets_at\":$future7,\"used_percentage\":12.3}}}"
assert "only-7d blob still writes state file"     '[[ -f "$STATE" ]]'
assert "only-7d -> top-level resets_at null"      '[[ "$(jq -r .resets_at "$STATE")" == "null" ]]'
assert "only-7d -> seven_day populated"           "[[ \"\$(jq -r .seven_day.resets_at \"\$STATE\")\" == \"$future7\" ]]"
run "$CHECK_USAGE"
assert "check-usage default -> exit 2 (no 5h)"    '[[ $RC -eq 2 ]]'
run "$CHECK_USAGE" --window 7d
assert "check-usage --window 7d reads 7d (exit 0)" '[[ $RC -eq 0 ]]'
run "$COMPUTE_FIRE"
assert "compute-fire default -> exit 2 (no 5h)"   '[[ $RC -eq 2 ]]'
run "$COMPUTE_FIRE" --window 7d
assert "compute-fire --window 7d exit 0 (has 7d)" '[[ $RC -eq 0 ]]'

# --- Built-in render path (no external statusline tool installed) ---
# Works standalone: the wrapper renders its own line and still taps the state.
tmpdir="$(mktemp -d)"; trap 'rm -f "$STATE"; rm -rf "$tmpdir"' EXIT   # non-git dir
exp_hm="$(date -r "$future" +%H:%M)"
render "{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future,\"used_percentage\":40.5}},\"model\":{\"display_name\":\"Opus 4.8\"},\"workspace\":{\"current_dir\":\"$tmpdir\"}}"
assert "built-in: still taps state file"        '[[ -f "$STATE" ]]'
assert "built-in: shows dir basename"           '[[ "$OUT" == *"${tmpdir##*/}"* ]]'
assert "built-in: shows model display_name"     '[[ "$OUT" == *"Opus 4.8"* ]]'
assert "built-in: shows 5h percentage (int)"    '[[ "$OUT" == *"5h 40%"* ]]'

# Pure-bash fraction strip floors a non-negative percent (e.g. 0.5 -> 0).
render "{\"rate_limits\":{\"five_hour\":{\"resets_at\":$future,\"used_percentage\":0.5}},\"model\":{\"id\":\"m\"},\"workspace\":{\"current_dir\":\"$tmpdir\"}}"
assert "built-in: sub-1 percent floors to 0"    '[[ "$OUT" == *"5h 0%"* ]]'
assert "built-in: shows reset wall-clock"       '[[ "$OUT" == *"resets $exp_hm"* ]]'
assert "built-in: non-git dir -> no (branch)"   '[[ "$OUT" != *"${tmpdir##*/} ("* ]]'

# A git working dir adds a (branch) segment.
render "{\"model\":{\"id\":\"m\"},\"workspace\":{\"current_dir\":\"$REPO_ROOT\"}}"
assert "built-in: git dir shows (branch)"        '[[ "$OUT" == *"("*")"* ]]'

# Free tier (no rate_limits): clean dir/model line, no 5h segment, no state file.
render "{\"model\":{\"display_name\":\"Sonnet\"},\"workspace\":{\"current_dir\":\"$tmpdir\"}}"
assert "built-in free-tier: shows model"        '[[ "$OUT" == *"Sonnet"* ]]'
assert "built-in free-tier: no 5h segment"      '[[ "$OUT" != *"5h"* ]]'
assert "built-in free-tier: no state written"   '[[ ! -f "$STATE" ]]'

echo "----"
echo "statusline-seam: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
