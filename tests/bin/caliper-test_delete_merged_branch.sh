#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/delete-merged-branch"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
BASE="$(cd "$TMPDIR_BASE" && pwd -P)"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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

g() { git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false "$@"; }

# Stub gh: log argv, then print $FAKE_GH_JSON (or fail when FAKE_GH_FAIL is set).
mkdir -p "$BASE/bin"
cat > "$BASE/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_ARGS_LOG"
[[ -z "${FAKE_GH_FAIL:-}" ]] || exit 1
printf '%s' "$FAKE_GH_JSON"
EOF
chmod +x "$BASE/bin/gh"
export PATH="$BASE/bin:$PATH" GH_ARGS_LOG="$BASE/gh-args"

gh_json() {  # <state> <headRefOid> <mergeCommit.oid>
  jq -cn --arg s "$1" --arg h "$2" --arg m "$3" \
    '{state: $s, headRefOid: $h, mergeCommit: (if $m == "" then null else {oid: $m} end)}'
}

REPO="$BASE/repo"
g init -q -b main "$REPO"
g -C "$REPO" commit -q --allow-empty -m base
BASE_OID="$(g -C "$REPO" rev-parse HEAD)"

# A commit on <parent> whose tree holds f=<content>; built with plumbing so no
# checkout moves. <msg> varies the oid for a same-tree commit.
commit_with() {  # <parent> <content> [<msg>]
  local blob tree
  blob="$(printf '%s\n' "$2" | g -C "$REPO" hash-object -w --stdin)"
  tree="$(printf '100644 blob %s\tf\n' "$blob" | g -C "$REPO" mktree)"
  g -C "$REPO" commit-tree "$tree" -p "$1" -m "${3:-$2}"
}

F1="$(commit_with "$BASE_OID" one)"
F2="$(commit_with "$F1" two)"
F3="$(commit_with "$F2" three)"                  # work added after the merge
SQUASH="$(commit_with "$BASE_OID" two squash)"   # tree == F2's, not a descendant
REBASED="$(commit_with "$BASE_OID" two rebased)" # tree == SQUASH's, different oid
MERGE="$(g -C "$REPO" commit-tree "$(g -C "$REPO" rev-parse "$F2^{tree}")" -p "$BASE_OID" -p "$F2" -m merge)"
MISSING=0123456789abcdef0123456789abcdef01234567

# Sets OUT and RC; runs from inside the repo, as pr-merge does.
run() {
  RC=0
  OUT="$(cd "$REPO" && "$SCRIPT" "$@" 2>&1)" || RC=$?
}

has_branch() { g -C "$REPO" rev-parse --verify --quiet "refs/heads/$1" >/dev/null && echo yes || echo no; }

# Test 1: local tip is exactly GitHub's merged head.
g -C "$REPO" branch b-head "$F2"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-head
check_eq "t1: exits 0" 0 "$RC"
check_eq "t1: reports the delete, then the leased remote delete naming one branch" \
  "DELETED b-head $F2"$'\n'"git push --force-with-lease=refs/heads/b-head:$F2 origin --delete refs/heads/b-head" "$OUT"
check_eq "t1: branch deleted" no "$(has_branch b-head)"

# Test 2: local tip moved off headRefOid but is an ancestor of a true merge commit.
g -C "$REPO" branch b-anc "$F1"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$MERGE")" run b-anc
check_eq "t2: exits 0" 0 "$RC"
check_eq "t2: branch deleted" no "$(has_branch b-anc)"

# Test 3: squash/rebase — local tip is tree-identical to the merge commit.
g -C "$REPO" branch b-squash "$REBASED"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-squash
check_eq "t3: exits 0" 0 "$RC"
check_eq "t3: branch deleted" no "$(has_branch b-squash)"

# Test 4: local tip has work GitHub never merged.
g -C "$REPO" branch b-div "$F3"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-div
check_eq "t4: exits 2" 2 "$RC"
check_match "t4: reports diverged" "SKIP b-div:*diverged*" "$OUT"
check_eq "t4: branch kept" yes "$(has_branch b-div)"

# Test 5: merge commit never fetched — the merge-commit legs can't vouch, so refuse.
g -C "$REPO" branch b-unfetched "$F1"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$MISSING")" run b-unfetched
check_eq "t5: exits 2" 2 "$RC"
check_eq "t5: branch kept" yes "$(has_branch b-unfetched)"

# Test 6: headRefOid missing but the merge commit vouches — delete, no lease oid.
g -C "$REPO" branch b-nohead "$REBASED"
FAKE_GH_JSON="$(gh_json MERGED "" "$SQUASH")" run b-nohead
check_eq "t6: exits 0" 0 "$RC"
check_eq "t6: DELETED line carries no oid and no push line follows" "DELETED b-nohead" "$OUT"
check_eq "t6: branch deleted" no "$(has_branch b-nohead)"

# Test 7: gh says MERGED but returned neither oid.
g -C "$REPO" branch b-nooids "$F2"
FAKE_GH_JSON="$(gh_json MERGED "" "")" run b-nooids
check_eq "t7: exits 2" 2 "$RC"
check_match "t7: reports the failed lookup" "SKIP b-nooids:*unavailable*" "$OUT"
check_eq "t7: branch kept" yes "$(has_branch b-nooids)"

# Test 8: PR not merged.
g -C "$REPO" branch b-open "$F2"
FAKE_GH_JSON="$(gh_json OPEN "$F2" "")" run b-open
check_eq "t8: exits 2" 2 "$RC"
check_match "t8: reports the gh state" "SKIP b-open:*OPEN*" "$OUT"
check_eq "t8: branch kept" yes "$(has_branch b-open)"

# Test 9: gh itself fails.
g -C "$REPO" branch b-ghfail "$F2"
FAKE_GH_FAIL=1 FAKE_GH_JSON="" run b-ghfail
check_eq "t9: exits 2" 2 "$RC"
check_match "t9: reports an unknown state" "SKIP b-ghfail:*unknown*" "$OUT"
check_eq "t9: branch kept" yes "$(has_branch b-ghfail)"

# Test 10: local branch already gone.
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-never-existed
check_eq "t10: exits 2" 2 "$RC"
check_match "t10: reports already deleted" "GONE b-never-existed:*" "$OUT"

# Test 11: branch still checked out in a worktree — update-ref -d would orphan it.
g -C "$REPO" branch b-co "$F2"
g -C "$REPO" worktree add -q "$BASE/wt-co" b-co
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-co
check_eq "t11: exits 2" 2 "$RC"
check_match "t11: names the worktree and the prune hint" "SKIP b-co:*$BASE/wt-co*git worktree prune*" "$OUT"
check_eq "t11: branch kept" yes "$(has_branch b-co)"

# Test 12: the compare-and-swap delete fails (ref locked) — report, keep the branch.
g -C "$REPO" branch b-lock "$F2"
touch "$REPO/.git/refs/heads/b-lock.lock"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-lock
rm -f "$REPO/.git/refs/heads/b-lock.lock"
check_eq "t12: exits 2" 2 "$RC"
check_match "t12: reports the failed delete" "SKIP b-lock:*local delete failed*" "$OUT"
check_eq "t12: branch kept" yes "$(has_branch b-lock)"

# Test 13: an explicit PR ref is what gh resolves, not the branch name.
g -C "$REPO" branch b-pr "$F2"
: > "$GH_ARGS_LOG"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-pr 42
check_eq "t13: exits 0" 0 "$RC"
check_match "t13: gh resolved the PR number" "pr view 42 *" "$(cat "$GH_ARGS_LOG")"

# Test 14: usage errors exit 1 without calling gh.
: > "$GH_ARGS_LOG"
run
check_eq "t14: no arguments exits 1" 1 "$RC"
run a b c
check_eq "t14: three arguments exits 1" 1 "$RC"
run 'bad..name'
check_eq "t14: invalid branch name exits 1" 1 "$RC"
check_eq "t14: gh never called" "" "$(cat "$GH_ARGS_LOG")"

# Test 15: the helper's printed remote delete, run verbatim as pr-merge says,
# against a local bare remote.
g init -q --bare "$BASE/remote.git"
g -C "$REPO" remote add origin "$BASE/remote.git"
remote_tip() { g -C "$REPO" ls-remote origin "refs/heads/$1" | cut -f1; }
printed_push() {  # <helper output> — runs its second line, the push, through a shell
  (cd "$REPO" && bash -c "$(sed -n 2p <<<"$1")" >/dev/null 2>&1)
}

g -C "$REPO" branch b-remote "$F2"
g -C "$REPO" push -q origin "$F2:refs/heads/b-remote"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-remote
RC_PUSH=0; printed_push "$OUT" || RC_PUSH=$?
check_eq "t15: remote at the merged head is deleted" "0 " "$RC_PUSH $(remote_tip b-remote)"

g -C "$REPO" branch b-advanced "$F2"
g -C "$REPO" push -q origin "$F3:refs/heads/b-advanced"   # another writer pushed after the merge
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-advanced
RC_PUSH=0; printed_push "$OUT" || RC_PUSH=$?
check_eq "t15: helper still deletes the local branch" 0 "$RC"
check_eq "t15: advanced remote survives the leased delete" "$F3" "$(remote_tip b-advanced)"
check_eq "t15: the push reports the refusal" 1 "$RC_PUSH"

# Test 16: local tip is exactly headRefOid and the merge commit was never
# fetched — only the headRefOid leg can vouch (t5 is its refusing mirror).
g -C "$REPO" branch b-headonly "$F2"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$MISSING")" run b-headonly
check_eq "t16: exits 0" 0 "$RC"
check_eq "t16: branch deleted" no "$(has_branch b-headonly)"

# Test 17: a commit added on top of the merged head that nets to the same tree
# (an empty commit here) never landed — the tree-identical leg must not vouch.
g -C "$REPO" branch b-ontop "$(commit_with "$F2" two after-merge)"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run b-ontop
check_eq "t17: exits 2" 2 "$RC"
check_match "t17: reports diverged" "SKIP b-ontop:*diverged*" "$OUT"
check_eq "t17: branch kept" yes "$(has_branch b-ontop)"

# Test 18: shell syntax in a valid ref name stays inert in the printed push.
# shellcheck disable=SC2016  # ${IFS} stays literal: it is part of the ref name
EVIL='b-evil;touch${IFS}pwned'
g -C "$REPO" branch "$EVIL" "$F2"
g -C "$REPO" push -q origin "$F2:refs/heads/$EVIL"
FAKE_GH_JSON="$(gh_json MERGED "$F2" "$SQUASH")" run "$EVIL"
RC_PUSH=0; printed_push "$OUT" || RC_PUSH=$?
check_eq "t18: remote deleted by the quoted push" "0 " "$RC_PUSH $(remote_tip "$EVIL")"
check_eq "t18: no injected command ran" no "$([[ -e "$REPO/pwned" ]] && echo yes || echo no)"

echo ""
echo "Passed: $pass, Failed: $fail"
[[ "$fail" -eq 0 ]]
