# Parallel Phases

Read this at Setup when the plan has sibling phases, when `validate-plan --ready-phases` lists more than one phase, when a phase is waiting on a sibling's merge, before dispatching a phase's review while it has siblings, or when step 7a sends a phase to Catch Up. Example: A has `depends_on: []`, while B and C each have `["A"]`. Once A merges, B and C run side by side. Each still gets the full per-phase flow (Prepare Phase, dispatch, Phase Wrap-Up). This file covers only what changes when two of those flows run at once.

## Confirm Siblings

Run this at Setup. Ask only if the plan wasn't drafted and plan-reviewed earlier in this session. A plan drafted before phase `depends_on` drove scheduling never had its completeness checked, and neither has a plan picked up on a resume. Ask one AskUserQuestion that names the sibling groups. The options are: run as declared, or serialize by adding each phase's predecessor letter to its `depends_on` (a `jq` write to `$PLAN_JSON`, then re-run `--schema`).

## Start Each Ready Phase

Run Prepare Phase for each listed phase in turn, from the integration worktree. Prepare Phase step 1's `--check-base` passes only on the integration branch, so between phases `cd` back with an absolute path: `cd "$MAIN_ROOT/.claude/worktrees/<feature>"`. Each phase gets its own nested worktree at `.claude/worktrees/phase-<letter>` and its own `--set-base --phase`. Every phase forks from the same integration tip.

## One Dispatch Loop, Many Parents

Keep one map of agent → (task ID, phase letter). The dispatch protocol derives `PARENT_WORKTREE` from the CWD and resets the CWD to it after each removal. So before running its Dispatch, Process Completions or After Completion steps for a task, `cd` into that task's phase worktree (absolute path, in its own Bash call). Never mix two phases' paths in one call: the worktree-isolation guard refuses chains that span worktrees, so keep each step a plain call with literal paths.

- **Ready tasks:** run `validate-plan --ready "$PLAN_JSON" --phase <L>` for each active phase. Don't use the unscoped `--ready`: it also lists tasks of phases that haven't started yet.
- **Dispatch:** send every ready task across all active phases in a single message.
- **A phase's last task merges:** run Phase Wrap-Up steps 1–6 for that phase while its siblings keep working. Handle completion notifications that arrive in the meantime as usual, each in its own phase worktree.

## Reviews

Each phase gets its own implementation-review over its own `PHASE_BASE_SHA..HEAD`. A shareable class of finding is the same pattern, the same seam, or the same CI matrix gap. Siblings finish review at different times, so sharing runs one way, from the phase that reviewed first to the one reviewing later:

- **Passing it on.** When you dispatch a phase's review (Phase Wrap-Up step 1), look for siblings, merged or not, whose `$PLAN_DIR/phase-<letter>/completion.md` has a `### Implementation Review Changes` section (step 3 writes it, and omits it when there was nothing to fix). For each one, add to the reviewer's `{PHASE_CONTEXT}` the file's path and the instruction to check this diff for the same classes. For an unmerged sibling, also ask it to check that sibling's branch (`git diff <its base_sha>..phase-<letter>`, a ref, so there's no need to enter its worktree) and to prefix those hits with `phase-<letter>:`, since file paths are identical across branches. Skip a merged sibling's branch: it's usually deleted, and the sibling's own review already covered its own classes.
- **A hit on a sibling still in review** (steps 1–3): hold it until that review finishes, then handle it as below.
- **A hit on a sibling whose PR hasn't opened** (steps 4–6, or waiting its merge turn) is a fix, not a dismissal: its branch is unpushed, so the fix lands before its PR exists. `cd` into that sibling's phase worktree in its own Bash call, commit the fix there, append it to that sibling's `### Implementation Review Changes` (creating the section if absent), and re-run `validate-plan --criteria "$PLAN_JSON" --phase {LETTER}` with the sibling's letter. Its review isn't re-dispatched. Then `cd` back to this phase's worktree (absolute path, own call) and carry on with its Wrap-Up.
- **A hit on a sibling whose PR is open or merged:** leave its branch alone, since pr-review may be merging it or it's already gone. Either way that sibling is a lower letter, so this phase rebases onto its merged code at Catch Up. List the hit under `### Deferred Sibling Fixes` in this phase's `completion.md`, kept apart from its review changes, since those read as already fixed. Record it in the review as dismissed with the reason "deferred to Catch Up". If `integrate/<feature>` is already an ancestor of this branch (the sibling merged before this phase forked), Catch Up won't run and the code is already here, so fix the hit now instead.
- **The reverse direction.** This phase's own shareable-class findings reach any sibling dispatched to review later, through this phase's `completion.md`. A sibling whose review was dispatched before that section existed, whether finished, still running or merged, won't see them. Before you dismiss such a finding as local, give that sibling's code one grep (its `phase-<letter>` branch, or `integrate/<feature>` once it has merged), and handle a hit as above.

The final cross-phase review is the backstop.

## Merge Order

Phase PRs merge in letter order, so `--check-merge-order` fails for a Complete phase while an earlier phase is unmerged. The lowest unmerged phase depends only on merged phases, so the order can't deadlock.

A phase that finishes early **waits**. Its review, criteria and Complete status are done, but its branch stays unpushed (pr-create pushes it on its turn). Keep running the loop for the other phases. When a phase's PR merges (step 7c, `--mark-merged`, 7d's fast-forward), resume each waiting phase in letter order whose `--check-merge-order` now passes, at step 7a.

After every merge, also re-run `--ready-phases`. Phases whose dependencies just merged start from the new integration tip.

## Catch Up

Step 7a sends a phase here whenever `integrate/<feature>` isn't an ancestor of its HEAD. That covers a phase that waited, one that finished after a sibling had already merged, and one resumed as Complete-but-unmerged. Its review and criteria ran against the old base, so re-check them against the new one:

1. From the phase worktree: `git rebase integrate/<feature>`. Rebase, not merge: pr-create's own `git rebase origin/<BASE>` would flatten a merge commit and replay its conflicts. After this it's a no-op, since 7d (or reconcile, on a resume) already fast-forwarded local integrate to the remote tip. The branch is still unpushed, because a PR opens only once every earlier phase has merged and the base can't move after that, so no force-push is needed. Resolve any conflict the way pr-create does. `--schema`'s `sibling_fileset_overlap` warning predicts where it will be. If resolving it needs a judgment call about the code, `git rebase --abort` and surface it to the user with the worktree path.
2. First fix every hit listed under `### Deferred Sibling Fixes` in this phase's `completion.md` (see Reviews), moving each entry to its `### Implementation Review Changes` as it lands so a resumed run doesn't redo it. Then re-run the phase criteria: `validate-plan --criteria "$PLAN_JSON" --phase {LETTER}`. A failure means the sibling's merged work broke this phase. Treat it as a review finding: fix it, then re-run.
3. Return to step 7a and open the PR. pr-create applies the repo's own PR conventions, such as a version bump, against the new merge-base.
