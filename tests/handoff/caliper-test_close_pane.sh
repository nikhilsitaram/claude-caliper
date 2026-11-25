#!/usr/bin/env bash
# Tests for skills/handoff/scripts/close-pane.sh (gh #319).
# A fake osascript stands in for iTerm2: it reports "closed" for a known id and
# "not-found" otherwise, and records its argv so the tests can check the id is
# passed as data (argv), never spliced into the AppleScript source.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$REPO_ROOT/skills/handoff/scripts/close-pane.sh"
unset ITERM_SESSION_ID

pass=0; fail=0
fk="$(mktemp -d)"; trap 'rm -rf "$fk"' EXIT
mkdir -p "$fk/bin"
cat > "$fk/bin/osascript" <<'EOF'
#!/usr/bin/env bash
src="$(cat)"
printf '%s\n' "$*" > "$FK/argv"
printf '%s' "$src" > "$FK/src"
[ -z "${FAKE_OSA_FAIL:-}" ] || { echo "execution error" >&2; exit 1; }
if [ "${2:-}" = "PANE-1" ]; then echo "closed"; else echo "not-found"; fi
EOF
chmod +x "$fk/bin/osascript"

run() {
  local tmp_out tmp_err
  tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
  set +e
  env FK="$fk" FAKE_OSA_FAIL="${FAKE_OSA_FAIL:-}" ITERM_SESSION_ID="${ITERM_SESSION_ID:-}" \
    HANDOFF_CLOSE_DELAY="${HANDOFF_CLOSE_DELAY:-0}" PATH="$fk/bin:$PATH" "$HELPER" "$@" >"$tmp_out" 2>"$tmp_err"
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

assert "close-pane.sh is executable" '[[ -x "$HELPER" ]]'
assert "close-pane.sh has a bash shebang" '[[ "$(head -1 "$HELPER")" == "#!/usr/bin/env bash" ]]'

run PANE-1
assert "known id closes, exit 0"        '[[ $RC -eq 0 ]]'
assert "known id reports CLOSED=yes"    '[[ "$(field CLOSED)" == "yes" ]]'
assert "id is passed to osascript as argv" '[[ "$(cat "$fk/argv")" == "- PANE-1 0 0.3" ]]'
assert "Ctrl-C is sent three times, inside the double-press window" 'grep -q "repeat 3 times" "$fk/src"'
assert "id is never spliced into the AppleScript source" '! grep -q PANE-1 "$fk/src"'
assert "AppleScript sends Ctrl-C (character id 3)" 'grep -q "character id 3" "$fk/src"'
assert "AppleScript matches by session id, not contents" '! grep -q "contents of" "$fk/src"'

run GONE-2
assert "unknown id exits 3"             '[[ $RC -eq 3 ]]'
assert "unknown id reports CLOSED=not-found" '[[ "$(field CLOSED)" == "not-found" ]]'

FAKE_OSA_FAIL=1 run PANE-1
assert "osascript failure exits 2"      '[[ $RC -eq 2 ]]'
assert "osascript failure reports CLOSED=failed" '[[ "$(field CLOSED)" == "failed" ]]'

ITERM_SESSION_ID="w0t0p1:PANE-1" run PANE-1
assert "refuses to close the invoking session (exit 4)" '[[ $RC -eq 4 ]]'
assert "refusal names the reason" '[[ "$STDERR" == *"own"* ]]'

run --dry-run PANE-1
assert "dry-run exits 0 and touches nothing" '[[ $RC -eq 0 && "$(field CLOSED)" == "dry-run" ]]'

run
assert "missing id exits 4"             '[[ $RC -eq 4 ]]'
run 'PANE-1"; quit'
assert "unsafe id rejected (exit 4)"    '[[ $RC -eq 4 ]]'
run a b
assert "too many arguments exits 4"     '[[ $RC -eq 4 ]]'
HANDOFF_CLOSE_DELAY="x" run PANE-1
assert "non-numeric close delay exits 4" '[[ $RC -eq 4 ]]'

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
