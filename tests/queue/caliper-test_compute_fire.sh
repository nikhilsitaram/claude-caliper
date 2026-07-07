#!/usr/bin/env bash
# Tests for skills/queue/scripts/compute-fire.sh
# macOS/BSD only (uses `date -r <epoch>`); skips on GNU date (e.g. Linux CI).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$REPO_ROOT/skills/queue/scripts/compute-fire.sh"

# Skip gracefully where `date -r <epoch>` isn't BSD semantics.
if ! date -r 0 >/dev/null 2>&1; then
  echo "SKIP: compute-fire.sh requires BSD date (-r epoch); not available here."
  exit 0
fi

pass=0; fail=0
STATE="$(mktemp)"; trap 'rm -f "$STATE"' EXIT
now="$(date +%s)"

# Run HELPER with QUEUE_STATE_FILE pointed at our temp state; capture out/err/rc.
run() {
  local tmp_out tmp_err
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  set +e
  env QUEUE_STATE_FILE="$STATE" PATH="$PATH" HOME="$HOME" bash "$HELPER" "$@" \
    >"$tmp_out" 2>"$tmp_err"
  RC=$?
  set -e
  STDOUT="$(cat "$tmp_out")"; STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "PASS: $desc"; pass=$((pass+1))
  else echo "FAIL: $desc"; echo "  STDOUT: $STDOUT"; echo "  STDERR: $STDERR"; echo "  RC: $RC"; fail=$((fail+1)); fi
}
field() { echo "$STDOUT" | sed -n "s/^$1=//p"; }            # value of a KEY=
lmin()  { echo $(( 10#$(date -r "$1" +%M) )); }             # local minute of an epoch
mkstate() { printf '%s' "$1" > "$STATE"; }

# --- reset mode: basic ---
future=$(( (now/3600 + 2)*3600 + 17*60 ))                   # a future :17 local, hours out
mkstate "{\"resets_at\":$future,\"used_percentage\":40,\"captured_at\":$now}"
run
assert "reset mode exits 0"            '[[ $RC -eq 0 ]]'
assert "reset mode reports MODE=reset" '[[ "$(field MODE)" == "reset" ]]'
assert "reset mode emits a CRON"       '[[ -n "$(field CRON)" ]]'
assert "fresh capture -> STALE=no"     '[[ "$(field STALE)" == "no" ]]'

# --- reset mode: :30 dodge (reset+90 rounds onto a local :30) ---
base=$(( (now/60 + 5)*60 ))                                 # minute-aligned, future
while [ "$(lmin "$base")" -ne 30 ]; do base=$((base+60)); done
mkstate "{\"resets_at\":$(( base - 120 )),\"captured_at\":$now}"   # +90 = base-30s -> roundup = base (:30)
run
dodged_min="$(field CRON | cut -d' ' -f1)"
assert ":30 reset dodges to :31"   '[[ "$dodged_min" -eq 31 ]]'
assert "dodge never lands on :00/:30" '[[ "$dodged_min" -ne 0 && "$dodged_min" -ne 30 ]]'

# --- reset mode: stale capture ---
mkstate "{\"resets_at\":$future,\"used_percentage\":40,\"captured_at\":$(( now - 600 ))}"
run
assert "stale capture -> STALE=yes"      '[[ "$(field STALE)" == "yes" ]]'
assert "stale capture still exits 0"     '[[ $RC -eq 0 ]]'
assert "stale capture warns on stderr"   '[[ "$STDERR" == *"stale"* ]]'

# --- reset mode: missing / no data ---
mkstate '{"used_percentage":40,"captured_at":'"$now"'}'
run
assert "missing resets_at -> exit 2" '[[ $RC -eq 2 ]]'
# non-integer resets_at is rejected at read, before it can reach arithmetic
mkstate "{\"resets_at\":\"2026-06-24T21:00:00Z\",\"captured_at\":$now}"
run
assert "non-integer resets_at -> exit 2" '[[ $RC -eq 2 ]]'
rm -f "$STATE"
run
assert "no state file -> exit 1"     '[[ $RC -eq 1 ]]'

# --- reset mode: far-past resets_at is a stale cross-session blob, not a fresh
# reset (#265). Distinguished from a legitimately-just-reset window by the grace
# window: far past -> exit 2 (retry for fresh data); just past -> exit 3 (run now).
past=$(( now - 3*7*86400 ))                                 # ~3 weeks ago
mkstate "{\"resets_at\":$past,\"used_percentage\":100,\"captured_at\":$now}"
run
assert "far-past resets_at -> exit 2 (stale blob)" '[[ $RC -eq 2 ]]'
assert "far-past message mentions stale/cross-session" '[[ "$STDERR" == *"stale cross-session"* ]]'
# A window reset only seconds ago is within the grace band — a real just-reset
# window, not a stale blob. It must NOT be flagged as data-unavailable (exit 2);
# it either schedules a fire (exit 0) or, if reset+90 already elapsed, says run-now
# (exit 3) — both mean "the reading is trusted".
justpast=$(( now - 30 ))                                    # within PAST_GRACE_SEC
mkstate "{\"resets_at\":$justpast,\"used_percentage\":40,\"captured_at\":$now}"
run
assert "just-reset window is trusted (exit != 2)" '[[ $RC -ne 2 ]]'

# --- epoch mode ---
tgt=$(( (now/3600 + 3)*3600 + 12*60 ))                      # future :12 local
run --epoch "$tgt"
assert "epoch mode exits 0"               '[[ $RC -eq 0 ]]'
assert "epoch mode reports MODE=epoch"    '[[ "$(field MODE)" == "epoch" ]]'
assert "epoch minute honored"             "[[ \"\$(field CRON | cut -d' ' -f1)\" -eq $(lmin "$tgt") ]]"

# sub-minute future target bumps to the next whole minute (cron is minute-granular)
nowx="$(date +%s)"; run --epoch "$(( nowx + 20 ))"
assert "sub-minute target exits 0"        '[[ $RC -eq 0 ]]'
assert "sub-minute bumps to next minute"  "[[ \$(field FIRE_EPOCH) -ge \$(( (nowx/60 + 1)*60 )) ]]"

# genuinely-past target -> exit 3 with minute-granular message
run --epoch "$(( now - 300 ))"
assert "past epoch -> exit 3"             '[[ $RC -eq 3 ]]'
assert "past epoch message mentions minutes" '[[ "$STDERR" == *"whole minutes"* ]]'

# bad --epoch -> exit 4
run --epoch "abc"
assert "non-integer --epoch -> exit 4"    '[[ $RC -eq 4 ]]'

# --- reset mode: --window 7d selects the seven_day reset (#260) ---
future7=$(( (now/3600 + 4)*3600 + 23*60 ))                  # distinct, later than $future
mkstate "{\"resets_at\":$future,\"used_percentage\":40,\"captured_at\":$now,\"seven_day\":{\"resets_at\":$future7,\"used_percentage\":12}}"
run
assert "default targets 5h reset"          "[[ \$(field FIRE_EPOCH) -lt $future7 ]]"
assert "default reports WINDOW=5h"         '[[ "$(field WINDOW)" == "5h" ]]'
run --window 7d
assert "--window 7d exits 0"               '[[ $RC -eq 0 ]]'
assert "--window 7d reports WINDOW=7d"      '[[ "$(field WINDOW)" == "7d" ]]'
assert "--window 7d targets 7d reset"      "[[ \$(field FIRE_EPOCH) -ge $future7 ]]"

# 7d unavailable (sub-object absent, or its resets_at null) -> exit 2, like 5h.
mkstate "{\"resets_at\":$future,\"captured_at\":$now}"
run --window 7d
assert "--window 7d, no seven_day -> exit 2" '[[ $RC -eq 2 ]]'
mkstate "{\"resets_at\":$future,\"captured_at\":$now,\"seven_day\":{\"resets_at\":null,\"used_percentage\":null}}"
run --window 7d
assert "--window 7d, null 7d resets_at -> exit 2" '[[ $RC -eq 2 ]]'

# bad --window value -> exit 4
mkstate "{\"resets_at\":$future,\"captured_at\":$now}"
run --window 9z
assert "bad --window -> exit 4"            '[[ $RC -eq 4 ]]'

# trailing flag with no value must error (not hang on a failed `shift 2`)
run --window
assert "--window with no value -> exit 4"  '[[ $RC -eq 4 ]]'
run --epoch
assert "--epoch with no value -> exit 4"   '[[ $RC -eq 4 ]]'

echo "----"
echo "compute-fire: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
