#!/usr/bin/env bash
# Tests for skills/usage-guard/scripts/check-usage.sh
# macOS/BSD only (uses `date -r <epoch>`); skips on GNU date (e.g. Linux CI).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$REPO_ROOT/skills/usage-guard/scripts/check-usage.sh"

if ! date -r 0 >/dev/null 2>&1; then
  echo "SKIP: check-usage.sh requires BSD date (-r epoch); not available here."
  exit 0
fi

pass=0; fail=0
STATE="$(mktemp)"; trap 'rm -f "$STATE"' EXIT
now="$(date +%s)"

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
field() { echo "$STDOUT" | sed -n "s/^$1=//p"; }
mkstate() { printf '%s' "$1" > "$STATE"; }

reset=$(( now + 3600 ))

# --- under threshold ---
mkstate "{\"resets_at\":$reset,\"used_percentage\":42.7,\"captured_at\":$now}"
run
assert "under threshold -> exit 0"      '[[ $RC -eq 0 ]]'
assert "under -> VERDICT=UNDER"         '[[ "$(field VERDICT)" == "UNDER" ]]'
assert "fresh capture -> STALE=no"      '[[ "$(field STALE)" == "no" ]]'

# --- at/over threshold (default 99) ---
mkstate "{\"resets_at\":$reset,\"used_percentage\":99.4,\"captured_at\":$now}"
run
assert "over threshold -> exit 10"      '[[ $RC -eq 10 ]]'
assert "over -> VERDICT=OVER"           '[[ "$(field VERDICT)" == "OVER" ]]'

# exactly at threshold counts as OVER
mkstate "{\"resets_at\":$reset,\"used_percentage\":99,\"captured_at\":$now}"
run
assert "exactly 99 -> exit 10 (at-or-over)" '[[ $RC -eq 10 ]]'

# --- custom threshold ---
mkstate "{\"resets_at\":$reset,\"used_percentage\":96,\"captured_at\":$now}"
run 95
assert "used 96 vs --at 95 -> exit 10"  '[[ $RC -eq 10 ]]'
run 99
assert "used 96 vs default 99 -> exit 0" '[[ $RC -eq 0 ]]'

# --- float display rounding (raw value still drives the compare) ---
mkstate "{\"resets_at\":$reset,\"used_percentage\":28.000000000000004,\"captured_at\":$now}"
run
assert "float noise displays as 28.0"   '[[ "$(field USED_PCT)" == "28.0" ]]'
assert "float value still UNDER (exit 0)" '[[ $RC -eq 0 ]]'

# --- staleness: missing captured_at reads as very stale, not fresh 0 (regression) ---
mkstate "{\"resets_at\":$reset,\"used_percentage\":50}"
run
assert "missing captured_at -> huge age" '[[ "$(field CAPTURED_AGE_SEC)" -gt 1000000 ]]'
assert "missing captured_at -> STALE=yes" '[[ "$(field STALE)" == "yes" ]]'

# --- no data ---
mkstate '{"resets_at":'"$reset"'}'
run
assert "missing used_percentage -> exit 2" '[[ $RC -eq 2 ]]'

# non-numeric used_percentage fails CLOSED (exit 2), never a false UNDER that
# would let the guard run past the limit.
mkstate "{\"resets_at\":$reset,\"used_percentage\":\"garbage\",\"captured_at\":$now}"
run
assert "non-numeric used_percentage -> exit 2"  '[[ $RC -eq 2 ]]'
mkstate "{\"resets_at\":$reset,\"used_percentage\":\"9.9.9\",\"captured_at\":$now}"
run
assert "multi-dot used_percentage -> exit 2"    '[[ $RC -eq 2 ]]'

rm -f "$STATE"
run
assert "no state file -> exit 1"        '[[ $RC -eq 1 ]]'

# --- --window selector reads the seven_day sub-object (#260) ---
mkstate "{\"resets_at\":$reset,\"used_percentage\":42.7,\"captured_at\":$now,\"seven_day\":{\"resets_at\":$reset,\"used_percentage\":88.0}}"
run
assert "default reads 5h used_pct (42.7)" '[[ "$(field USED_PCT)" == "42.7" ]]'
assert "default reports WINDOW=5h"        '[[ "$(field WINDOW)" == "5h" ]]'
run --window 7d
assert "--window 7d reads 7d used_pct (88.0)" '[[ "$(field USED_PCT)" == "88.0" ]]'
assert "--window 7d reports WINDOW=7d"    '[[ "$(field WINDOW)" == "7d" ]]'
# each window crosses its own threshold independently: 5h under, 7d over.
run 90
assert "5h 42.7 vs 90 -> UNDER (exit 0)"  '[[ $RC -eq 0 ]]'
run --window 7d 90
assert "7d 88.0 vs 90 -> UNDER (exit 0)"  '[[ $RC -eq 0 ]]'
run --window 7d 85
assert "7d 88.0 vs 85 -> OVER (exit 10)"  '[[ $RC -eq 10 ]]'

# 7d unavailable (sub-object absent, or its used_percentage null) -> exit 2.
mkstate "{\"resets_at\":$reset,\"used_percentage\":42.7,\"captured_at\":$now}"
run --window 7d
assert "--window 7d, no seven_day -> exit 2" '[[ $RC -eq 2 ]]'
mkstate "{\"resets_at\":$reset,\"used_percentage\":42.7,\"captured_at\":$now,\"seven_day\":{\"resets_at\":null,\"used_percentage\":null}}"
run --window 7d
assert "--window 7d, null 7d used_pct -> exit 2" '[[ $RC -eq 2 ]]'

# bad --window value -> exit 64 (usage error)
mkstate "{\"resets_at\":$reset,\"used_percentage\":42.7,\"captured_at\":$now}"
run --window weekly
assert "bad --window -> exit 64"          '[[ $RC -eq 64 ]]'

# trailing --window with no value must error (not hang on a failed `shift 2`)
run --window
assert "--window with no value -> exit 64" '[[ $RC -eq 64 ]]'

echo "----"
echo "check-usage: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
