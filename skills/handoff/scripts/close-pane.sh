#!/usr/bin/env bash
# close-pane.sh — close an iTerm2 pane opened by spawn-pane.sh, by its session id.
# macOS + iTerm2 only (osascript against iTerm's AppleScript API).
#
# Usage:
#   close-pane.sh [--dry-run] <session-id>
#
#   <session-id>  The SESSION_ID= spawn-pane.sh printed for the pane.
#   --dry-run     Validate and print what would be closed, without touching iTerm2.
#
# Sends Ctrl-C three times ~0.3s apart, waits, then closes the session. Claude
# Code exits on a second press only within a short window (a 1s gap missed it:
# the second press counted as a new first one). An idle session exits on presses
# one and two; a mid-turn one is interrupted by the first and exits on the next
# two; a press left over lands harmlessly in the shell. The close itself sends
# SIGHUP, so a session that ignored the presses still exits seconds later.
#
# It matches by session id only, never by pane contents: a content match by pane
# name fails once the name scrolls out of the buffer, or after the pane's session
# is reset (gh #319). It finds the session first and closes after the
# loop, because closing inside iTerm's session iteration throws "Invalid index".
#
# Prints CLOSED=yes|not-found|failed|dry-run. Exit: 0 closed (or dry-run),
# 3 no session has that id (already closed), 2 osascript failed, 4 usage error.
set -u

CLOSE_DELAY="${HANDOFF_CLOSE_DELAY:-2}"  # seconds to let claude exit before closing
PRESS_GAP=0.3                            # seconds between Ctrl-Cs: inside the double-press window

usage() { echo "ERROR: $1 (usage: close-pane.sh [--dry-run] <session-id>)." >&2; exit 4; }

dry_run="no"
id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run="yes" ;;
    -*) usage "unknown option '$1'" ;;
    *) [ -z "$id" ] || usage "too many arguments"; id="$1" ;;
  esac
  shift
done
[ -n "$id" ] || usage "a <session-id> is required"
case "$id" in
  *[!A-Za-z0-9-]*) usage "session id '$id' has unsafe characters — expected an iTerm2 session UUID" ;;
esac
[[ "$CLOSE_DELAY" =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage "HANDOFF_CLOSE_DELAY='$CLOSE_DELAY' is not a number of seconds"

# Never close the session running this script: that would kill the caller.
if [ -n "${ITERM_SESSION_ID:-}" ] && [ "${ITERM_SESSION_ID##*:}" = "$id" ]; then
  echo "ERROR: refusing to close this script's own iTerm2 session ($id)." >&2
  exit 4
fi

echo "SESSION_ID=${id}"
if [ "$dry_run" = "yes" ]; then
  echo "CLOSED=dry-run"
  exit 0
fi

# A top-level QUOTED heredoc read into a variable, then fed on stdin with <<<
# (a heredoc inside $(...) breaks stock macOS bash 3.2). The id and delays
# arrive via argv, never spliced into the source.
#
# The session is found again by id before every action. A session taken from
# iTerm's loop is a positional reference (item k of tab j of window m), so if
# focus moves or another pane closes during the delays, it would retarget a
# different pane, possibly the coordinator's own.
IFS= read -r -d '' CLOSE_SCRIPT <<'APPLESCRIPT' || true
on findSession(wantId)
  tell application "iTerm"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if (id of s) is wantId then return s
        end repeat
      end repeat
    end repeat
  end tell
  return missing value
end findSession

on run argv
  set wantId to item 1 of argv
  set pause to (item 2 of argv) as number
  set gap to (item 3 of argv) as number
  if my findSession(wantId) is missing value then return "not-found"
  repeat 3 times
    set target to my findSession(wantId)
    if target is missing value then return "closed"
    tell application "iTerm" to tell target to write text (character id 3) newline no
    delay gap
  end repeat
  delay pause
  set target to my findSession(wantId)
  if target is missing value then return "closed"
  tell application "iTerm" to close target
  return "closed"
end run
APPLESCRIPT
if ! result="$(osascript - "$id" "$CLOSE_DELAY" "$PRESS_GAP" <<<"$CLOSE_SCRIPT")"; then
  echo "ERROR: osascript could not close session $id (has iTerm2 been granted Automation access? see README)." >&2
  echo "CLOSED=failed"
  exit 2
fi

case "$result" in
  closed) echo "CLOSED=yes"; exit 0 ;;
  not-found) echo "CLOSED=not-found"; exit 3 ;;
  *) echo "ERROR: unexpected osascript result '$result'." >&2; echo "CLOSED=failed"; exit 2 ;;
esac
