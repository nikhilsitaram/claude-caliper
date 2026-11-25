#!/usr/bin/env bash
set -euo pipefail

# Tests for bin/caliper-pr-at-bar (gh #319). A fake gh serves fixture JSON for
# the reads the script makes:
#   gh pr view                              state, head, checks, commits
#   gh api graphql                          review threads (one doc per page)
#   gh api .../compare/...                  behind_by
#   gh api .../commits/<base>/check-runs    base check runs (broken-CI valve)
#   gh api .../commits/<base>/status        base commit statuses (valve)
# Each scenario starts from an at-bar PR and breaks one criterion.

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
yes_no() { if "$@"; then echo yes; else echo no; fi; }

mkdir -p "$BASE/bin"
cat > "$BASE/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/argv"
[[ -z "${FAKE_GH_FAIL:-}" ]] || { echo "HTTP 502" >&2; exit 1; }
case "$*" in
  "pr view"*) cat "$FAKE/view.json" ;;
  "api graphql"*) cat "$FAKE/threads.json" ;;
  *compare*) cat "$FAKE/behind" ;;
  *check-runs*) cat "$FAKE/base_runs.json" ;;
  */status*) cat "$FAKE/base_status.json" ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$BASE/bin/gh"
export PATH="$BASE/bin:$PATH"

HEAD_SHA="1111111111111111111111111111111111111111"
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
view() {  # <state> <mergeable> <checks-json> <committedDate>
  jq -cn --arg s "$1" --arg m "$2" --argjson chk "$3" --arg d "$4" --arg h "$HEAD_SHA" '
    {state: $s, mergeable: $m, headRefOid: $h, baseRefName: "main",
     statusCheckRollup: $chk, commits: [{oid: $h, committedDate: $d}]}' > "$FAKE/view.json"
}
threads() {  # <resolved>:<comment-count> ...
  local a
  for a in "$@"; do printf '%s\n' "$a"; done | jq -Rcn '
    {data: {repository: {pullRequest: {reviewThreads: {nodes: [inputs | split(":") |
      {isResolved: (.[0] == "true"), comments: {totalCount: (.[1] | tonumber)}}]}}}}}' > "$FAKE/threads.json"
}
base_runs() {  # <name>:<conclusion> ... -> base branch check runs (REST shape)
  local a
  for a in "$@"; do printf '%s\n' "$a"; done | jq -Rcn '
    {check_runs: [inputs | split(":") | {name: .[0], status: "completed", conclusion: .[1]}]}' > "$FAKE/base_runs.json"
}
base_status() {  # <context>:<state> ...
  local a
  for a in "$@"; do printf '%s\n' "$a"; done | jq -Rcn '
    {statuses: [inputs | split(":") | {context: .[0], state: .[1]}]}' > "$FAKE/base_status.json"
}

GREEN="$(checks "test:COMPLETED:SUCCESS" "lint:COMPLETED:SKIPPED" "ctx:coderabbit:SUCCESS")"

reset() {  # at-bar baseline; base branch green
  rm -rf "$FAKE"; mkdir -p "$FAKE"
  view OPEN MERGEABLE "$GREEN" "$NOW_ISO"
  threads true:1 false:2
  echo 0 > "$FAKE/behind"
  base_runs; base_status
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
check_eq "script is executable" yes "$(yes_no test -x "$SCRIPT")"
check_eq "script has bash shebang" "#!/usr/bin/env bash" "$(head -1 "$SCRIPT")"

# --- at bar ---
reset; run 42
check_eq "at bar: exit 0" 0 "$RC"
check_eq "at bar: at_bar true" true "$(j .at_bar)"
check_eq "at bar: no failing criteria" 0 "$(j '.failing | length')"
check_eq "at bar: criteria are exactly state, checks, threads, mergeable, up_to_date" \
  "checks,mergeable,state,threads,up_to_date" "$(j '[keys[] | select(IN("pr","head","at_bar","failing","hint") | not)] | join(",")')"
check_eq "at bar: checks counted" "3/3" "$(j '"\(.checks.passed)/\(.checks.total)"')"
check_eq "at bar: threads answered" "2/2" "$(j '"\(.threads.answered)/\(.threads.total)"')"
check_eq "at bar: head reported" "$HEAD_SHA" "$(j .head)"
check_eq "at bar: pr number reported" 42 "$(j .pr)"
check_eq "at bar: graphql asks for PR 42" yes "$(yes_no grep -q 'api graphql.*n=42' "$FAKE/argv")"
check_eq "at bar: compare is base...head" yes "$(yes_no grep -q "compare/main...$HEAD_SHA" "$FAKE/argv")"
check_eq "green PR: base checks are not read" no "$(yes_no grep -q 'check-runs' "$FAKE/argv")"

# --- checks ---
reset; view OPEN MERGEABLE "$(checks "test:COMPLETED:FAILURE" "lint:COMPLETED:SUCCESS")" "$NOW_ISO"
run 42
check_eq "failed check: exit 1" 1 "$RC"
check_eq "failed check: checks failing" '["checks"]' "$(j '.failing | tojson')"
check_eq "failed check: name listed" "test" "$(j '.checks.failed_names | join(",")')"
check_eq "failed check: base checks are read on main" yes "$(yes_no grep -q 'commits/main/check-runs' "$FAKE/argv")"

reset; view OPEN MERGEABLE "$(checks "test:IN_PROGRESS:" "ctx:ci:PENDING")" "$NOW_ISO"
run 42
check_eq "pending checks: exit 1" 1 "$RC"
check_eq "pending checks: 2 pending" 2 "$(j .checks.pending)"

reset; view OPEN MERGEABLE "$(checks "test:COMPLETED:SUCCESS" "CodeRabbit:IN_PROGRESS:")" "$NOW_ISO"
run 42
check_eq "a bot still reviewing holds the bar" 1 "$RC"

reset; view OPEN MERGEABLE "$(checks "ctx:ci:ERROR")" "$NOW_ISO"
run 42
check_eq "errored status context counts as failed" 1 "$(j .checks.failed)"

reset; view OPEN MERGEABLE '[]' "$NOW_ISO"
run 42
check_eq "no checks: not at bar" 1 "$RC"
check_eq "no checks: fresh head gives no dropped-event hint" "" "$(j '.hint // ""')"

reset; view OPEN MERGEABLE '[]' "$OLD_ISO"
run 42
check_eq "no checks on an old head: dropped-event hint" yes "$(j '.hint // ""' | grep -qi 'empty commit' && echo yes || echo no)"

reset; view OPEN MERGEABLE '[]' "$NOW_ISO"
run 42 --allow-no-checks
check_eq "--allow-no-checks: zero checks is at bar" 0 "$RC"

reset; view OPEN MERGEABLE '[]' "$OLD_ISO"
run 42 --no-checks-min 999999999
check_eq "--no-checks-min: a large window suppresses the hint" "" "$(j '.hint // ""')"

# --- broken-CI safety valve ---
RED="$(checks "test:COMPLETED:FAILURE" "ctx:deploy:FAILURE" "lint:COMPLETED:SUCCESS")"

reset; view OPEN MERGEABLE "$RED" "$NOW_ISO"; base_runs "test:failure"; base_status "deploy:error"
run 42
check_eq "valve: failures base shares are waived -> at bar" 0 "$RC"
check_eq "valve: waived names listed" "deploy,test" "$(j '.checks.broken_names | sort | join(",")')"
check_eq "valve: waived checks aren't counted as failed" 0 "$(j .checks.failed)"
check_eq "valve: stderr names the waived checks" yes "$(yes_no grep -q 'broken CI waived.*test' <<<"$ERR")"

reset; view OPEN MERGEABLE "$RED" "$NOW_ISO"; base_runs "test:failure"
run 42
check_eq "valve: a failure base doesn't share still blocks" 1 "$RC"
check_eq "valve: only the shared one is waived" "test|deploy" "$(j '"\(.checks.broken_names | join(","))|\(.checks.failed_names | join(","))"')"

reset; view OPEN MERGEABLE "$RED" "$NOW_ISO"; base_runs "test:success" "deploy:success"
run 42
check_eq "valve: green base waives nothing" 2 "$(j .checks.failed)"

reset; view OPEN MERGEABLE "$(checks "pr-only:COMPLETED:FAILURE")" "$NOW_ISO"
run 42
check_eq "valve: a check with no base run (pull_request-only) still blocks" 1 "$RC"

reset; view OPEN MERGEABLE "$(checks "test:COMPLETED:CANCELLED")" "$NOW_ISO"; base_runs "test:cancelled"
run 42
check_eq "valve: base cancelled counts as base failing too" 0 "$RC"

reset; view OPEN MERGEABLE "$(checks "test:COMPLETED:FAILURE" "slow:IN_PROGRESS:")" "$NOW_ISO"; base_runs "test:failure"
run 42
check_eq "valve: a pending check still holds the bar" 1 "$RC"

# --- threads ---
reset; threads true:1 false:1 false:3
run 42
check_eq "unanswered thread: exit 1" 1 "$RC"
check_eq "unanswered thread: 2/3 answered" "2/3" "$(j '"\(.threads.answered)/\(.threads.total)"')"

reset; threads
run 42
check_eq "no threads: at bar" 0 "$RC"

# gh --paginate prints one document per page: an unanswered thread on page 2
# must still fail the bar.
reset; threads true:1; cp "$FAKE/threads.json" "$BASE/p1"; threads false:1
cat "$BASE/p1" "$FAKE/threads.json" > "$BASE/p12"; mv "$BASE/p12" "$FAKE/threads.json"
run 42
check_eq "paginated threads: an unanswered thread on page 2 fails the bar" "1/2" "$(j '"\(.threads.answered)/\(.threads.total)"')"
check_eq "graphql call paginates" yes "$(yes_no grep -q 'api graphql --paginate' "$FAKE/argv")"

# --- mergeable / state / behind ---
reset; view OPEN CONFLICTING "$GREEN" "$NOW_ISO"
run 42
check_eq "conflicting: exit 1" 1 "$RC"
check_eq "conflicting: mergeable failing" true "$(j '.failing | index("mergeable") != null')"

reset; view OPEN UNKNOWN "$GREEN" "$NOW_ISO"
run 42
check_eq "UNKNOWN mergeable is not at bar" 1 "$RC"

reset; echo 3 > "$FAKE/behind"
run 42
check_eq "behind base: exit 1" 1 "$RC"
check_eq "behind base: behind count" 3 "$(j .up_to_date.behind)"
check_eq "behind base: up_to_date failing" true "$(j '.failing | index("up_to_date") != null')"

reset; view MERGED UNKNOWN "$GREEN" "$NOW_ISO"
run 42
check_eq "merged PR: not at bar" 1 "$RC"
check_eq "merged PR: state failing" true "$(j '.failing | index("state") != null')"

# --- reason line + errors ---
reset; echo 3 > "$FAKE/behind"
run 42
check_eq "not at bar: stderr names the failing criterion" yes "$(yes_no grep -q 'up_to_date' <<<"$ERR")"

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
