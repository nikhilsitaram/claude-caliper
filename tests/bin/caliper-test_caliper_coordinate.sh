#!/usr/bin/env bash
set -euo pipefail

# Tests for bin/caliper-coordinate, the coordinate skill's ledger CLI (gh #319).
# --ledger points every call at a temp file; a fake gh answers `pr view` from
# $FAKE/pr-<n> (a PR state, e.g. MERGED) for `status` reconciliation and
# outside-PR (`pr:N`) dependencies.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-coordinate"

pass=0
fail=0
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
FAKE="$BASE/fake"
mkdir -p "$FAKE" "$BASE/bin"
export FAKE
L="$BASE/ledger/coordinate.json"

cat > "$BASE/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/argv"
[[ "$1 $2" == "pr view" ]] || { echo "fake gh: unexpected: $*" >&2; exit 99; }
[[ -f "$FAKE/pr-$3" ]] || { echo "no pull request $3" >&2; exit 1; }
jq -cn --arg s "$(cat "$FAKE/pr-$3")" '{state: $s}'
EOF
chmod +x "$BASE/bin/gh"
export PATH="$BASE/bin:$PATH"

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}
run() {
  set +e
  OUT="$("$SCRIPT" --ledger "$L" "$@" 2>/dev/null)"
  RC=$?
  set -e
}
item() { jq -r --arg s "$1" ".items[] | select(.slug == \$s) | $2" "$L"; }

check_eq "script is executable" yes "$([[ -x "$SCRIPT" ]] && echo yes || echo no)"
check_eq "script has bash shebang" "#!/usr/bin/env bash" "$(head -1 "$SCRIPT")"

# --- add ---
run add fix-a --issue 101
check_eq "add: exit 0" 0 "$RC"
check_eq "add: creates the ledger (and its dir)" yes "$([[ -f "$L" ]] && echo yes || echo no)"
check_eq "add: status defaults to queued" queued "$(item fix-a .status)"
check_eq "add: issue recorded as a number" 101 "$(item fix-a .issue)"
check_eq "add: not held" false "$(item fix-a .held)"

run add fix-a
check_eq "add: duplicate slug refused" 1 "$RC"
run add "bad slug"
check_eq "add: unsafe slug refused" 64 "$RC"

run add fix-b --after fix-a
run add fix-c --after fix-a,pr:900
run add fix-d --after nope
check_eq "add: unknown after slug refused" 1 "$RC"
check_eq "add: after list recorded" "fix-a,pr:900" "$(item fix-c '.after | join(",")')"

# --- ready ---
run ready
check_eq "ready: only items with no unmet deps" "fix-a" "$OUT"

run set fix-a --status running --pane-name fix-a-1a2b --session-id PANE-1
check_eq "set: exit 0" 0 "$RC"
check_eq "set: pane name" fix-a-1a2b "$(item fix-a .pane.name)"
check_eq "set: pane session id" PANE-1 "$(item fix-a .pane.session_id)"
run ready
check_eq "ready: running items are not ready" "" "$OUT"

run set fix-a --status merged --pr 55 --head abc123
check_eq "set: pr number" 55 "$(item fix-a .pr.number)"
check_eq "set: pr head" abc123 "$(item fix-a .pr.head)"
check_eq "set: merged stamps merged_at" yes "$([[ "$(item fix-a .merged_at)" != null ]] && echo yes || echo no)"
run ready
check_eq "ready: dep merged -> fix-b ready, fix-c still waits on pr:900" "fix-b" "$OUT"

echo MERGED > "$FAKE/pr-900"
run ready
check_eq "ready: outside PR merged -> both ready, in add order" "fix-b fix-c" "$(tr '\n' ' ' <<<"$OUT" | sed 's/ $//')"

run set fix-b --hold "touches publish path"
check_eq "set --hold: held" true "$(item fix-b .held)"
check_eq "set --hold: reason recorded" "touches publish path" "$(item fix-b '.hold_reasons | join(";")')"
run ready
check_eq "ready: held items are not ready" "fix-c" "$OUT"
run set fix-b --unhold
check_eq "set --unhold: cleared" "false 0" "$(item fix-b '"\(.held) \(.hold_reasons | length)"')"

# --- validation ---
run set fix-b --status bogus
check_eq "set: unknown status refused" 64 "$RC"
run set nope --status running
check_eq "set: unknown slug refused" 1 "$RC"
run set fix-b --pr abc
check_eq "set: non-numeric pr refused" 64 "$RC"
run set fix-b --after fix-b
check_eq "set: self-dependency refused" 1 "$RC"

# --- active ---
run set fix-b --status running
run set fix-c --status at-bar
run active
check_eq "active: counts running, at-bar and merged (pane still open)" 3 "$OUT"
run set fix-a --status "done"
run active
check_eq "active: done items don't count" 2 "$OUT"

# --- get / list ---
run get fix-c
check_eq "get: prints the item" at-bar "$(jq -r .status <<<"$OUT")"
run list --status running
check_eq "list --status filters" fix-b "$(jq -r '.[].slug' <<<"$OUT")"

# --- status: reconciles with live gh ---
run set fix-c --pr 77
echo MERGED > "$FAKE/pr-77"
run status
check_eq "status: exit 0" 0 "$RC"
check_eq "status: a PR merged outside the ledger moves the item to merged" merged "$(item fix-c .status)"
check_eq "status: names the reconciled merge so after-merge steps run" yes "$(grep -qx 'MERGED-ON-GITHUB fix-c' <<<"$OUT" && echo yes || echo no)"
check_eq "status: table lists the item" yes "$(grep -q 'fix-c' <<<"$OUT" && echo yes || echo no)"
check_eq "status: table shows the PR" yes "$(grep -q '#77' <<<"$OUT" && echo yes || echo no)"

echo CLOSED > "$FAKE/pr-55"
run status
check_eq "status: done items are left alone" "done" "$(item fix-a .status)"

# --- status: holds what would stall silently ---
run add fix-e --after fix-b
run set fix-b --status dropped
run set fix-c --status running
echo CLOSED > "$FAKE/pr-77"
run status
check_eq "status: PR closed unmerged -> held with reason" "true PR #77 closed without merging" \
  "$(item fix-c '"\(.held) \(.hold_reasons | join(";"))"')"
check_eq "status: queued item on a dropped dep -> held" "true depends on dropped item fix-b" \
  "$(item fix-e '"\(.held) \(.hold_reasons | join(";"))"')"
run status
check_eq "status: re-running doesn't duplicate hold reasons" 1 "$(item fix-c '.hold_reasons | length')"
check_eq "status: nothing newly merged -> no MERGED-ON-GITHUB line" no "$(grep -q 'MERGED-ON-GITHUB' <<<"$OUT" && echo yes || echo no)"

run add fix-f --after pr:901
echo CLOSED > "$FAKE/pr-901"
run status
check_eq "status: queued item on a closed outside PR -> held" "true depends on PR #901, closed without merging" \
  "$(item fix-f '"\(.held) \(.hold_reasons | join(";"))"')"

# --- soft dependencies (gh #329): met for starting, shown until merged ---
L="$BASE/soft/coordinate.json"
run add api
run add ui --soft-after api
check_eq "soft: add exit 0" 0 "$RC"
check_eq "soft: soft_after recorded" api "$(item ui '.soft_after | join(",")')"
check_eq "soft: add without it records an empty list" 0 "$(item api '.soft_after | length')"
run ready
check_eq "soft: an unmerged soft dep doesn't block ready" "api ui" "$(tr '\n' ' ' <<<"$OUT" | sed 's/ $//')"
run add both --after api --soft-after ui
run ready
check_eq "soft: a hard dep still gates ready beside a soft one" "api ui" "$(tr '\n' ' ' <<<"$OUT" | sed 's/ $//')"

run add bad --soft-after pr:950
check_eq "soft: pr:N has no soft form (usage error)" 64 "$RC"
run add bad --soft-after nope
check_eq "soft: unknown soft slug refused" 1 "$RC"
run add bad --soft-after bad
check_eq "soft: self soft-dependency refused" 1 "$RC"
run add bad --after api --soft-after api
check_eq "soft: same slug hard and soft refused" 1 "$RC"
check_eq "soft: refused add leaves no item" "" "$(item bad .slug)"
run set ui --after api
check_eq "soft: set can't make a soft dep also hard" 1 "$RC"
check_eq "soft: refused set leaves the item unchanged" 0 "$(item ui '.after | length')"

run set ui --status running
run status
check_eq "soft: WAITING ON shows an unmerged soft dep on a running item" yes \
  "$(grep -E '^running +ui ' <<<"$OUT" | grep -q 'api (soft)' && echo yes || echo no)"
check_eq "soft: WAITING ON lists a queued item's hard and soft deps" yes \
  "$(grep -E '^queued +both ' <<<"$OUT" | grep -q 'api,ui (soft)' && echo yes || echo no)"
run set api --status merged
run status
check_eq "soft: a merged soft dep leaves WAITING ON" yes \
  "$(grep -E '^running +ui ' <<<"$OUT" | grep -qv 'api' && echo yes || echo no)"

run set both --soft-after ""
check_eq "soft: set --soft-after '' clears the list" 0 "$(item both '.soft_after | length')"
run set both --soft-after ui
check_eq "soft: set --soft-after records the list" ui "$(item both '.soft_after | join(",")')"

run add late --soft-after ui
run set ui --status dropped
run ready
check_eq "soft: a dropped soft dep keeps the item out of ready even before status holds it" "" "$OUT"
run set both --status running
run status
check_eq "soft: queued item on a dropped soft dep -> held" "true depends on dropped item ui (soft)" \
  "$(item late '"\(.held) \(.hold_reasons | join(";"))"')"
check_eq "soft: running item on a dropped soft dep -> held" "true depends on dropped item ui (soft)" \
  "$(item both '"\(.held) \(.hold_reasons | join(";"))"')"
run status
check_eq "soft: re-running doesn't duplicate a running item's hold" 1 "$(item both '.hold_reasons | length')"
run set both --unhold
run status
check_eq "soft: --unhold alone is re-held while the dropped dep is listed" true "$(item both .held)"
run set both --soft-after ""
run set both --unhold
run status
check_eq "soft: editing the dep list out, then --unhold, sticks" false "$(item both .held)"

run add core
run add view --soft-after core
run set view --status at-bar
run status
check_eq "soft: WAITING ON shows an unmerged soft dep on an at-bar item" yes \
  "$(grep -E '^at-bar +view ' <<<"$OUT" | grep -q 'core (soft)' && echo yes || echo no)"
run set core --status dropped
run status
check_eq "soft: at-bar item on a dropped soft dep -> held" "true depends on dropped item core (soft)" \
  "$(item view '"\(.held) \(.hold_reasons | join(";"))"')"

# --- cycles: hard, soft or mixed, each end would wait on the other forever ---
L="$BASE/cycle/coordinate.json"
run add x
run add y --soft-after x
run set x --soft-after y
check_eq "cycle: soft-soft refused" 1 "$RC"
check_eq "cycle: refused set leaves the item unchanged" 0 "$(item x '.soft_after | length')"
run add z --after x
run set x --soft-after z
check_eq "cycle: mixed hard/soft refused" 1 "$RC"
run set x --after z
check_eq "cycle: hard-hard refused" 1 "$RC"
run add w --after z --soft-after y
check_eq "cycle: an acyclic diamond is accepted" 0 "$RC"
run set x --after pr:5
check_eq "cycle: pr:N deps aren't followed" 0 "$RC"
check_eq "add: the --after error keeps its pr:N hint" yes \
  "$(ERR="$("$SCRIPT" --ledger "$L" add q --after nope 2>&1)"; grep -q '(or pr:N)' <<<"$ERR" && echo yes || echo no)"

# A ledger written before soft deps existed has no soft_after field.
L="$BASE/legacy/coordinate.json"
mkdir -p "$(dirname "$L")"
jq -n '{version: 1, items: [
  {slug: "old", issue: null, status: "queued", held: false, hold_reasons: [], after: [],
   pane: {name: null, session_id: null}, pr: {number: null, head: null},
   created_at: "t", updated_at: "t", merged_at: null},
  {slug: "old2", issue: null, status: "running", held: false, hold_reasons: [], after: [],
   pane: {name: null, session_id: null}, pr: {number: null, head: null},
   created_at: "t", updated_at: "t", merged_at: null}]}' > "$L"
run ready
check_eq "legacy: ready works on items without soft_after" "0 old" "$RC $OUT"
run status
check_eq "legacy: status works on items without soft_after" 0 "$RC"
run set old --after old2
check_eq "legacy: set --after works on items without soft_after" 0 "$RC"

# --- seam: every slug the ledger accepts is one spawn-pane.sh accepts ---
for slug in fix-a a.b_c-9 X1; do
  set +e
  "$REPO_ROOT/bin/caliper-coordinate" --ledger "$BASE/seam.json" add "$slug" >/dev/null 2>&1; added=$?
  TERM_PROGRAM=iTerm.app "$REPO_ROOT/skills/handoff/scripts/spawn-pane.sh" --dry-run "$slug" /tmp >/dev/null 2>&1; spawned=$?
  set -e
  check_eq "seam: slug '$slug' accepted by both ledger and spawn-pane" "0 0" "$added $spawned"
done

# --- drift: every caliper-coordinate command and set flag the skill cites exists ---
SKILL_MD="$REPO_ROOT/skills/coordinate/SKILL.md"
for cmd in $(grep -o 'caliper-coordinate [a-z]*' "$SKILL_MD" | awk '{print $2}' | sort -u); do
  check_eq "drift: SKILL's 'caliper-coordinate $cmd' is a CLI command" yes \
    "$(grep -q "^  $cmd)" "$SCRIPT" && echo yes || echo no)"
done
for flag in $(grep -oE '(set|add) <slug> [^`]*' "$SKILL_MD" | grep -o -- '--[a-z-]*' | sort -u); do
  check_eq "drift: SKILL's 'set/add $flag' is a CLI flag" yes \
    "$(grep -q -- "^ *$flag)" "$SCRIPT" && echo yes || echo no)"
done
# SKILL tells the coordinator to find soft dependents by this key in `list`.
check_eq "drift: SKILL cites the soft_after key" yes "$(grep -q '`soft_after`' "$SKILL_MD" && echo yes || echo no)"
"$SCRIPT" --ledger "$BASE/seam.json" add drift-key >/dev/null 2>&1
check_eq "drift: list output carries the soft_after key SKILL cites" yes \
  "$("$SCRIPT" --ledger "$BASE/seam.json" list | jq -e 'all(.[]; has("soft_after"))' >/dev/null && echo yes || echo no)"

# --- errors ---
run frobnicate
check_eq "unknown subcommand: exit 64" 64 "$RC"
check_eq "ledger stays valid JSON throughout" yes "$(jq -e . "$L" >/dev/null && echo yes || echo no)"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
