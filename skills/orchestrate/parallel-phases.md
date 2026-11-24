# Parallel Phases

Read this when `validate-plan --ready-phases` lists more than one phase, or when a phase is waiting on a sibling's merge. Example: A has `depends_on: []`, while B and C each have `["A"]`. Once A merges, B and C run side by side. Each still gets the full per-phase flow (Prepare Phase, dispatch, Phase Wrap-Up). This file covers only what changes when two of those flows run at once.

## Start Each Ready Phase

Run Prepare Phase for each listed phase in turn, from the integration worktree. Prepare Phase step 1's `--check-base` passes only on the integration branch, so between phases `cd` back with an absolute path: `cd "$MAIN_ROOT/.claude/worktrees/<feature>"`. Each phase gets its own nested worktree at `.claude/worktrees/phase-<letter>` and its own `--set-base --phase`. Every phase forks from the same integration tip.

## One Dispatch Loop, Many Parents

Keep one map of agent → (task ID, phase letter). The dispatch protocol derives `PARENT_WORKTREE` from the CWD and resets the CWD to it after each removal. So before running its Dispatch, Process Completions or After Completion steps for a task, `cd` into that task's phase worktree (absolute path, in its own Bash call). Never mix two phases' paths in one call: the worktree-isolation guard refuses chains that span worktrees, so keep each step a plain call with literal paths.

- **Ready tasks:** run `validate-plan --ready "$PLAN_JSON" --phase <L>` for each active phase. Don't use the unscoped `--ready`: it also lists tasks of phases that haven't started yet.
- **Dispatch:** send every ready task across all active phases in a single message.
- **A phase's last task merges:** run Phase Wrap-Up steps 1–6 for that phase while its siblings keep working. Handle completion notifications that arrive in the meantime as usual, each in its own phase worktree.

## Reviews

Each phase gets its own implementation-review over its own `PHASE_BASE_SHA..HEAD`. A finding of a class that a sibling phase could share (the same pattern, the same seam, the same CI matrix gap) is worth one grep on the sibling's branch before you dismiss it as local. The final cross-phase review is the backstop.

## Merge Order

Phase PRs merge in letter order, so `--check-merge-order` fails for a Complete phase while an earlier phase is unmerged. The lowest unmerged phase depends only on merged phases, so the order can't deadlock.

A phase that finishes early **waits**. Its review, criteria and Complete status are done, but its branch stays unpushed (pr-create pushes it on its turn, so no force-push is ever needed). Keep running the loop for the other phases. When a phase's PR merges (step 7c, `--mark-merged`, 7d's fast-forward), take each waiting phase in letter order whose `--check-merge-order` now passes:

1. `cd` into its phase worktree and merge the updated integration branch: `git merge integrate/<feature>`. Merge rather than rebase: the branch already holds task merge commits, and the PR is squash-merged anyway. If it conflicts (`--schema`'s `sibling_fileset_overlap` warning predicts where), stop and surface the conflict to the user with the worktree path. The lead coordinates and doesn't resolve code conflicts.
2. Re-run the phase criteria: `validate-plan --criteria "$PLAN_JSON" --phase {LETTER}`. A failure means the sibling's merged work broke this phase. Treat it as a review finding: fix it, then re-run.
3. Continue with Phase Wrap-Up step 7a (`pr-create` applies the repo's own PR conventions, such as a version bump, against the new merge-base).

After every merge, also re-run `--ready-phases`. Phases whose dependencies just merged start from the new integration tip.
