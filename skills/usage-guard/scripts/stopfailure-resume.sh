#!/usr/bin/env bash
# stopfailure-resume.sh — StopFailure hook (matcher: rate_limit) breadcrumb for
# /usage-guard --queue.
#
# usage-guard's main job is to STOP cleanly at the threshold (default 99%). The
# check is checkpoint-granular, though, so one oversized action can trip a real
# rate limit before the next check — Claude Code then fires a StopFailure hook
# with matcher `rate_limit`. This hook is a light breadcrumb: it does NOT try to
# auto-resume (a hook is a plain shell process — it can't create a CronCreate job,
# and the payload carries no reset time anyway). It just records that an active
# `--queue` run was interrupted, so the next `/usage-guard` run can offer to pick
# the work back up instead of it being silently lost.
#
# It NO-OPS unless a `--queue` run is active (the guard-marker.sh marker is
# present), so it is safe to leave registered. OPT-IN: wire it into settings.json
# yourself (a plugin can't edit settings.json) — see ../README.md.
#
# Config (env): QUEUE_STATE_FILE (default ~/.claude/queue/state.json)
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
STATE_DIR="$(dirname "$STATE_FILE")"
MARKER="$STATE_DIR/active-guard.json"
PENDING="$STATE_DIR/pending-resume.json"
LOG="$STATE_DIR/stopfailure.log"

# Drain stdin (the hook payload); we don't need any of its fields.
cat >/dev/null 2>&1 || true

# Gate: do nothing unless a --queue guard run is active. StopFailure output is
# ignored by Claude Code, so the exit code is cosmetic — exit 0 throughout.
[ -f "$MARKER" ] || exit 0

now="$(date +%s)"
# The breadcrumb is the marker (original task + cwd) plus when the limit hit.
tmp="$PENDING.tmp.$$"
if jq --argjson now "$now" \
    '{reason:"stopfailure-rate_limit", interrupted_at:$now} + .' "$MARKER" \
    > "$tmp" 2>/dev/null; then
  mv "$tmp" "$PENDING"
  printf '[%s] rate_limit StopFailure: recorded interrupted --queue run\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$LOG" 2>/dev/null || true
else
  rm -f "$tmp"
fi
exit 0
