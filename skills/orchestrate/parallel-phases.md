# Parallel Phases

Read this when the plan has sibling phases: at Setup, when `validate-plan --ready-phases` lists more than one phase, when a phase waits on a sibling's merge, before dispatching a phase's review while it has siblings, or when step 7a sends a phase to Catch Up. Example: A has `depends_on: []`, B and C each `["A"]`; once A merges, B and C run side by side. Each still gets the full per-phase flow (Prepare Phase, dispatch, Phase Wrap-Up); this file covers only what changes when two run at once.

## Confirm Siblings

At Setup, ask only if the plan wasn't drafted and plan-reviewed earlier in this session: a plan drafted before phase `depends_on` drove scheduling never had its completeness checked, and neither has one picked up on a resume. Ask one AskUserQuestion naming the sibling groups, with two options: run as declared, or serialize by adding each phase's predecessor letter to its `depends_on` (a `jq` write to `$PLAN_JSON`, then re-run `--schema`).

## Start Each Ready Phase

Run Prepare Phase for each listed phase in turn, from the integration worktree. Prepare Phase step 1's `--check-base` checks against the integration branch, so between phases `cd` back with an absolute path: `cd "$MAIN_ROOT/.claude/worktrees/<feature>"`. Each phase gets its own nested worktree at `.claude/worktrees/phase-<letter>` and its own `--set-base --phase`, all forked from the same integration tip.

## One Dispatch Loop, Many Parents

Keep one map of agent → (task ID, phase letter). `caliper-phase-dispatch` takes each task's phase worktree as an argument, so Dispatch needs no `cd`. Process Completions and After Completion run from the parent, so first `cd` into that task's phase worktree (absolute path, its own Bash call). Never mix two phases' paths in one call: the worktree-isolation guard refuses chains that span worktrees.

- **Ready tasks:** `validate-plan --ready "$PLAN_JSON" --phase <L>` for each active phase. The unscoped `--ready` also lists tasks of phases that haven't started.
- **Dispatch:** every ready task across all active phases in a single message.
- **A phase's last task merges:** run Phase Wrap-Up steps 1–6 for it while its siblings keep working, handling completions that arrive meanwhile as usual, each in its own phase worktree.

## Reviews

Each phase gets its own implementation-review over its own `PHASE_BASE_SHA..HEAD`. Siblings finish review at different times, so sharing runs one way. When you dispatch a phase's review, for each sibling (merged ones too) whose `$PLAN_DIR/phase-<letter>/completion.md` has a `### Implementation Review Changes` section, add that path to the reviewer's `{PHASE_CONTEXT}` and ask it to check this diff for the same classes (same pattern, same seam, same CI matrix gap). For an unmerged sibling, also ask it to check that sibling's branch (`git diff integrate/<feature>...phase-<letter>`, three dots, so a rebased sibling shows only its own work) and to prefix those hits `phase-<letter>:`. In reverse, a sibling whose review was already dispatched (running or finished), or that merged, won't see this phase's shareable-class findings, so grep its code (`phase-<letter>`, or `integrate/<feature>` once merged) before dismissing one as local.

A hit on a sibling is a fix. It lies outside this phase's diff, so it doesn't count toward this review's `remaining`. Note it as one line in this phase's `completion.md`, naming its route, so a resume doesn't lose it. Route it by the sibling's state:

- **Past review, unpushed:** from the sibling's worktree (own Bash call), fix it on that branch and commit it (Catch Up's rebase refuses a dirty tree), re-run `validate-plan --criteria "$PLAN_JSON" --phase {LETTER}` with the sibling's letter, then `cd` back.
- **PR open or merged:** this phase reaches Catch Up anyway, so fix it there after the rebase; if the sibling's code is already in this phase's base, fix it now.
- **Still in review:** hand it to that review's triage.

The final cross-phase review is the backstop.

## Merge Order

Phase PRs merge in letter order, so `--check-merge-order` fails for a Complete phase while an earlier phase is unmerged. The lowest unmerged phase depends only on merged phases, so the order can't deadlock.

A phase that finishes early **waits**: review, criteria and Complete status done, branch unpushed (pr-create pushes it on its turn). Keep running the loop for the other phases. When a phase's PR merges (step 7c, `--mark-merged`, 7d's fast-forward), resume each waiting phase, in letter order, whose `--check-merge-order` now passes, at step 7a. Also re-run `--ready-phases`: phases whose dependencies just merged start from the new integration tip.

## Catch Up

Step 7a sends a phase here whenever `integrate/<feature>` isn't an ancestor of its HEAD: it waited, finished after a sibling merged, or resumed as Complete-but-unmerged. Its review and criteria ran against the old base, so re-check them against the new one:

1. From the phase worktree: `git rebase integrate/<feature>`. Rebase, not merge: pr-create's own `git rebase origin/<BASE>` would flatten a merge commit and replay its conflicts, and after this rebase it's a no-op, since 7d (or reconcile, on a resume) already fast-forwarded local integrate to the remote tip. No force-push is needed: the branch is unpushed until every earlier phase has merged, after which the base can't move. Resolve conflicts the way pr-create does; `--schema`'s `sibling_fileset_overlap` warning predicts where they'll be. If one needs a judgment call about the code, `git rebase --abort` and surface it with the worktree path.
2. Fix any sibling hit this phase's `completion.md` routes to Catch Up (see Reviews), then re-run `validate-plan --criteria "$PLAN_JSON" --phase {LETTER}`. A failure means the sibling's merged work broke this phase: treat it as a review finding, fix it, and re-run.
3. Return to step 7a and open the PR, applying the repo's PR conventions (such as a version bump) against the new merge-base.
