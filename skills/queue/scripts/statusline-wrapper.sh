#!/usr/bin/env bash
# statusline-wrapper.sh — taps the 5-hour usage-window reset time into a state
# file on its way through to your real statusline renderer.
#
# Claude Code pipes a JSON blob to the statusLine command on stdin. For Pro/Max
# subscribers it includes `rate_limits.five_hour.{resets_at,used_percentage}` —
# the moment the current 5h usage window flips and how much is consumed. That
# data is NOT available to anything running inside a session, so we capture it
# here. Reads stdin once, persists to the state file, then forwards the SAME
# stdin to the real renderer (default: ccstatusline) and prints its output.
#
# Config (env):
#   QUEUE_STATE_FILE   where to write state (default ~/.claude/queue/state.json)
#   QUEUE_STATUSLINE   the real statusline command to forward to
#                      (default: bunx -y ccstatusline@latest)
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
mkdir -p "$(dirname "$STATE_FILE")"

input="$(cat)"

# Tap the 5h window fields; only persist when resets_at is present and a bare
# integer epoch. Guarding here matters: resets_at is interpolated raw into the
# JSON below, so a non-numeric value (e.g. an ISO-8601 string) would write a
# corrupt, unparseable state file — worse than no file, since both consumers
# would then jq-fail to empty and misreport the cause as "no resets_at".
resets_at="$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)"
case "$resets_at" in ''|*[!0-9]*) resets_at="" ;; esac
if [ -n "$resets_at" ]; then
  used="$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)"
  now="$(date +%s)"
  printf '{"resets_at":%s,"used_percentage":%s,"captured_at":%s}\n' \
    "$resets_at" "${used:-null}" "$now" > "$STATE_FILE"
fi

# Forward original stdin to the real statusline renderer (output unchanged).
printf '%s' "$input" | ${QUEUE_STATUSLINE:-bunx -y ccstatusline@latest}
