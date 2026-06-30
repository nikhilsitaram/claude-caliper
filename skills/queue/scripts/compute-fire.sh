#!/usr/bin/env bash
# compute-fire.sh — emit a one-shot cron spec (local time) for /queue.
# macOS/BSD only: uses `date -r <epoch>` and `date -j -f` (GNU date differs).
#
# Modes:
#   (default, no args)   Fire ~90s AFTER the current usage window resets. Reads
#                        the chosen window's resets_at + the shared captured_at
#                        from the state file (kept fresh by statusline-wrapper.sh).
#                        Rounds up to a whole minute and DODGES :00/:30 — the
#                        minutes where CronCreate applies up-to-90s-EARLY jitter to
#                        one-shots — so it can never fire before the window
#                        actually resets. Flags STALE if the statusline hasn't
#                        rendered recently.
#
#   --window 5h|7d       Which rolling window's reset to target in reset mode
#                        (default 5h). `7d` reads .seven_day.resets_at so reset
#                        mode can fire after the weekly reset. Ignored with
#                        --epoch (an explicit target is window-agnostic).
#
#   --epoch <N>          Fire at the explicit local epoch N (a clock time / "in
#                        2h" / "10am tomorrow" the caller already resolved).
#                        Floored to the minute and honored; a sub-minute-FUTURE
#                        target bumps to the next whole minute (cron is
#                        minute-granular).
#
# Config (env): QUEUE_STATE_FILE (default ~/.claude/queue/state.json)
# Prints KEY=VALUE lines on success; non-zero exit + stderr message on failure.
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
STALE_SEC=90            # statusline refreshes ~every 10s; >90s ⇒ likely not rendering
now="$(date +%s)"
mode="reset"
epoch=""
WINDOW="5h"

while [ $# -gt 0 ]; do
  case "$1" in
    --epoch)    [ $# -ge 2 ] || { echo "ERROR: --epoch requires a value." >&2; exit 4; }
                mode="epoch"; epoch="$2"; shift 2 ;;
    --epoch=*)  mode="epoch"; epoch="${1#*=}"; shift ;;
    --window)   [ $# -ge 2 ] || { echo "ERROR: --window requires a value (5h|7d)." >&2; exit 4; }
                WINDOW="$2"; shift 2 ;;
    --window=*) WINDOW="${1#*=}"; shift ;;
    *) echo "ERROR: unknown argument '$1' (usage: compute-fire.sh [--window 5h|7d] [--epoch <N>])." >&2; exit 4 ;;
  esac
done
if [ "$mode" = "epoch" ]; then
  case "$epoch" in
    ''|*[!0-9]*) echo "ERROR: --epoch needs an integer Unix timestamp, got '${epoch}'." >&2; exit 4 ;;
  esac
fi
case "$WINDOW" in
  5h|7d) ;;
  *) echo "ERROR: --window must be 5h or 7d, got '$WINDOW'." >&2; exit 4 ;;
esac

stale=""
age=0
if [ "$mode" = "reset" ]; then
  if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: no state file at $STATE_FILE — the statusline hasn't captured a reset time yet." >&2
    echo "Fix: keep this terminal focused ~10-15s so the statusline renders once, then retry." >&2
    exit 1
  fi
  # Must be a bare integer epoch: it feeds `fire=$(( resets_at + 90 ))` below, so
  # a non-numeric value (corrupt/hand-edited file) would otherwise reach
  # arithmetic. Guard at read; the empty/"null"/garbage cases all land here.
  # The window selects where the reset epoch lives: five_hour at the top level,
  # seven_day in the sub-object (null when that window is absent).
  if [ "$WINDOW" = "7d" ]; then
    resets_at="$(jq -r '.seven_day.resets_at // empty' "$STATE_FILE" 2>/dev/null)"
  else
    resets_at="$(jq -r '.resets_at // empty' "$STATE_FILE" 2>/dev/null)"
  fi
  case "$resets_at" in
    ''|*[!0-9]*)
      echo "ERROR: state file has no valid resets_at for the $WINDOW window (rate_limits is Pro/Max-only, and appears after the first API response; each window may be independently absent)." >&2
      exit 2 ;;
  esac
  # Staleness from captured_at; default 0 so a missing/non-numeric value reads as
  # very stale (not falsely fresh).
  captured="$(jq -r '.captured_at // 0' "$STATE_FILE" 2>/dev/null)"
  case "$captured" in ''|*[!0-9]*) captured=0 ;; esac
  age=$(( now - captured ))
  if [ "$age" -gt "$STALE_SEC" ]; then
    stale="yes"
    echo "WARNING: usage state is stale (${age}s old) — the statusline may not be rendering. Focus this terminal ~10-15s and re-run to refresh the reset time before relying on it." >&2
  else
    stale="no"
  fi
  # Fire 90s after reset, rounded UP to the next whole minute, dodging :00/:30.
  # Use the LOCAL minute (date +%M) for the dodge so it stays correct in
  # half-hour-offset timezones, where UTC minutes != local minutes.
  fire=$(( resets_at + 90 ))
  fire=$(( (fire + 59) / 60 * 60 ))
  m=$(( 10#$(date -r "$fire" +%M) ))
  if [ "$m" -eq 0 ] || [ "$m" -eq 30 ]; then
    fire=$(( fire + 60 ))
  fi
  basis_label="RESET_HUMAN"
  basis_human="$(date -r "$resets_at" '+%Y-%m-%d %H:%M:%S %Z')"
else
  # Explicit target: floor to the minute. A sub-minute FUTURE target (e.g. "in
  # 30s") floors into the current minute — bump it to the next whole minute so
  # cron has something to fire on. A genuinely past target falls to the guard.
  fire=$(( epoch / 60 * 60 ))
  if [ "$fire" -le "$now" ] && [ "$epoch" -gt "$now" ]; then
    fire=$(( (now / 60 + 1) * 60 ))
  fi
  basis_label="TARGET_HUMAN"
fi

if [ "$fire" -le "$now" ]; then
  if [ "$mode" = "epoch" ]; then
    echo "ERROR: target $(date -r "$epoch" '+%Y-%m-%d %H:%M:%S %Z') is in the past. Cron resolves to whole minutes — pick a time ≥1 minute out, and resolve bare clock times to the next future occurrence." >&2
  else
    echo "ERROR: the $WINDOW window already reset at $(date -r "$resets_at" '+%Y-%m-%d %H:%M:%S %Z'); nothing to wait for — run the commands now instead." >&2
  fi
  exit 3
fi

[ "$mode" = "epoch" ] && basis_human="$(date -r "$fire" '+%Y-%m-%d %H:%M %Z')"

# Cron fields in LOCAL time. 10# forces base-10 so "08"/"09" aren't read as octal
# and leading zeros are stripped (some cron parsers reject "09").
M=$((  10#$(date -r "$fire" +%M) ))
H=$((  10#$(date -r "$fire" +%H) ))
DOM=$(( 10#$(date -r "$fire" +%d) ))
MON=$(( 10#$(date -r "$fire" +%m) ))

# DST spring-forward guard: if the fire wall-clock doesn't round-trip back to the
# same epoch, it lands in a non-existent hour (e.g. 02:00-02:59 on the March
# transition) and cron would never match. Warn — don't fail.
wall="$(date -r "$fire" '+%Y-%m-%d %H:%M:00')"
rt="$(date -j -f '%Y-%m-%d %H:%M:%S' "$wall" +%s 2>/dev/null)"
if [ -n "$rt" ] && [ "$rt" != "$fire" ]; then
  echo "WARNING: fire wall-clock $wall doesn't round-trip — likely a DST spring-forward gap; cron may never match. Nudge the time outside the 02:00-02:59 local hour." >&2
fi

secs=$(( fire - now ))
echo "MODE=$mode"
echo "CRON=$M $H $DOM $MON *"
echo "FIRE_EPOCH=$fire"
echo "FIRE_HUMAN=$(date -r "$fire" '+%Y-%m-%d %H:%M %Z')"
echo "$basis_label=$basis_human"
echo "SECONDS_AWAY=$secs"
echo "MINUTES_AWAY=$(( secs / 60 ))"
if [ "$mode" = "reset" ]; then
  echo "WINDOW=$WINDOW"
  echo "CAPTURED_AGE_SEC=$age"
  echo "STALE=$stale"
fi
