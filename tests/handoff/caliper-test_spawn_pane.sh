#!/usr/bin/env bash
# Tests for skills/handoff/scripts/spawn-pane.sh
# Uses --dry-run so no iTerm2 is touched; TERM_PROGRAM is set per case to
# exercise the guard. Portable (no BSD-date dependency) — runs on Linux CI too.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$REPO_ROOT/skills/handoff/scripts/spawn-pane.sh"

# Scrub the runner's own iTerm2 session id so cases that don't set it inline see an
# empty value (not whatever tab this test happens to run in). Inline
# `ITERM_SESSION_ID=… run …` still overrides per case.
unset ITERM_SESSION_ID

pass=0; fail=0

# Run HELPER; capture out/err/rc. First arg is the TERM_PROGRAM to simulate.
run() {
  local term="$1"; shift
  local tmp_out tmp_err
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  set +e
  env TERM_PROGRAM="$term" ITERM_SESSION_ID="${ITERM_SESSION_ID:-}" PATH="$PATH" HOME="$HOME" bash "$HELPER" "$@" \
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

# --- dry-run happy path ---
run "iTerm.app" --dry-run run-tests /tmp
assert "dry-run exits 0"                    '[[ $RC -eq 0 ]]'
assert "NAME is slug + suffix"              '[[ "$(field NAME)" =~ ^run-tests-[0-9a-f]{4}$ ]]'
assert "CWD echoes the passed dir"          '[[ "$(field CWD)" == "/tmp" ]]'
assert "LAUNCH_CMD cds to cwd"              '[[ "$(field LAUNCH_CMD)" == cd\ /tmp\ * ]]'
assert "LAUNCH_CMD names the session"       '[[ "$(field LAUNCH_CMD)" == *"claude --name run-tests-"* ]]'
# The accept setting is load-bearing: without it the relayed brief would be held.
assert "LAUNCH_CMD sets crossSessionInbound accept" \
  $'[[ "$(field LAUNCH_CMD)" == *"--settings \'{\\"crossSessionInbound\\":\\"accept\\"}\'"* ]]'
assert "dry-run reports LAUNCHED=dry-run"   '[[ "$(field LAUNCHED)" == "dry-run" ]]'
assert "no --permission-mode by default"    '[[ "$(field LAUNCH_CMD)" != *"--permission-mode"* ]]'

# --- invoker session id: split targets handoff's own pane, not the focused one ---
ITERM_SESSION_ID="w0t2p1:ABC-123-DEF" run "iTerm.app" --dry-run tabbed /tmp
assert "INVOKER_SESSION strips the wNtNpN prefix" '[[ "$(field INVOKER_SESSION)" == "ABC-123-DEF" ]]'

ITERM_SESSION_ID="BARE-UUID-NO-COLON" run "iTerm.app" --dry-run tabbed /tmp
assert "INVOKER_SESSION passes a colon-less id through" '[[ "$(field INVOKER_SESSION)" == "BARE-UUID-NO-COLON" ]]'

ITERM_SESSION_ID="" run "iTerm.app" --dry-run tabbed /tmp
assert "empty ITERM_SESSION_ID -> empty INVOKER_SESSION (AppleScript falls back)" '[[ -z "$(field INVOKER_SESSION)" ]]'

# --- default cwd is $PWD ---
run "iTerm.app" --dry-run just-a-slug
assert "cwd defaults to invocation dir"     '[[ -n "$(field CWD)" && -d "$(field CWD)" ]]'

# --- --perm-mode passthrough & validation ---
run "iTerm.app" --dry-run --perm-mode acceptEdits edits /tmp
assert "--perm-mode appends --permission-mode" '[[ "$(field LAUNCH_CMD)" == *"--permission-mode acceptEdits"* ]]'

run "iTerm.app" --dry-run --perm-mode=plan edits /tmp
assert "--perm-mode=X form also appends" '[[ "$(field LAUNCH_CMD)" == *"--permission-mode plan"* ]]'

run "iTerm.app" --dry-run --perm-mode
assert "--perm-mode with no value exits 4" '[[ $RC -eq 4 ]]'

run "iTerm.app" --dry-run --perm-mode 'acceptEdits; rm -rf ~' edits /tmp
assert "shell-metachar perm-mode rejected (exit 4)" '[[ $RC -eq 4 ]]'
assert "rejected perm-mode never reaches LAUNCH_CMD"  '[[ "$STDOUT" != *"rm -rf"* ]]'

# --- iTerm2 guard ---
run "Apple_Terminal" --dry-run run-tests /tmp
assert "non-iTerm exits 2"                  '[[ $RC -eq 2 ]]'
assert "non-iTerm explains the requirement" '[[ "$STDERR" == *"iTerm2"* ]]'

run "" --dry-run run-tests /tmp
assert "unset TERM_PROGRAM exits 2"         '[[ $RC -eq 2 ]]'

# --- argument validation ---
run "iTerm.app" --dry-run
assert "missing slug exits 4"               '[[ $RC -eq 4 ]]'

run "iTerm.app" --dry-run "bad slug"
assert "unsafe slug exits 4"                '[[ $RC -eq 4 ]]'

run "iTerm.app" --dry-run 'evil;rm'
assert "shell-metachar slug exits 4"        '[[ $RC -eq 4 ]]'

run "iTerm.app" --dry-run good-slug /no/such/dir
assert "nonexistent cwd exits 4"            '[[ $RC -eq 4 ]]'

run "iTerm.app" --dry-run --bogus good-slug /tmp
assert "unknown option exits 4"             '[[ $RC -eq 4 ]]'

run "iTerm.app" --dry-run one two three
assert "too many arguments exits 4"         '[[ $RC -eq 4 ]]'

# --- cwd with spaces survives quoting ---
sp="$(mktemp -d "${TMPDIR:-/tmp}/handoff test XXXXXX")"; trap 'rm -rf "$sp"' EXIT
run "iTerm.app" --dry-run spaced "$sp"
assert "spaced cwd exits 0"                 '[[ $RC -eq 0 ]]'
assert "spaced cwd is escaped in LAUNCH_CMD" '[[ "$(field LAUNCH_CMD)" == *"handoff\\ test"* ]]'

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
