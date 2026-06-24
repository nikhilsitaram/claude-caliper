#!/usr/bin/env bash
# check-usage.sh [threshold]   (threshold default 99)
# macOS/BSD only: uses `date -r <epoch>`.
#
# Reports the current Claude 5-hour usage-window consumption by reading the
# queue skill's state file — refreshed (~every 10s) by statusline-wrapper.sh
# with rate_limits.five_hour.{used_percentage,resets_at}.
#
# Exit codes let a caller branch without parsing floats:
#   0  = UNDER threshold (keep going)
#   10 = AT/OVER threshold (stop / queue)
#   1  = no state file (wrapper not wired in, or no render yet)
#   2  = no used_percentage (Pro/Max only, appears after first API response)
#
# CAPTURED_AGE_SEC is the staleness signal: large ⇒ the statusline isn't
# rendering and USED_PCT lags reality. A missing captured_at reports as very
# stale (not falsely fresh).
#
# Config (env): QUEUE_STATE_FILE (default ~/.claude/queue/state.json)
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
THRESH="${1:-99}"

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: no $STATE_FILE — the queue statusline wrapper isn't capturing usage yet." >&2
  echo "Fix: settings.json statusLine must point to the queue statusline-wrapper.sh; let the terminal render once." >&2
  exit 1
fi

used="$(jq -r '.used_percentage // empty' "$STATE_FILE" 2>/dev/null)"
resets_at="$(jq -r '.resets_at // empty' "$STATE_FILE" 2>/dev/null)"
captured="$(jq -r '.captured_at // 0' "$STATE_FILE" 2>/dev/null)"
if [ -z "$used" ]; then
  echo "ERROR: no used_percentage in state file (Pro/Max only, after first API response)." >&2
  exit 2
fi
case "$captured" in ''|*[!0-9]*) captured=0 ;; esac

now="$(date +%s)"
age=$(( now - captured ))

# Display value rounded to 1 decimal (statusline can carry float noise like
# 28.000000000000004); keep raw $used for the threshold compare.
used_disp="$(awk -v u="$used" 'BEGIN{ printf "%.1f", u+0 }')"

echo "USED_PCT=$used_disp"
echo "THRESHOLD=$THRESH"
echo "CAPTURED_AGE_SEC=$age"
if [ -n "$resets_at" ] && [ "$resets_at" != "null" ]; then
  echo "RESETS_AT_HUMAN=$(date -r "$resets_at" '+%Y-%m-%d %H:%M %Z')"
  echo "RESETS_IN_MIN=$(( (resets_at - now) / 60 ))"
fi

# Float-safe comparison (used_percentage may be e.g. 92.7).
verdict="$(awk -v u="$used" -v t="$THRESH" 'BEGIN{ print (u+0 >= t+0) ? "OVER" : "UNDER" }')"
echo "VERDICT=$verdict"
[ "$verdict" = "OVER" ] && exit 10 || exit 0
