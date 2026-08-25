#!/usr/bin/env bash
# spawn-pane.sh — open a new iTerm2 split pane and launch a fresh `claude`
# session in it, ready to receive a relayed brief over cross-session messaging.
# macOS + iTerm2 only (uses osascript against iTerm's AppleScript API).
#
# The new session launches with `--settings '{"crossSessionInbound":"accept"}'`
# so the caller's relayed brief is DELIVERED, not held for approval — without it
# the whole point of the skill breaks (a bypass-vs-prompt class mismatch would
# leave the brief sitting in a hold dialog in the new pane). See the skill's
# SKILL.md and the cross-session-messaging docs.
#
# Usage:
#   spawn-pane.sh [--dry-run] [--perm-mode <mode>] <slug> [cwd]
#
#   <slug>        Short kebab-case label for the work (e.g. "run-tests"). A short
#                 random suffix is appended to form the session --name, so two
#                 handoffs never collide and get auto-renamed by Claude Code
#                 (a rename would break the caller's known address).
#   [cwd]         Working directory for the new session (default: $PWD — the
#                 same directory the caller is in).
#   --perm-mode   Passed through as `claude --permission-mode <mode>` (e.g.
#                 acceptEdits). Omitted by default: interactive, so the visible
#                 pane prompts for permissions like any hands-on session.
#   --dry-run     Print what would be launched (NAME=, CWD=, LAUNCH_CMD=) and
#                 exit without touching iTerm2 or polling. Used by tests and to
#                 preview the launch line.
#
# Prints KEY=VALUE lines on success. On real (non-dry-run) success it also polls
# until the new claude process is up (so the caller needs at most a couple of
# ListAgents checks, never a poll loop) and prints LAUNCHED=yes, or LAUNCHED=timeout
# with a non-zero exit if the process never appeared.
set -u

REGISTER_TIMEOUT="${HANDOFF_REGISTER_TIMEOUT:-20}"  # seconds to wait for the process
SETTINGS_JSON='{"crossSessionInbound":"accept"}'

dry_run="no"
perm_mode=""
slug=""
cwd=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   dry_run="yes"; shift ;;
    --perm-mode) [ $# -ge 2 ] || { echo "ERROR: --perm-mode requires a value." >&2; exit 4; }
                 perm_mode="$2"; shift 2 ;;
    --perm-mode=*) perm_mode="${1#*=}"; shift ;;
    -*)          echo "ERROR: unknown option '$1' (usage: spawn-pane.sh [--dry-run] [--perm-mode <mode>] <slug> [cwd])." >&2; exit 4 ;;
    *)           if [ -z "$slug" ]; then slug="$1"; elif [ -z "$cwd" ]; then cwd="$1";
                 else echo "ERROR: too many arguments." >&2; exit 4; fi
                 shift ;;
  esac
done

[ -n "$slug" ] || { echo "ERROR: a <slug> is required (usage: spawn-pane.sh [--dry-run] [--perm-mode <mode>] <slug> [cwd])." >&2; exit 4; }
# Slug must be safe to drop straight onto a shell command line as `--name <slug>`.
case "$slug" in
  *[!a-zA-Z0-9._-]*) echo "ERROR: slug '$slug' has unsafe characters — use letters, digits, dot, underscore, dash." >&2; exit 4 ;;
esac
[ -n "$cwd" ] || cwd="$PWD"
[ -d "$cwd" ] || { echo "ERROR: cwd '$cwd' is not a directory." >&2; exit 4 ;}

# Guard: this only works from iTerm2. Read $TERM_PROGRAM (Claude Code exports the
# host terminal into it) rather than probing the app, so the failure is a clear
# message instead of an AppleScript error. Tests set TERM_PROGRAM to exercise both.
if [ "${TERM_PROGRAM:-}" != "iTerm.app" ]; then
  echo "ERROR: handoff needs iTerm2 (TERM_PROGRAM='${TERM_PROGRAM:-unset}', expected 'iTerm.app'). This skill is macOS + iTerm2 only." >&2
  exit 2
fi

# Deterministic-but-unique name: slug + short hex suffix from $RANDOM. The caller
# reads NAME= back and addresses the new session by it.
suffix="$(printf '%03x' "$(( RANDOM % 4096 ))")"
name="${slug}-${suffix}"

# The pane must be split off the session that INVOKED handoff — not whatever
# session happens to be focused when osascript runs (that lands the pane in the
# wrong tab if the user has since switched away). iTerm2 exports the invoking
# session's UUID as $ITERM_SESSION_ID ("w0t0p0:<UUID>"); the part after the colon
# matches an AppleScript session's `id`. Empty (older iTerm2) falls back to the
# current session in the AppleScript below.
invoker_id="${ITERM_SESSION_ID##*:}"

# Build the launch command as ONE shell line to type into the new pane. cwd is
# %q-quoted so spaces survive; SETTINGS_JSON stays single-quoted so the pane's
# shell hands it to claude intact. This whole string is passed to AppleScript as
# an argv element (never interpolated into the AppleScript source), so `write text`
# sends it verbatim — the three quoting layers (bash -> AppleScript -> shell)
# never collide.
q_cwd="$(printf '%q' "$cwd")"
launch_cmd="cd ${q_cwd} && claude --name ${name} --settings '${SETTINGS_JSON}'"
[ -n "$perm_mode" ] && launch_cmd="${launch_cmd} --permission-mode ${perm_mode}"

echo "NAME=${name}"
echo "CWD=${cwd}"
echo "INVOKER_SESSION=${invoker_id}"
echo "LAUNCH_CMD=${launch_cmd}"

if [ "$dry_run" = "yes" ]; then
  echo "LAUNCHED=dry-run"
  exit 0
fi

# Split the INVOKING iTerm2 session vertically (the cmd+d equivalent) and type the
# launch line into the new pane. The AppleScript is a QUOTED heredoc — nothing
# from bash is interpolated into it; both the command and the invoker's session id
# arrive via `on run argv`. It finds the session whose id matches (so the pane
# lands in handoff's own tab, not the focused one); an empty id falls back to the
# current session.
if ! osascript - "$launch_cmd" "$invoker_id" <<'APPLESCRIPT'
on run argv
  set theCmd to item 1 of argv
  set wantId to item 2 of argv
  tell application "iTerm"
    if (count of windows) is 0 then error "no iTerm2 window is open" number 2
    if wantId is "" then
      set target to current session of current window
    else
      set target to missing value
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            if (id of s) is wantId then set target to s
          end repeat
        end repeat
      end repeat
      if target is missing value then error "handoff's own iTerm2 session (" & wantId & ") was not found" number 4
    end if
    tell target
      set newSession to (split vertically with same profile)
    end tell
    tell newSession
      write text theCmd
    end tell
  end tell
end run
APPLESCRIPT
then
  echo "ERROR: could not create the iTerm2 pane (is a window open, and has iTerm2 been granted Automation access? see README)." >&2
  echo "LAUNCHED=failed"
  exit 3
fi

# Wait for the worker process to come up so the caller can message it right away.
# Match the full `claude --name <name>` on the command line; the [c] bracket trick
# keeps this grep from matching itself in the ps listing.
waited=0
while [ "$waited" -lt "$REGISTER_TIMEOUT" ]; do
  if ps -Ao command= | grep -q "[c]laude --name ${name}"; then
    echo "LAUNCHED=yes"
    exit 0
  fi
  sleep 1
  waited=$(( waited + 1 ))
done

echo "WARNING: the new session's claude process didn't appear within ${REGISTER_TIMEOUT}s — the pane may still be starting. Check the pane, then confirm with ListAgents before messaging." >&2
echo "LAUNCHED=timeout"
exit 5
