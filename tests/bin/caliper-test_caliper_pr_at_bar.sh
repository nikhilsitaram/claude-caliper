#!/usr/bin/env bash
set -euo pipefail

# Tests for bin/caliper-pr-at-bar (gh #319). A fake gh serves fixture JSON for
# the three reads the script makes: `gh pr view` (state, head, checks, comments,
# commits), `gh api graphql` (review threads) and `gh api .../compare/...`
# (behind_by). Each scenario starts from an at-bar PR and breaks one criterion.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-pr-at-bar"

pass=0
fail=0
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
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

mkdir -p "$BASE/bin"
cat > "$BASE/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/argv"
[[ -z "${FAKE_GH_FAIL:-}" ]] || { echo "HTTP 502" >&2; exit 1; }
case "$1 $2" in
  "pr view") cat "$FAKE/view.json" ;;
  "api graphql") cat "$FAKE/threads.json" ;;
  "api "*compare*) cat "$FAKE/behind" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$BASE/bin/gh"
export PATH="$BASE/bin:$PATH"

HEAD_SHA="1111111111111111111111111111111111111111"
OLD_SHA="2222222222222222222222222222222222222222"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OLD_ISO="2000-01-01T00:00:00Z"

# Builders. checks: <name>:<status>:<conclusion> for CheckRuns, or
# ctx:<name>:<state> for commit StatusContexts.
checks() {
  local a
  for a in "$@"; do printf '%s\n' "$a"; done | jq -Rcn '[inputs | split(":") |
    if .[0] == "ctx" then {__typename: "StatusContext", context: .[1], state: .[2]}
    else {__typename: "CheckRun", name: .[0], status: .[1], conclusion: .[2]} end]'
}
verdict() {  # <sha> <blocking>
  printf 'Fixed 2, dismissed 1.\n\nReviewed-Head: %s · blocking: %s' "$1" "$2"
}
# view <state> <mergeable> <checks-json> <committedDate> <comment-body>...
# A body prefixed ext: comes from an outside commenter, member: from a repo
# member; any other body is the viewer's own comment.
view() {
  local state="$1" mergeable="$2" chk="$3" date="$4"; shift 4
  local c
  for c in "$@"; do printf '%s\0' "$c"; done \
    | jq -Rsc --arg s "$state" --arg m "$mergeable" --arg h "$HEAD_SHA" --argjson chk "$chk" --arg d "$date" '
      {state: $s, mergeable: $m, headRefOid: $h, baseRefName: "main",
       statusCheckRollup: $chk,
       commits: [{oid: $h, committedDate: $d}],
       comments: (split("\u0000") | map(select(. != "")) | map(
         if startswith("ext:") then {body: .[4:], author: {login: "drive-by"}, authorAssociation: "NONE", viewerDidAuthor: false}
         elif startswith("member:") then {body: .[7:], author: {login: "teammate"}, authorAssociation: "MEMBER", viewerDidAuthor: false}
         else {body: ., author: {login: "me"}, authorAssociation: "NONE", viewerDidAuthor: true} end))}' > "$FAKE/view.json"
}
threads() {  # <resolved>:<comment-count> ...
  local a
  for a in "$@"; do printf '%s\n' "$a"; done | jq -Rcn '
    {data: {repository: {pullRequest: {reviewThreads: {nodes: [inputs | split(":") |
      {isResolved: (.[0] == "true"), comments: {totalCount: (.[1] | tonumber)}}]}}}}}' > "$FAKE/threads.json"
}

GREEN="$(checks "test:COMPLETED:SUCCESS" "lint:COMPLETED:SKIPPED" "ctx:coderabbit:SUCCESS")"

reset() {  # at-bar baseline
  rm -rf "$FAKE"; mkdir -p "$FAKE"
  view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "unrelated" "$(verdict "$HEAD_SHA" 0)"
  threads true:1 false:2
  echo 0 > "$FAKE/behind"
}

run() {
  set +e
  OUT="$("$SCRIPT" "$@" 2>"$BASE/err")"
  RC=$?
  set -e
  ERR="$(cat "$BASE/err")"
}
j() { jq -r "$1" <<<"$OUT"; }

# --- layout ---
check_eq "script is executable" yes "$([[ -x "$SCRIPT" ]] && echo yes || echo no)"
check_eq "script has bash shebang" "#!/usr/bin/env bash" "$(head -1 "$SCRIPT")"

# --- at bar ---
reset; run 42
check_eq "at bar: exit 0" 0 "$RC"
check_eq "at bar: at_bar true" true "$(j .at_bar)"
check_eq "at bar: no failing criteria" 0 "$(j '.failing | length')"
check_eq "at bar: checks counted" "3/3" "$(j '"\(.checks.passed)/\(.checks.total)"')"
check_eq "at bar: verdict names head" true "$(j .verdict.names_head)"
check_eq "at bar: threads answered" "2/2" "$(j '"\(.threads.answered)/\(.threads.total)"')"
check_eq "at bar: head reported" "$HEAD_SHA" "$(j .head)"
check_eq "at bar: pr number reported" 42 "$(j .pr)"
check_eq "at bar: graphql asks for PR 42" yes "$(grep -q 'api graphql.*n=42' "$FAKE/argv" && echo yes || echo no)"
check_eq "at bar: compare is base...head" yes "$(grep -q "compare/main...$HEAD_SHA" "$FAKE/argv" && echo yes || echo no)"

# --- checks ---
reset; view OPEN MERGEABLE "$(checks "test:COMPLETED:FAILURE" "lint:COMPLETED:SUCCESS")" "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "failed check: exit 1" 1 "$RC"
check_eq "failed check: checks failing" '["checks"]' "$(j '.failing | tojson')"
check_eq "failed check: name listed" "test" "$(j '.checks.failed_names | join(",")')"

reset; view OPEN MERGEABLE "$(checks "test:IN_PROGRESS:" "ctx:ci:PENDING")" "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "pending checks: exit 1" 1 "$RC"
check_eq "pending checks: 2 pending" 2 "$(j .checks.pending)"

reset; view OPEN MERGEABLE "$(checks "ctx:ci:ERROR")" "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "errored status context counts as failed" 1 "$(j .checks.failed)"

reset; view OPEN MERGEABLE '[]' "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "no checks: not at bar" 1 "$RC"
check_eq "no checks: fresh head gives no dropped-event hint" "" "$(j '.hint // ""')"

reset; view OPEN MERGEABLE '[]' "$OLD_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "no checks on an old head: dropped-event hint" yes "$(j '.hint // ""' | grep -qi 'empty commit' && echo yes || echo no)"

reset; view OPEN MERGEABLE '[]' "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42 --allow-no-checks
check_eq "--allow-no-checks: zero checks is at bar" 0 "$RC"

reset; view OPEN MERGEABLE '[]' "$OLD_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42 --no-checks-min 999999999
check_eq "--no-checks-min: a large window suppresses the hint" "" "$(j '.hint // ""')"

# --- verdict ---
reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "$(verdict "$OLD_SHA" 0)"
run 42
check_eq "stale verdict: exit 1" 1 "$RC"
check_eq "stale verdict: names_head false" false "$(j .verdict.names_head)"
check_eq "stale verdict: verdict failing" true "$(j '.failing | index("verdict") != null')"

reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "$(verdict "$HEAD_SHA" 2)"
run 42
check_eq "blocking verdict: not at bar" 1 "$RC"
check_eq "blocking verdict: blocking parsed" 2 "$(j .verdict.blocking)"

reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)" "$(verdict "$OLD_SHA" 0)"
run 42
check_eq "newest verdict wins (older one named head)" false "$(j .verdict.names_head)"

reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "LGTM"
run 42
check_eq "no verdict: not at bar" 1 "$RC"
check_eq "no verdict: line null" null "$(j .verdict.line)"

reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "quoting: > Reviewed-Head: $HEAD_SHA · blocking: 0"
run 42
check_eq "verdict must start its line (a quote doesn't count)" 1 "$RC"

reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "$(verdict "$OLD_SHA" 0)" "ext:$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "outside commenter's verdict is ignored" false "$(j .verdict.names_head)"
check_eq "outside commenter can't put the PR at bar" 1 "$RC"

reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "member:$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "a repo member's verdict counts" 0 "$RC"

# --- seam: the verdict line pr-review documents is the one this script parses ---
# Read the template line from pr-review's SKILL.md (not a copy), fill in the
# head and a zero count, and require it to pass the verdict criterion.
TEMPLATE="$(grep -m1 '^Reviewed-Head: <sha>' "$REPO_ROOT/skills/pr-review/SKILL.md")"
check_eq "seam: pr-review documents a Reviewed-Head template line" yes "$([[ -n "$TEMPLATE" ]] && echo yes || echo no)"
FILLED="${TEMPLATE/<sha>/$HEAD_SHA}"; FILLED="${FILLED/<n>/0}"
reset; view OPEN MERGEABLE "$GREEN" "$NOW_ISO" "$(printf 'Summary.\n\n%s' "$FILLED")"
run 42
check_eq "seam: pr-review's documented verdict line satisfies the bar" true "$(j .verdict.ok)"

# --- threads ---
reset; threads true:1 false:1 false:3
run 42
check_eq "unanswered thread: exit 1" 1 "$RC"
check_eq "unanswered thread: 2/3 answered" "2/3" "$(j '"\(.threads.answered)/\(.threads.total)"')"

reset; threads
run 42
check_eq "no threads: at bar" 0 "$RC"

# --- mergeable / state / behind ---
reset; view OPEN CONFLICTING "$GREEN" "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "conflicting: exit 1" 1 "$RC"
check_eq "conflicting: mergeable failing" true "$(j '.failing | index("mergeable") != null')"

reset; view OPEN UNKNOWN "$GREEN" "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "UNKNOWN mergeable is not at bar" 1 "$RC"

reset; echo 3 > "$FAKE/behind"
run 42
check_eq "behind base: exit 1" 1 "$RC"
check_eq "behind base: behind count" 3 "$(j .up_to_date.behind)"
check_eq "behind base: up_to_date failing" true "$(j '.failing | index("up_to_date") != null')"

reset; view MERGED UNKNOWN "$GREEN" "$NOW_ISO" "$(verdict "$HEAD_SHA" 0)"
run 42
check_eq "merged PR: not at bar" 1 "$RC"
check_eq "merged PR: state failing" true "$(j '.failing | index("state") != null')"

# --- reason line + errors ---
reset; echo 3 > "$FAKE/behind"
run 42
check_eq "not at bar: stderr names the failing criterion" yes "$(grep -q 'up_to_date' <<<"$ERR" && echo yes || echo no)"

reset; FAKE_GH_FAIL=1 run 42
check_eq "gh failure: exit 64" 64 "$RC"
run
check_eq "missing pr: exit 64" 64 "$RC"
run abc
check_eq "non-numeric pr: exit 64" 64 "$RC"
run 42 --bogus
check_eq "unknown flag: exit 64" 64 "$RC"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
