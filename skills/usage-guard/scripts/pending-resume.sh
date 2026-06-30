#!/usr/bin/env bash
# pending-resume.sh — SessionStart hook that surfaces a pending usage-guard
# resume left by the StopFailure backstop (stopfailure-resume.sh). macOS/BSD only.
#
# Emits a SessionStart `additionalContext` block when a resume is DUE (the 5h
# window has reset, or no reset time was known), instructing the model to resume
# `/usage-guard --queue` on the carried payload and then delete pending-resume.json.
# When a resume exists but is not yet due, it emits a short note instead. NO-OPS
# (no output) when there is nothing pending — safe to leave registered.
#
# OPT-IN: wire into settings.json yourself — see ../README.md.
#
# Config (env): QUEUE_STATE_FILE (default ~/.claude/queue/state.json)
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
STATE_DIR="$(dirname "$STATE_FILE")"
PENDING="$STATE_DIR/pending-resume.json"

cat >/dev/null 2>&1 || true   # drain the SessionStart payload

[ -f "$PENDING" ] || exit 0

now="$(date +%s)"
fire="$(jq -r '.fire_epoch // empty' "$PENDING" 2>/dev/null)"
payload="$(jq -r '.payload // ""' "$PENDING" 2>/dev/null)"
case "$fire" in *[!0-9]*) fire="" ;; esac   # null/garbage -> treat as due now

emit() {  # emit a SessionStart additionalContext block
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
}

if [ -n "$fire" ] && [ "$now" -lt "$fire" ]; then
  when="$(date -r "$fire" '+%Y-%m-%d %H:%M %Z' 2>/dev/null)"
  emit "A /usage-guard --queue run was interrupted by a rate limit; its remaining work is pending resume at ${when:-the next window reset}. Not due yet — do not resume now. (Record: $PENDING)"
  exit 0
fi

emit "A /usage-guard --queue run was interrupted by a rate limit and its window has now reset. Resume the remaining work: invoke /usage-guard --queue on the payload below, then delete the record file $PENDING so it is not resumed twice.

--- pending resume payload ---
$payload"
exit 0
