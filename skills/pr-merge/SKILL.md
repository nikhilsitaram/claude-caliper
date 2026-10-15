---
name: pr-merge
description: Use when a reviewed PR is ready to merge, or when triggered by "/pr-merge", "merge the PR", "merge it".
---

# Merge PR

Merge (squash or rebase) and clean up branches and worktrees.

**Prerequisite:** A PR that has been reviewed (via `/pr-review` or manually).

## Workflow

### Step 1: Setup

Detect if CWD is inside a worktree — it is when the two printed lines differ (the isolation guard refuses `$(git …)` in a test):

```bash
git rev-parse --path-format=absolute --git-dir --git-common-dir
```

If inside a worktree, note `IN_WORKTREE=true` and capture paths for cleanup:

```bash
MAIN_REPO=$(caliper-main-root)
WORKTREE_PATH=$(pwd)
CWD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

Stay in the worktree — `gh pr merge` is a GitHub API call that works from any directory.

Identify the PR from argument, current branch (`gh pr view`), or `gh pr list --author @me --state open`. If multiple candidates and you're not on a branch with an associated PR, ask the user to pick. Store PR number, branch name, and URL.

Detect environment:
- `DEFAULT_BRANCH` from `refs/remotes/origin/HEAD` (fallback: main/master)
- `IS_INTEGRATION` — true when `$BRANCH_NAME` matches `integrate/*`
- `IS_INTEGRATION_CWD` — true when `$CWD_BRANCH` matches `integrate/*` (CWD is an integration worktree, regardless of which PR is being merged)

### Step 2: Merge

If branch protection requires human approval and the PR lacks it, tell the user and stop with the PR URL.

**Pre-merge rebase check:** Verify the PR branch is up-to-date with the base branch:

```bash
git fetch origin
git merge-base --is-ancestor origin/<DEFAULT_BRANCH> HEAD
```

Use bare `git fetch origin` (no branch arg) so `refs/remotes/origin/<DEFAULT_BRANCH>` actually advances. `git fetch origin <DEFAULT_BRANCH>` only updates `FETCH_HEAD` — the `is-ancestor` check then compares against a stale ref and reports up-to-date when the branch is actually behind.

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

**Fallback — direct merge.** When `allow_auto_merge` is `false` or `--auto` exits non-zero, gate on the checks first (`gh pr merge` errors while required checks pend): `caliper-wait-pr $PR_NUMBER --timeout-min <merge_wait_minutes>` — `--timeout-min 0` (one poll) under `--no-wait`. On exit 0 `GREEN` or 4 `NO_CHECKS`, `gh pr merge $PR_NUMBER --$METHOD` (returns with the PR `MERGED`); on 2, 5 or 6, the matching row below; otherwise report the reason line and stop.

**Wait for the merge to land.** Unless `--no-wait` was passed — a hand-rolled state poll waits out the timeout on a conflict or failed check that blocks auto-merge:

```bash
caliper-wait-pr $PR_NUMBER --merged --timeout-min <merge_wait_minutes>
```

Minutes from `caliper-settings get merge_wait_minutes` (default 10) — not `review_wait_minutes`, which orchestrate overloads to `0` ("merge directly"). Give either wait's Bash call a `timeout` a minute past the wait — over 9 min, use `run_in_background: true` instead (the tool caps at 10).

| Exit | Then |
|---|---|
| 5 `MERGED` | Step 3 (direct merge returns this at once) |
| 6 `CLOSED` | Stop and report; no cleanup |
| 2 `CONFLICT` | Base moved: redo the pre-merge rebase, push, rerun Step 2 |
| 1 `FAILED` | Report the failed checks and PR URL; **skip Step 3** (a non-required failure may still auto-merge) |
| 3 `TIMEOUT` · 4 `NO_CHECKS` | Auto-merge hasn't fired. Report the reason line (what's pending, or that no check registered — a required review or untriggered required check is blocking) and the PR URL; **skip Step 3** |

Skipping Step 3 is safe: a later `/pr-merge` sees `MERGED` and finishes cleanup (Step 3's per-branch gh-state gate makes re-runs safe).

`--no-wait` enables auto-merge and exits after reporting, skipping Step 3.

Never use `--delete-branch` — branch cleanup is handled in Step 3.

### Step 3: Clean Up

Read the repo's auto-delete-on-merge setting (`AUTO_DELETE_REMOTE`, used below) and refresh remote-tracking refs so the containment guard sees the just-merged commit (bare `git fetch` — see Step 2 note):

```bash
gh api "repos/{owner}/{repo}" --jq .delete_branch_on_merge
git fetch origin
```

**Branch deletion** is gh-verified, local first. `<B>` is the call site's branch (`$BRANCH_NAME`, `phase-a`, …); `<PR>` is the PR to verify against — pass `$PR_NUMBER` (the just-merged PR from Step 1) when `<B>` is `$BRANCH_NAME`, since resolving by branch name returns the most recent PR for that name, which for a reused name like `phase-a` may be a stale historical one. Omit it to resolve by branch for the `phase-X` branches in integration cleanup: `$PR_NUMBER` there is the integration PR, which vouches for no phase tip, so every phase branch would SKIP:

```bash
delete-merged-branch <B> <PR>
```

It deletes the local branch only when GitHub reports the PR merged and the local tip is provably what landed — exactly `headRefOid`, an ancestor of the merge commit, or tree-identical to it (squash/rebase) with no commits on top of `headRefOid` — and no worktree has it checked out. Every leg is fail-closed and the delete is a compare-and-swap, so commits added after the merge are never destroyed silently. Exit 0 prints `DELETED <B> <head>` and, when `<head>` is known, the leased remote delete on a second line. Exit 2 prints a `GONE`/`SKIP` line saying why it kept the branch — a report, not a failure: note it for the Step 4 Summary and carry on.

**Remote branch** — only when the helper printed a push line, and only when `AUTO_DELETE_REMOTE` isn't `true` (else GitHub already deleted it on merge): run that `git push --force-with-lease=refs/heads/<B>:<head> origin --delete refs/heads/<B>` line verbatim rather than filling the template by hand — a lease protects only the ref it names, so a line whose two `<B>`s differ deletes unchecked, and the helper shell-quotes a branch name holding shell syntax.

The lease makes it a compare-and-delete: the push is rejected unless origin's tip is still the merged head, so a branch another writer advanced after the merge survives. `remote ref does not exist` means it's already gone; any rejection (`stale info` = advanced past the merged head, or protected) → report `SKIP remote <B>`. A `DELETED` line without `<head>` (and so no push line) means leave the remote branch and report it. This stays its own visible call so a safety hook guarding remote deletes can see and gate it; the local cleanup above doesn't depend on it.

**Worktree removal** uses bare `git worktree remove <wt>` (no `--force`). Before each one, run `clear-worktree-scratch <wt>`: it syncs agent memory back to main, then deletes caliper's own untracked scratch (what `discard_changes` used to discard) so only user content can block the remove. **This stop-on-failure rule applies to every `git worktree remove` call in this section:** if `clear-worktree-scratch` or the removal exits non-zero (a failed clear means memory may be unsynced, and an ignored `.claude/` wouldn't stop the remove from deleting it), the worktree holds content the user may want — stop the cleanup chain, report the path, and let the user decide rather than force-removing it. **Phase worktrees** are located by branch, not a built path (nested in the integration worktree, siblings in older plans; earlier runs may have removed some):

```bash
git worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} $0=="branch refs/heads/phase-X"{print w}'
```

No output: already gone. Otherwise remove the printed path.

**Leave and remove the current worktree** (used below) — first match wins:
- Nested phase worktree (`…/<feature>/.claude/worktrees/phase-X`): skip `ExitWorktree` (the session belongs to the integration worktree, which orchestrate keeps using): `cd` there, remove `$WORKTREE_PATH`, and skip the `git pull --rebase` below — orchestrate fast-forwards integrate in 7d.
- Otherwise `ExitWorktree` with `action: "remove"`, `discard_changes: true` (the PR merged, so local commits are safe to discard).
  - Refused as not owner (design/implement enter worktrees by `path`): `ExitWorktree` with `action: "keep"` lifts isolation and returns to the main checkout; then remove `$WORKTREE_PATH`.
  - No-op (no worktree session): `cd "$MAIN_REPO" && git worktree remove "$WORKTREE_PATH"`, then prefix later commands with `cd "$MAIN_REPO" &&`.

**Integration branch** (`IS_INTEGRATION=true`):
1. Remove remaining phase worktrees (the lookup above, per `phase-X`) — nested ones sit inside the integration worktree, so they go first
2. If `IN_WORKTREE`: leave and remove the current worktree
3. Delete phase branches (gh-verified): for each `phase-X` from plan.json, apply the pattern above without `<PR>`
4. Delete `$BRANCH_NAME` (gh-verified)
5. `git worktree prune && git pull --rebase && git remote prune origin`

**Standard worktree** (`IN_WORKTREE=true`):
- If `IS_INTEGRATION_CWD=true`: pr-merge is running from the integration worktree for a phase PR (a manual run — orchestrate uses the phase worktree) — do NOT remove the integration worktree. Just delete `$BRANCH_NAME` (gh-verified) and prune remotes (`git remote prune origin`). While the phase worktree still exists the delete reports `SKIP … still checked out` — expected; the integration branch's own cleanup deletes the phase branch after removing its worktree. The orchestrator handles the rest in Phase Wrap-Up 7d/7e.
- If `IS_INTEGRATION_CWD=false` (normal case, CWD branch matches PR branch):
  1. Leave and remove the current worktree
  2. Delete `$BRANCH_NAME` (gh-verified)
  3. `git worktree prune && git pull --rebase && git remote prune origin`

**No worktree:** `git checkout <DEFAULT_BRANCH> && git pull --rebase && git remote prune origin`, then delete `$BRANCH_NAME` (gh-verified).

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
| Skipping `ExitWorktree` when it's available | `cd` doesn't persist across Bash tool calls — only `ExitWorktree` resets CWD at the session level. Always try `ExitWorktree` first (bar nested phase worktrees); the fallbacks cover its refusal and no-op. |
| Deleting branch before removing worktree | `delete-merged-branch` refuses (`SKIP`) a branch still checked out. Remove worktree first. |
| Using `--delete-branch` on `gh pr merge` | Fails in worktree flows. Delete branch manually after. |
| Treating `gh pr merge --auto` as blocking | It returns once auto-merge is *enabled*, not merged. Wait with `caliper-wait-pr --merged` before cleanup. |
| Polling for a bot comment naming HEAD | Bots may post nothing for a no-op push (e.g. rebase-only), so the wait never ends. Wait on check completion (`caliper-wait-pr`) instead. |

## Integration

**Preceded by:** pr-review (or manual review)

**Auto-invoked by:** orchestrate — in `pr-merge` workflow mode
