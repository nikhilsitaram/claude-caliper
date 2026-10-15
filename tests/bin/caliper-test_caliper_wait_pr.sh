#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-wait-pr"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
BASE="$(cd "$TMPDIR_BASE" && pwd -P)"
FAKE="$BASE/fake"
export FAKE

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

check_match() {
  local desc="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # unquoted on purpose: $pattern is a glob
  if [[ "$actual" == $pattern ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (pattern=[$pattern] actual=[$actual])"; fail=$((fail + 1))
  fi
}

# Fake gh: `pr view` and `pr checks` each serve line N of their .seq file on
# their Nth call (the last line repeats once the sequence runs out). NONE is
# gh's zero-checks error, ERR a generic gh failure, and a "8 " prefix prints
# the rest but exits 8 (gh's pending code).
mkdir -p "$BASE/bin"
cat > "$BASE/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/argv"
case "$1 $2" in
  "pr view") kind=view ;;
  "pr checks") kind=checks ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
n=$(( $(cat "$FAKE/$kind.n" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE/$kind.n"
total=$(wc -l < "$FAKE/$kind.seq")
(( n <= total )) || n=$total
line="$(sed -n "${n}p" "$FAKE/$kind.seq")"
case "$line" in
  ERR) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
  NONE) echo "no checks reported on the 'feat' branch" >&2; exit 1 ;;
  "8 "*) printf '%s\n' "${line#8 }"; exit 8 ;;
  *) printf '%s\n' "$line" ;;
esac
EOF
# Fake sleep: record the requested interval, return at once.
cat > "$BASE/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/sleeps"
EOF
chmod +x "$BASE/bin/gh" "$BASE/bin/sleep"
export PATH="$BASE/bin:$PATH"

# Response builders.
pr() {  # <state> <mergeable> [<mergeStateStatus>]
  jq -cn --arg s "$1" --arg m "$2" --arg x "${3:-CLEAN}" '{state: $s, mergeable: $m, mergeStateStatus: $x}'
}
OPEN_OK="$(pr OPEN MERGEABLE)"
chk() {  # <name>:<bucket> ...
  local a
  for a in "$@"; do printf '%s\n' "$a"; done \
    | jq -Rcn '[inputs | split(":") | {name: .[0], bucket: .[1], state: "X"}]'
}

# scenario <view-line>... -- <checks-line>...
scenario() {
  rm -rf "$FAKE"; mkdir -p "$FAKE"; : > "$FAKE/view.seq"; : > "$FAKE/checks.seq"
  local f="$FAKE/view.seq"
  for a in "$@"; do
    if [[ "$a" == "--" ]]; then f="$FAKE/checks.seq"; continue; fi
    printf '%s\n' "$a" >> "$f"
  done
}

# Sets OUT (stdout), ERR (stderr), RC, POLLS (gh pr view calls), SLEEPS.
run() {
  RC=0
  OUT="$("$SCRIPT" "$@" 2>"$BASE/stderr")" || RC=$?
  ERR="$(cat "$BASE/stderr")"
  POLLS=0 SLEEPS=0
  [[ ! -f "$FAKE/argv" ]] || POLLS="$(grep -c '^pr view' "$FAKE/argv" || true)"
  [[ ! -f "$FAKE/sleeps" ]] || SLEEPS="$(wc -l < "$FAKE/sleeps" | tr -d ' ')"
}

# Every timing flag is passed explicitly so no test leans on a script default.
T=(--interval-s 30 --timeout-min 5 --grace-s 60)

echo "=== usage ==="
scenario "$OPEN_OK" -- "$(chk test:pass)"
run
check_eq "no PR argument -> 64" 64 "$RC"
run 7 --bogus
check_eq "unknown flag -> 64" 64 "$RC"
run 7 --timeout-min soon
check_eq "non-integer timeout -> 64" 64 "$RC"
run 7 --interval-s 0
check_eq "zero interval -> 64" 64 "$RC"
run 7 --require-check
check_eq "--require-check without a name -> 64" 64 "$RC"

echo "=== unreadable PR fails fast ==="
scenario ERR -- "$(chk test:pass)"
run 999 "${T[@]}"
check_eq "PR lookup failing on the first poll -> 64" 64 "$RC"
check_eq "  ...without waiting" 0 "$SLEEPS"

echo "=== green ==="
scenario "$OPEN_OK" -- "$(chk test:pass CodeRabbit:pass lint:skipping)"
run 7 "${T[@]}"
check_eq "all concluded, none failed -> 0" 0 "$RC"
check_match "  ...reason line says GREEN" "GREEN*" "$OUT"
check_eq "  ...on the first poll" 1 "$POLLS"
check_eq "  ...without sleeping" 0 "$SLEEPS"

echo "=== pending, then green ==="
scenario "$OPEN_OK" -- "$(chk test:pending review:pending)" "$(chk test:pass review:pass)"
run 7 "${T[@]}"
check_eq "pending then green -> 0" 0 "$RC"
check_eq "  ...after two polls" 2 "$POLLS"
check_eq "  ...sleeping the interval between them" 30 "$(cat "$FAKE/sleeps")"
check_match "  ...progress names the pending checks" "*poll 1/11*2 pending: test, review*" "$ERR"

echo "=== gh exits 8 (pending) with JSON on stdout ==="
scenario "$OPEN_OK" -- "8 $(chk test:pending)" "$(chk test:pass)"
run 7 "${T[@]}"
check_eq "exit-8 output is parsed, not treated as an error -> 0" 0 "$RC"
check_match "  ...poll 1 saw test pending" "*1 pending: test*" "$ERR"

echo "=== failed checks ==="
scenario "$OPEN_OK" -- "$(chk test:fail deploy:cancel lint:pass review:pending)" "$(chk test:fail deploy:cancel lint:pass review:pass)"
run 7 "${T[@]}"
check_eq "fail/cancel bucket -> 1" 1 "$RC"
check_eq "  ...only once nothing is pending (a bot check may still post)" 2 "$POLLS"
check_match "  ...names the failed checks" "FAILED*test*deploy*" "$OUT"
check_match "  ...progress shows the failure while waiting" "*1 pending: review*failed: test, deploy*" "$ERR"
scenario "$OPEN_OK" -- "$(chk test:fail review:pending)"
run 7 --interval-s 30 --timeout-min 1 --grace-s 60
check_eq "a failure with checks still pending at the timeout -> 1, not 3" 1 "$RC"
check_match "  ...reason names the failure and what is pending" "FAILED: test*review*" "$OUT"

echo "=== merge conflict ==="
scenario "$(pr OPEN CONFLICTING DIRTY)" -- NONE
run 7 "${T[@]}"
check_eq "CONFLICTING with no checks (workflows never start) -> 2" 2 "$RC"
check_eq "  ...on the first poll" 1 "$POLLS"
check_match "  ...reason line says CONFLICT" "CONFLICT*" "$OUT"
scenario "$(pr OPEN UNKNOWN DIRTY)" -- "$(chk test:pending)"
run 7 "${T[@]}"
check_eq "mergeStateStatus DIRTY alone -> 2" 2 "$RC"
scenario "$OPEN_OK" "$(pr OPEN CONFLICTING DIRTY)" -- "$(chk test:pending)"
run 7 "${T[@]}"
check_eq "conflict appearing mid-wait (base moved) -> 2" 2 "$RC"
check_eq "  ...on the poll that saw it" 2 "$POLLS"

echo "=== UNKNOWN mergeability is never clean ==="
scenario "$(pr OPEN UNKNOWN UNKNOWN)" "$OPEN_OK" -- "$(chk test:pass)"
run 7 "${T[@]}"
check_eq "green checks but UNKNOWN, then MERGEABLE -> 0" 0 "$RC"
check_eq "  ...only once mergeability resolved" 2 "$POLLS"
scenario "$(pr OPEN UNKNOWN UNKNOWN)" -- "$(chk test:pass)"
run 7 --interval-s 30 --timeout-min 1 --grace-s 60
check_eq "UNKNOWN for the whole wait -> 3" 3 "$RC"
check_match "  ...reason names the unknown mergeability" "TIMEOUT*UNKNOWN*" "$OUT"

echo "=== timeout ==="
scenario "$OPEN_OK" -- "$(chk test:pass slow:pending)"
run 7 --interval-s 30 --timeout-min 1 --grace-s 60
check_eq "still pending at the timeout -> 3" 3 "$RC"
check_eq "  ...polls at 0s, 30s, 60s" 3 "$POLLS"
check_eq "  ...sleeping between polls only" 2 "$SLEEPS"
check_match "  ...reason names what is still pending" "TIMEOUT*slow*" "$OUT"
scenario "$OPEN_OK" -- "$(chk slow:pending)"
run 7 --interval-s 30 --timeout-min 0 --grace-s 60
check_eq "--timeout-min 0 -> one poll, then 3" "3 1 0" "$RC $POLLS $SLEEPS"

echo "=== no checks registered ==="
scenario "$OPEN_OK" -- NONE
run 7 "${T[@]}"
check_eq "zero checks past the grace period on a mergeable PR -> 4" 4 "$RC"
check_eq "  ...at the first poll at or past --grace-s (0s, 30s, 60s)" 3 "$POLLS"
check_match "  ...reason line says NO_CHECKS" "NO_CHECKS*" "$OUT"
scenario "$(pr OPEN UNKNOWN UNKNOWN)" -- NONE
run 7 --interval-s 30 --timeout-min 2 --grace-s 30
check_eq "zero checks but mergeability UNKNOWN -> waits it out (3), not 4" 3 "$RC"
scenario "$OPEN_OK" -- NONE NONE "$(chk test:pass)"
run 7 "${T[@]}"
check_eq "checks registering inside the grace period -> 0" 0 "$RC"

echo "=== transient gh failures keep polling ==="
scenario "$OPEN_OK" -- ERR "$(chk test:pass)"
run 7 "${T[@]}"
check_eq "gh pr checks failing once mid-wait -> keeps polling -> 0" 0 "$RC"
check_match "  ...and says so" "*gh pr checks failed*" "$ERR"
scenario "$OPEN_OK" ERR "$OPEN_OK" -- "$(chk test:pending)" "$(chk test:pending)" "$(chk test:pass)"
run 7 "${T[@]}"
check_eq "gh pr view failing after the first poll -> keeps polling -> 0" 0 "$RC"

echo "=== merged / closed ==="
scenario "$(pr MERGED UNKNOWN UNKNOWN)" -- "$(chk test:pending)"
run 7 "${T[@]}"
check_eq "MERGED (which reports mergeable UNKNOWN) -> 5" 5 "$RC"
check_eq "  ...on the first poll" 1 "$POLLS"
check_match "  ...reason line says MERGED" "MERGED*" "$OUT"
scenario "$(pr CLOSED UNKNOWN UNKNOWN)" -- "$(chk test:pass)"
run 7 "${T[@]}"
check_eq "CLOSED -> 6" 6 "$RC"
check_match "  ...reason line says CLOSED" "CLOSED*" "$OUT"

echo "=== --merged waits past green for the merge ==="
scenario "$OPEN_OK" "$OPEN_OK" "$(pr MERGED UNKNOWN UNKNOWN)" -- "$(chk test:pass)"
run 7 --merged "${T[@]}"
check_eq "green but OPEN keeps waiting, then MERGED -> 5" 5 "$RC"
check_eq "  ...on the third poll" 3 "$POLLS"
check_match "  ...progress says the PR is still open" "*still OPEN*" "$ERR"
scenario "$(pr OPEN MERGEABLE BLOCKED)" -- "$(chk test:fail)"
run 7 --merged "${T[@]}"
check_eq "--merged with a failed check -> 1" 1 "$RC"
scenario "$(pr OPEN MERGEABLE BLOCKED)" -- "$(chk test:pass)"
run 7 --merged --interval-s 30 --timeout-min 1 --grace-s 60
check_eq "--merged, never merges -> 3" 3 "$RC"

echo "=== --require-check ==="
scenario "$OPEN_OK" -- "$(chk test:pass)" "$(chk test:pass CodeRabbit:pending)" "$(chk test:pass CodeRabbit:pass)"
run 7 --require-check CodeRabbit "${T[@]}"
check_eq "required check unregistered, then pending, then pass -> 0" 0 "$RC"
check_eq "  ...on the third poll" 3 "$POLLS"
check_match "  ...progress flags it as not registered" "*CodeRabbit (not registered)*" "$ERR"
scenario "$OPEN_OK" -- "$(chk test:pass)"
run 7 --require-check CodeRabbit --require-check "Claude Review" --interval-s 30 --timeout-min 1 --grace-s 60
check_eq "required checks that never register -> 3" 3 "$RC"
check_match "  ...reason names both" "TIMEOUT*CodeRabbit*Claude Review*" "$OUT"

echo "=== --min-wait-s ==="
scenario "$OPEN_OK" -- "$(chk test:pass)"
run 7 --min-wait-s 60 "${T[@]}"
check_eq "green at once but held until --min-wait-s -> 0" 0 "$RC"
check_eq "  ...at the first poll at or past it (0s, 30s, 60s)" 3 "$POLLS"
scenario "$OPEN_OK" -- "$(chk test:fail)"
run 7 --min-wait-s 60 "${T[@]}"
check_eq "a failure is held for --min-wait-s like green (bots still posting) -> 1" "1 3" "$RC $POLLS"
scenario "$OPEN_OK" -- NONE
run 7 --min-wait-s 90 "${T[@]}"
check_eq "no checks: holds for the later of --grace-s and --min-wait-s" "4 4" "$RC $POLLS"
scenario "$OPEN_OK" -- "$(chk test:pass)"
run 7 --min-wait-s 60 --interval-s 30 --timeout-min 0 --grace-s 60
check_eq "--min-wait-s past the timeout is clamped to the last poll -> 0" "0 1" "$RC $POLLS"
scenario "$OPEN_OK" -- "$(chk test:pass)"
run 7 --min-wait-s 300 --interval-s 45 --timeout-min 5 --grace-s 60
check_eq "  ...including a last poll short of the timeout (45s interval: 0..270s)" "0 7" "$RC $POLLS"

echo "=== the skills' exit tables match the script ==="
has() {  # <desc> <grep args...>
  local desc="$1"; shift
  if grep -q "$@"; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc"; fail=$((fail + 1))
  fi
}
# The script's finish calls are the source of truth for code -> tag.
PAIRS="$(grep -oE 'finish [0-9]+ "[A-Z_]+:' "$SCRIPT" | sed -E 's/finish ([0-9]+) "([A-Z_]+):/\1 \2/' | sort -u)"
check_eq "seven distinct exit codes, one tag each" "7 7" \
  "$(wc -l <<<"$PAIRS" | tr -d ' ') $(cut -d' ' -f1 <<<"$PAIRS" | sort -u | wc -l | tr -d ' ')"
while read -r code tag; do
  has "script header documents $code $tag" -E "^# +$code $tag( |\$)" "$SCRIPT"
  for skill in pr-review pr-merge; do
    has "$skill names exit $code \`$tag\`" -F "$code \`$tag\`" "$REPO_ROOT/skills/$skill/SKILL.md"
  done
done <<<"$PAIRS"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
