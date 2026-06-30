#!/usr/bin/env bash
# check-usage.sh [--window 5h|7d] [threshold]   (window default 5h, threshold 99)
# macOS/BSD only: uses `date -r <epoch>`.
#
# Reports the current Claude usage-window consumption by reading the queue
# skill's state file — refreshed (~every 10s) by statusline-wrapper.sh, which
# captures BOTH rolling windows: rate_limits.five_hour.* at the top level and
# rate_limits.seven_day.* under a `seven_day` sub-object. `--window 7d` guards
# the weekly cap; the default `5h` guards the 5-hour block.
#
# Exit codes let a caller branch without parsing floats:
#   0  = UNDER threshold (keep going)
#   10 = AT/OVER threshold (stop / queue)
#   1  = no state file (wrapper not wired in, or no render yet)
#   2  = no used_percentage for the chosen window (Pro/Max only, after first API
#        response — and each window may be independently absent)
#   64 = usage error (bad flag / unknown --window value)
#
# CAPTURED_AGE_SEC is the staleness signal: large ⇒ the statusline isn't
# rendering and USED_PCT lags reality. A missing captured_at reports as very
# stale (not falsely fresh). STALE=yes|no applies the same >90s cutoff as
# compute-fire.sh, so both consumers of captured_at agree on one threshold.
#
# Config (env): QUEUE_STATE_FILE (default ~/.claude/queue/state.json)
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
STALE_SEC=90            # statusline refreshes ~every 10s; >90s ⇒ likely not rendering

# Parse flags. --window selects the rolling window; the lone positional is the
# threshold (kept positional for backward compatibility with existing callers).
WINDOW="5h"
THRESH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --window)   [ $# -ge 2 ] || { echo "ERROR: --window requires a value (5h|7d)." >&2; exit 64; }
                WINDOW="$2"; shift 2 ;;
    --window=*) WINDOW="${1#*=}"; shift ;;
    --)         shift; break ;;
    -*)         echo "ERROR: unknown flag '$1' (usage: check-usage.sh [--window 5h|7d] [threshold])." >&2; exit 64 ;;
    *)          THRESH="$1"; shift ;;
  esac
done
THRESH="${THRESH:-99}"
case "$WINDOW" in
  5h|7d) ;;
  *) echo "ERROR: --window must be 5h or 7d, got '$WINDOW'." >&2; exit 64 ;;
esac

# Window selects where in the state file the fields live. five_hour is the
# top-level shape; seven_day is a sub-object (null fields when that window is
# absent — jq's `// empty` then collapses to the same "unavailable" path).
if [ "$WINDOW" = "7d" ]; then
  used_path='.seven_day.used_percentage'; resets_path='.seven_day.resets_at'
else
  used_path='.used_percentage'; resets_path='.resets_at'
fi

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: no $STATE_FILE — the queue statusline wrapper isn't capturing usage yet." >&2
  echo "Fix: settings.json statusLine must point to the queue statusline-wrapper.sh; let the terminal render once." >&2
  exit 1
fi

used="$(jq -r "$used_path // empty" "$STATE_FILE" 2>/dev/null)"
resets_at="$(jq -r "$resets_path // empty" "$STATE_FILE" 2>/dev/null)"
captured="$(jq -r '.captured_at // 0' "$STATE_FILE" 2>/dev/null)"
# Fail closed on a missing/non-numeric used_percentage: a non-number would make
# the awk compare below read 0 and report a false UNDER — exactly the verdict
# that would let the guard run past the limit. exit 2 (data unavailable) instead.
case "$used" in
  ''|*[!0-9.]*|*.*.*)
    echo "ERROR: missing or non-numeric used_percentage for the $WINDOW window in state file (Pro/Max only, after first API response; each window may be independently absent)." >&2
    exit 2 ;;
esac
# resets_at is only used for the human/RESETS_IN lines; a non-integer reads as
# absent so we skip those rather than emit garbage or hit a date error.
case "$resets_at" in *[!0-9]*) resets_at="" ;; esac
case "$captured" in ''|*[!0-9]*) captured=0 ;; esac

now="$(date +%s)"
age=$(( now - captured ))

# Display value rounded to 1 decimal (statusline can carry float noise like
# 28.000000000000004); keep raw $used for the threshold compare.
used_disp="$(awk -v u="$used" 'BEGIN{ printf "%.1f", u+0 }')"

echo "WINDOW=$WINDOW"
echo "USED_PCT=$used_disp"
echo "THRESHOLD=$THRESH"
echo "CAPTURED_AGE_SEC=$age"
if [ "$age" -gt "$STALE_SEC" ]; then echo "STALE=yes"; else echo "STALE=no"; fi
if [ -n "$resets_at" ]; then
  echo "RESETS_AT_HUMAN=$(date -r "$resets_at" '+%Y-%m-%d %H:%M %Z')"
  echo "RESETS_IN_MIN=$(( (resets_at - now) / 60 ))"
fi

# Float-safe comparison (used_percentage may be e.g. 92.7).
verdict="$(awk -v u="$used" -v t="$THRESH" 'BEGIN{ print (u+0 >= t+0) ? "OVER" : "UNDER" }')"
echo "VERDICT=$verdict"
[ "$verdict" = "OVER" ] && exit 10 || exit 0
