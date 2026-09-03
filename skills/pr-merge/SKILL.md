---
name: pr-merge
description: Use when a reviewed PR is ready to merge, or when triggered by "/pr-merge", "merge the PR", "merge it".
---

# Merge PR

Merge (squash or rebase) and clean up branches and worktrees.

**Prerequisite:** A PR that has been reviewed (via `/pr-review` or manually).

## Workflow

### Step 1: Setup

Detect if CWD is inside a worktree:

```bash
[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]
```

If inside a worktree, note `IN_WORKTREE=true` and capture paths for cleanup:

```bash
MAIN_REPO="$(git worktree list --porcelain | head -1 | sed 's/^worktree //')"
WORKTREE_PATH="$(pwd)"
CWD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

Stay in the worktree — `gh pr merge` is a GitHub API call that works from any directory.

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master)
- `IS_INTEGRATION` — true when `$BRANCH_NAME` matches `integrate/*`; extract `FEATURE=${BRANCH_NAME#integrate/}`
- `IS_INTEGRATION_CWD` — true when `$CWD_BRANCH` matches `integrate/*` (CWD is an integration worktree, regardless of which PR is being merged)

### Step 2: Merge

If branch protection requires human approval and the PR lacks it, tell the user and stop with the PR URL.

**Pre-merge rebase check:** Verify the PR branch is up-to-date with the base branch:

```bash
git fetch origin
git merge-base --is-ancestor origin/$DEFAULT_BRANCH HEAD
```

Use bare `git fetch origin` (no branch arg) so `refs/remotes/origin/$DEFAULT_BRANCH` actually advances. `git fetch origin $DEFAULT_BRANCH` only updates `FETCH_HEAD` — the `is-ancestor` check then compares against a stale ref and reports up-to-date when the branch is actually behind.

If behind (non-zero exit): rebase onto default branch, resolve conflicts, run tests, push with `git push -u origin HEAD --force-with-lease`. Comment on PR with conflict resolution details. Complex conflicts → stop and ask user.

**Merge method** (`$METHOD` = `squash` or `rebase`):
- Integration branches (`IS_INTEGRATION=true`): `rebase` — auto-detected, no flag needed
- Phase PRs (base is `integrate/*`): `squash` — auto-detected, no flag needed
- Explicit `--rebase` flag overrides for any non-auto-detected branch
- Otherwise: `caliper-settings get merge_strategy` (`squash` or `rebase`)

Multi-phase plans produce one squash commit per phase on the integration branch; rebase preserves that per-phase history on main. Single-phase plans use squash (one phase = one commit).

**Enable auto-merge (preferred).** Hand the CI gate to GitHub instead of polling `gh pr checks` yourself. Check whether the repo allows it:

```bash
ALLOW_AUTO_MERGE=$(gh api "repos/{owner}/{repo}" --jq .allow_auto_merge 2>/dev/null)
```

If `true`, enable auto-merge:

```bash
gh pr merge $PR_NUMBER --auto --$METHOD
```

This is **non-blocking** — it returns once auto-merge is *enabled*, not once the PR merges. GitHub performs the merge whenever required checks pass (PR already mergeable → merges within seconds; checks pending → deferred until green). A non-zero exit means auto-merge couldn't attach (repo disallows it, or the PR is already in a clean immediately-mergeable state GitHub won't queue) — fall back to the direct merge below.

**Fallback — direct merge (legacy behavior).** When `allow_auto_merge` is `false` or `--auto` exits non-zero:

```bash
gh pr merge $PR_NUMBER --$METHOD
```

This errors if required checks are still pending — the caller is responsible for having waited. It returns with the PR already `MERGED`.

**Wait for the merge to land.** Unless `--no-wait` was passed, poll the PR's merge state until it flips — this replaces the old pre-merge `gh pr checks` poll:

```bash
gh pr view $PR_NUMBER --json state -q .state   # poll until MERGED
```

Poll on a modest interval, timing out at `caliper-settings get merge_wait_minutes` (default 10) — a dedicated setting, not `review_wait_minutes` (which orchestrate overloads to `0` to mean "merge directly"; a `0` here would defer cleanup on every auto-merge repo):
- `MERGED` → proceed to Step 3 cleanup. (Direct-merge fallback is already `MERGED`, so it returns immediately.)
- `CLOSED` without merge → stop and report; do not clean up.
- Still `OPEN` at timeout → auto-merge is enabled but CI is slow. Report the PR URL and that it will merge when checks pass, then **skip Step 3** — local cleanup needs the PR actually merged. A later `/pr-merge` sees the `MERGED` state and finishes cleanup (Step 3's per-branch gh-state gate makes re-runs safe).

`--no-wait` enables auto-merge and exits after reporting, skipping Step 3.

Never use `--delete-branch` — branch cleanup is handled in Step 3.

### Step 3: Clean Up

Capture the repo's auto-delete-on-merge setting once for use in branch deletion below:

```bash
AUTO_DELETE_REMOTE=$(gh api "repos/{owner}/{repo}" --jq .delete_branch_on_merge 2>/dev/null)
git fetch origin   # refresh remote-tracking refs so the containment guard below sees the just-merged commit (bare form — see Step 2 note)
```

**Local + remote branch deletion** uses a gh-verified pattern. `$B` is a placeholder for the call site's branch name (`$BRANCH_NAME`, `phase-a`, etc.); `$PR_REF` is whatever uniquely identifies the PR — prefer `$PR_NUMBER` (the just-merged PR from Step 1) when available, since branch-name resolution returns the most recent PR for that name and could match a stale historical PR for reused names like `phase-a`:

```bash
info=$(gh pr view "${PR_REF:-$B}" --json state,mergeCommit,headRefOid 2>/dev/null)
state=$(jq -r '.state // ""' <<<"$info")
if [ "$state" = "MERGED" ]; then
  head_oid=$(jq -r '.headRefOid // ""' <<<"$info")
  merge_oid=$(jq -r '.mergeCommit.oid // ""' <<<"$info")
  local_oid=$(git rev-parse --verify --quiet "refs/heads/$B")
  if [ -z "$local_oid" ]; then
    echo "Note: local $B already deleted"
  elif [ -z "$head_oid$merge_oid" ]; then
    echo "SKIP $B: gh MERGED but headRefOid/mergeCommit.oid unavailable (gh lookup failed) — delete refs/heads/$B manually if intended"
  elif [ "$local_oid" = "$head_oid" ] \
       || git merge-base --is-ancestor "$local_oid" "$merge_oid" 2>/dev/null \
       || git diff --quiet "$local_oid" "$merge_oid" 2>/dev/null; then
    if git update-ref -d "refs/heads/$B" "$local_oid"; then   # compare-and-swap: refuse if $B moved since the guard read it
      if [ "$AUTO_DELETE_REMOTE" != "true" ]; then
        git push origin --delete "$B" 2>/dev/null || echo "Note: remote $B already gone or protected"
      fi
    else
      echo "ERROR: local delete of $B failed (ref moved or locked) — leaving remote branch intact"
    fi
  else
    echo "SKIP $B: gh MERGED but local tip is neither what GitHub merged nor contained in the merge commit (diverged) — delete refs/heads/$B manually if intended"
  fi
else
  echo "Skipped $B (gh state: ${state:-unknown})"
fi
```

GitHub's MERGED state confirms the PR landed, but `update-ref -d` is as unconditional as `git branch -D` — it's used over `branch -d` only because `-d`'s merge check false-negatives on squash. The containment guard supplies the local check gh can't: it deletes only when the local tip is exactly what GitHub merged (`headRefOid`), or is an ancestor of the PR's merge commit (true merge), or is tree-identical to it (squash/rebase). The `headRefOid` leg needs no fetched object and is immune to base movement, so it stays correct on a deferred `/pr-merge` run even after other PRs land on the base or the merged branch was stale at squash time; the merge-commit legs cover a local tip that moved but is still contained. Every comparison is fail-closed — an absent local ref, an unavailable gh lookup, or a genuinely diverged tip all refuse the delete and report distinctly (already-deleted vs. lookup-failed vs. diverged), so local commits added after the merge are never destroyed silently. The local delete passes `$local_oid` as `update-ref`'s expected old value, so it refuses (and leaves the remote branch intact) if `$B` moved between the guard and the delete. The remote delete then fires only after the local delete succeeds, and only when auto-delete-on-merge is off (else GitHub already deleted it); `git push origin --delete` tolerates 404 (already-deleted) and 422 (branch protection) gracefully. Capture SKIP lines and errors in the Step 4 Summary so the user knows cleanup left branches behind.

**Worktree removal** uses bare `git worktree remove "$PATH"` (no `--force`) — the PR has merged so the worktree should be clean. **This stop-on-failure rule applies to every `git worktree remove` call in this section:** if removal exits non-zero, the worktree has uncommitted/untracked content the user may want to keep — stop the cleanup chain, report the path, and let the user decide, since force-removal can destroy uncommitted or untracked work that may still be needed. **Sibling phase worktrees** (some may already be cleaned by earlier pr-merge runs) need an existence guard; the inner remove still propagates failure to the caller (the `if` block exits with the inner `worktree remove` exit code, so the orchestrator above sees non-zero and stops):

```bash
if git worktree list --porcelain | grep -q "^branch refs/heads/phase-X$"; then
  git worktree remove .claude/worktrees/$FEATURE-phase-X
fi
```

**Integration branch** (`IS_INTEGRATION=true`):
1. If `IN_WORKTREE`: call `ExitWorktree` with `action: "remove"` and `discard_changes: true` — the PR is already merged so local commits are safe to discard
   - If ExitWorktree is a no-op (cross-session): `cd "$MAIN_REPO" && git worktree remove "$WORKTREE_PATH"`, then prefix all subsequent commands with `cd "$MAIN_REPO" &&`
2. Remove remaining phase worktrees (apply the sibling existence guard from above for each `phase-X`)
3. Delete phase branches (gh-verified): for each `phase-X` from plan.json, apply the pattern above
4. Delete `$BRANCH_NAME` (gh-verified)
5. `git worktree prune && git pull --rebase && git remote prune origin`

**Standard worktree** (`IN_WORKTREE=true`):
- If `IS_INTEGRATION_CWD=true`: the orchestrator is invoking pr-merge from the integration worktree for a phase PR — do NOT remove the integration worktree. Just delete `$BRANCH_NAME` (gh-verified) and prune remotes (`git remote prune origin`). The orchestrator handles the integration worktree in Phase Wrap-Up step 7d/7e.
- If `IS_INTEGRATION_CWD=false` (normal case, CWD branch matches PR branch):
  1. Call `ExitWorktree` with `action: "remove"` and `discard_changes: true` — the PR is already merged so local commits are safe to discard
     - If ExitWorktree is a no-op (cross-session): `cd "$MAIN_REPO" && git worktree remove "$WORKTREE_PATH"`, then prefix all subsequent commands with `cd "$MAIN_REPO" &&`
  2. Delete `$BRANCH_NAME` (gh-verified)
  3. `git worktree prune && git pull --rebase && git remote prune origin`

**No worktree:** `git checkout $DEFAULT_BRANCH && git pull --rebase && git remote prune origin`, then delete `$BRANCH_NAME` (gh-verified).

### Step 4: Summary

Report: PR number/URL, merge status, cleanup status.

## Arguments

| Arg | Effect |
|-----|--------|
| `<PR number>` | Target specific PR (`/pr-merge 42`) |
| *(none)* | Detect from current branch |
| `--rebase` | Use rebase merge instead of squash (for multi-phase final PRs) |
| `--no-wait` | Enable auto-merge and exit without waiting for the merge or cleaning up (cleanup runs on a later `/pr-merge` once GitHub reports `MERGED`) |

## Pitfalls

| Mistake | Why |
|---------|-----|
| Skipping `ExitWorktree` when it's available | `cd` doesn't persist across Bash tool calls — only `ExitWorktree` resets CWD at the session level. Always try `ExitWorktree` first; the `cd "$MAIN_REPO" &&` fallback is for cross-session worktrees where ExitWorktree returns a no-op. |
| Deleting branch before removing worktree | Git refuses. Remove worktree first. |
| Using `--delete-branch` on `gh pr merge` | Fails in worktree flows. Delete branch manually after. |
| Treating `gh pr merge --auto` as blocking | It returns once auto-merge is *enabled*, not merged. Poll `gh pr view --json state` for `MERGED` before cleanup. |

## Integration

**Preceded by:** pr-review (or manual review)

**Auto-invoked by:** orchestrate — in `pr-merge` workflow mode
