#!/usr/bin/env bash
# stopfailure-resume.sh — StopFailure hook (matcher: rate_limit) backstop for
# /usage-guard --queue. macOS/BSD only (compute-fire.sh uses `date -r`).
#
# The proactive guard stops at a threshold (default 99%) and queues its own
# continuation. But the check is checkpoint-granular: one large action can blow
# past the limit before the next check, tripping a real rate limit mid-run. When
# that happens Claude Code fires a StopFailure hook with matcher `rate_limit`.
# This script is the defense-in-depth behind the proactive guard — it converts an
# unexpected hard rate-limit into the same queue-and-resume the guard would have
# done at the threshold.
#
# It is OPT-IN: wire it into your settings.json yourself (a plugin can't edit
# settings.json) — see ../README.md. It NO-OPS unless a `--queue` run is active
# (the guard-marker.sh marker is present), so it is safe to leave registered.
#
# The StopFailure payload carries the fact a limit was hit, NOT the reset time —
# so the resume is keyed off the LAST-KNOWN resets_at in the queue state file. A
# hook is a plain shell process: it cannot create a CronCreate job, so it records
# the intent to pending-resume.json and the SessionStart hook (pending-resume.sh)
# surfaces it on the next session, comparing fire_epoch to wall-clock. Unlike a
# cron one-shot, that surfacing has no scheduler jitter, so fire_epoch is simply
# the reset plus a small cushion — no cron dodge needed, and so no dependency on
# compute-fire.sh (this script stays correct when copied to a stable path).
#
# Config (env): QUEUE_STATE_FILE (default ~/.claude/queue/state.json)
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
STATE_DIR="$(dirname "$STATE_FILE")"
MARKER="$STATE_DIR/active-guard.json"
PENDING="$STATE_DIR/pending-resume.json"
LOG="$STATE_DIR/stopfailure.log"
CUSHION=60              # resume a minute past the reset, never before the API frees up

# Drain stdin (the hook payload); we don't need any of its fields.
cat >/dev/null 2>&1 || true

# Gate: do nothing unless a --queue guard run is active. StopFailure output is
# ignored by Claude Code, so exit code is cosmetic — exit 0 throughout.
[ -f "$MARKER" ] || exit 0

now="$(date +%s)"

# fire_epoch = last-known 5h reset + cushion. If the state file has no usable
# reset time, it stays null and the resume surfaces as "due now" rather than lost.
fire_epoch="null"
resets_at="$(jq -r '.resets_at // empty' "$STATE_FILE" 2>/dev/null)"
case "$resets_at" in ''|*[!0-9]*) : ;; *) fire_epoch=$(( resets_at + CUSHION )) ;; esac

# Carry the continuation payload from the marker into the pending-resume record.
payload="$(jq -c '.payload // ""' "$MARKER" 2>/dev/null)"
case "$payload" in ''|null) payload='""' ;; esac

tmp="$PENDING.tmp.$$"
if jq -n --argjson now "$now" --argjson fire "$fire_epoch" --argjson payload "$payload" \
    '{created_at:$now, reason:"stopfailure-rate_limit", fire_epoch:$fire, payload:$payload}' \
    > "$tmp" 2>/dev/null; then
  mv "$tmp" "$PENDING"
  printf '[%s] rate_limit StopFailure: queued resume (fire_epoch=%s)\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$fire_epoch" >> "$LOG" 2>/dev/null || true
else
  rm -f "$tmp"
fi
exit 0
