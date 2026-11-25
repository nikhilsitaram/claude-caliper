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

# --- seam: every slug the ledger accepts is one spawn-pane.sh accepts ---
for slug in fix-a a.b_c-9 X1; do
  set +e
  "$REPO_ROOT/bin/caliper-coordinate" --ledger "$BASE/seam.json" add "$slug" >/dev/null 2>&1; added=$?
  TERM_PROGRAM=iTerm.app "$REPO_ROOT/skills/handoff/scripts/spawn-pane.sh" --dry-run "$slug" /tmp >/dev/null 2>&1; spawned=$?
  set -e
  check_eq "seam: slug '$slug' accepted by both ledger and spawn-pane" "0 0" "$added $spawned"
done

# --- errors ---
run frobnicate
check_eq "unknown subcommand: exit 64" 64 "$RC"
check_eq "ledger stays valid JSON throughout" yes "$(jq -e . "$L" >/dev/null && echo yes || echo no)"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
