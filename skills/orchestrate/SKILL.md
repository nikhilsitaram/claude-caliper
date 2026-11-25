---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute a plan by dispatching task-implementer subagents in parallel, each in its own worktree. A phase starts once every phase in its `depends_on` has merged, so independent phases run side by side; phase PRs merge in letter order; tasks within a phase dispatch as their dependencies clear. The lead coordinates; implementers touch code.

There is no per-task review: the gate is the per-phase implementation-review over the integrated diff, plus a final review across all phases.

Templates: `./implementer-prompt.md` (for `claude-caliper:task-implementer`), `skills/implementation-review/reviewer-prompt.md` (for `claude-caliper:implementation-reviewer`), `./dispatch-subagents.md` (dispatch protocol).

## Progress Tracking

TaskCreate one entry per plan.json task ("Implement A1", ...), one "Phase {LETTER}: implementation review" per phase, and final "Create PR" / "Mark plan complete", with `addBlockedBy` mirroring task and phase `depends_on`. Mark a task `in_progress` at dispatch and `completed` when its branch merges, so a stuck task stands out.

## Setup

Before the first phase:
- Plan artifacts live in the main repo at `$MAIN_ROOT/.claude/claude-caliper/` (gitignored, so they outlive worktree cleanup). Under worktree isolation, write `$PLAN_DIR` files through Bash (`jq`, `cat >>`), never Write/Edit, and keep git calls plain (**See:** `skills/design/worktree-isolation.md`). `MAIN_ROOT` is the output of `caliper-main-root`; then, from the caller's absolute plan.json path:

  ```bash
  PLAN_JSON=$(realpath -- "<absolute-path-passed-by-caller>")
  PLAN_DIR=$(dirname "$PLAN_JSON")
  ```

  Use these absolute paths downstream: phase worktrees lack the gitignored artifacts.
- `DESIGN_DOC="$(ls "$PLAN_DIR"/design-*.md 2>/dev/null | head -1)"` fills `{DESIGN_DOC}` in the implementer prompt.
- `WORKFLOW=$(jq -r '.workflow' "$PLAN_JSON")`: once created, the plan, not caliper-settings, is the source of truth.
- `TASK_IMPLEMENTER_MODEL=$(caliper-settings get task_implementer_model)` and `IMPL_REVIEWER_MODEL=$(caliper-settings get implementation_reviewer_model)` fill `{TASK_IMPLEMENTER_MODEL}` and `{IMPL_REVIEWER_MODEL}`.
- `PHASE_COUNT=$(jq '.phases | length' "$PLAN_JSON")`
- Gates: `validate-plan --schema "$PLAN_JSON"` (file-set overlap, structure), `validate-plan --check-entry "$PLAN_JSON" --stage execution` (no wasted work), `validate-plan --check-base "$PLAN_JSON"` (no wrong-worktree dispatch), `validate-plan --consistency "$PLAN_JSON"` (state drift).
- Sibling phases (neither in the other's transitive `depends_on`) run in parallel. If the plan has any, confirm them. **See:** `./parallel-phases.md` Confirm Siblings
- `validate-plan --update-status "$PLAN_JSON" --plan --status "In Development"`
- `PLAN_BASE_SHA` is what `validate-plan --set-base "$PLAN_JSON" --plan --sha HEAD --if-unset` prints: it records HEAD on the first run and keeps that base on a resume, so review ranges start where the plan did.
- `[ -f "$PLAN_DIR/reviews.json" ] || echo '[]' > "$PLAN_DIR/reviews.json"`
- `git push -u origin HEAD`
- Read the dispatch protocol: **See:** `./dispatch-subagents.md`

Every status change goes through `validate-plan --update-status`, which keeps plan.json and plan.md in sync and enforces the transition gates. Re-run `validate-plan --consistency "$PLAN_JSON"` after status changes to catch state drift.

## Per-Phase Execution

Multi-phase only; a single-phase plan goes to Single-Phase Plans. `validate-plan --ready-phases "$PLAN_JSON"` lists the phases to work on now: not yet Complete, every `depends_on` phase merged (In Progress ones included, so a resume picks them up). A phase counts as merged once `--mark-merged` records it (Phase Wrap-Up step 7); squash-merge usually deletes the phase branch, so ancestry can't stand in.

1. Reconcile (resume): from the integration worktree, `git pull --ff-only origin integrate/<feature>` (as in step 7d, including its failure handling): a phase PR may have merged while the run was stopped. Then, for each phase whose status starts with "Complete" but lacks `merged` (plans that predate the marker included), run `gh pr list --base integrate/<feature> --head phase-<letter> --state merged --json number --jq 'length'`. Non-zero → `validate-plan --mark-merged "$PLAN_JSON" --phase {LETTER}`. Zero → it still owes Phase Wrap-Up step 7 (7a's catch-up check included), reusing any open PR.
2. Run `--ready-phases`. One phase listed → run the sections below for it. Several → start them all together. **See:** `./parallel-phases.md`
3. After each phase merges, re-run `--ready-phases` and start what it newly lists. When every phase is merged → After All Phases.

### Prepare Phase

1. Enter the phase worktree (multi-phase only; single-phase stays in the feature worktree). First, from the integration worktree root, re-run `validate-plan --check-base "$PLAN_JSON"`: it checks the current branch against the plan's `integration_branch`, so it must run before you move to `phase-<letter>`. Then `git worktree prune` and reuse what a stopped run left:
   - A surviving branch (`git rev-parse --verify --quiet refs/heads/phase-<letter>` succeeds) must have forked from this plan: if `git merge-base --is-ancestor <BASE> phase-<letter>` fails, it's stale from another plan; stop and surface it. `<BASE>` is the phase's recorded `base_sha` (`jq -r --arg l {LETTER} '.phases[] | select(.letter == $l) | .base_sha // "HEAD"' "$PLAN_JSON"`) as a literal, not the integration tip, which a sibling's merge can move past the fork point.
   - If `git worktree list --porcelain` lists `branch refs/heads/phase-<letter>`, use that worktree (its `worktree` line is `PHASE_WORKTREE`); else if the branch exists, `git worktree add .claude/worktrees/phase-<letter> phase-<letter>` (no `-b`); else `git worktree add .claude/worktrees/phase-<letter> -b phase-<letter>`. It nests in the integration worktree, `PHASE_WORKTREE="$MAIN_ROOT/.claude/worktrees/<feature>/.claude/worktrees/phase-<letter>"`; a sibling under the main checkout is unusable under isolation.
   - `cd` into it and `seed-agent-memory "$PHASE_WORKTREE"` so the Phase Wrap-Up reviewer reads accumulated memory (synced back at step 7e).
2. `PHASE_BASE_SHA`: run Setup's `--set-base` command from the worktree, with `--phase {LETTER}` in place of `--plan`.
3. Bootstrap dependencies in the worktree. **See:** `skills/design/dependency-bootstrap.md`
4. Extract context: tasks JSON, plan dir, phase dir, prior completions (from the `depends_on` closure; prior phases' handoff notes are in plan.json).
5. `validate-plan --update-status "$PLAN_JSON" --phase {LETTER} --status "In Progress"`: no task can move to `in_progress` while its phase is "Not Started".
6. Reconcile tasks a stopped run left behind. **See:** `./dispatch-subagents.md` Resuming In-Flight Tasks

### Dispatch and Complete Tasks

Follow `./dispatch-subagents.md`: dispatch only what `validate-plan --ready "$PLAN_JSON" --phase {LETTER}` lists, and merge each verified task branch into the phase branch.

### Phase Wrap-Up

After all tasks complete and their branches merge:
1. Dispatch implementation-review over `PHASE_BASE_SHA..HEAD` with `model: "$IMPL_REVIEWER_MODEL"`; run the Review Loop Protocol (scope: `phase-{letter_lower}`).
2. `validate-plan --check-review "$PLAN_JSON" --type impl-review --scope phase-{letter_lower}`
3. Append the review changes to `${PHASE_DIR}/completion.md` (`cat >>`) under a `### Implementation Review Changes` heading, which `./parallel-phases.md` Reviews looks for.
4. `validate-plan --criteria "$PLAN_JSON" --phase {LETTER}`
5. **Record cross-phase handoff notes.** For each future-phase task whose `depends_on` names a task from this phase, record the shipped interface (names, paths, signatures, usage), including review-driven changes. It writes plan.json and re-renders plan.md:

   ```bash
   validate-plan --add-handoff "$PLAN_JSON" --task {DOWNSTREAM_ID} --from {SOURCE_ID} --note "src/auth/middleware.ts exports validateToken(); use as Hono middleware: app.use('/dashboard/*', validateToken())."
   ```

   - **Ad-hoc** (context useful to a future task with no `depends_on` link): run `validate-plan --add-dep "$PLAN_JSON" --task {DOWNSTREAM_ID} --depends-on {SOURCE_ID}` first, then `--add-handoff`. `--add-dep` refuses a cross-phase edge unless the downstream phase (transitively) depends on this one. A sibling may already be running without this phase's code, so for one, put the context in this phase's `completion.md` instead.
   - **Opt-out:** if downstream tasks can derive everything from `completion.md`, append a `## Handoff Notes` section to `{PHASE_DIR}/completion.md` whose first content line starts with `None` (e.g., `None — downstream tasks derive context from completion.md.`).
   - **Validate:** `validate-plan --check-handoffs "$PLAN_JSON" --phase {LETTER}` fails if a later-phase task depending on this phase lacks a handoff and no opt-out exists.
6. `validate-plan --update-status "$PLAN_JSON" --phase {LETTER} --status "Complete (YYYY-MM-DD)"`, only after criteria and handoffs pass, so a resumed run never sees Complete with gates unmet.
7. (Multi-phase) Merge the phase PR into the integration branch: every phase including the last, whatever the `workflow`. The final integrate→main PR comes in After All Phases.
   a. `validate-plan --check-merge-order "$PLAN_JSON" --phase {LETTER}`. If it fails, an earlier sibling hasn't merged and this phase waits (**See:** `./parallel-phases.md` Merge Order). Then, from the phase worktree, if `git merge-base --is-ancestor integrate/<feature> HEAD` fails, a sibling merged after this branch forked: catch up first (`./parallel-phases.md` Catch Up). Then reuse the open phase PR (`gh pr list --head phase-<letter> --state open --json url --jq '.[0].url'`) or run `pr-create --base integrate/<feature>`.
   b. `REVIEW_WAIT=$(caliper-settings get review_wait_minutes)`
   c. `$REVIEW_WAIT` == 0 → invoke `pr-merge`; else `pr-review --automated-merge` (which invokes `pr-merge`). No `gh pr checks` poll first: `pr-merge` enables auto-merge, so GitHub gates on CI, and waits (up to `merge_wait_minutes`) for `MERGED`. Then confirm `gh pr view <phase PR> --json state -q .state` prints `MERGED`. If not, dispatch nothing new, finish in-flight implementers, and stop until GitHub merges it: without the stop, step d's `--ff-only` would succeed as a no-op and start dependent phases without this one. Once `MERGED`: `validate-plan --mark-merged "$PLAN_JSON" --phase {LETTER}`
   d. From the integration worktree (the lead's primary CWD), fast-forward local integrate: `cd "$MAIN_ROOT/.claude/worktrees/<feature>" && git pull --ff-only origin integrate/<feature>`. Absolute `cd`, since a relative one fails from the nested phase worktree; `--ff-only`, so divergent commits surface instead of being reset away. On failure, stop the loop and surface the worktree path.
   e. Remove the phase worktree if pr-merge hasn't. Locate it by branch (a resumed older plan may use the sibling layout): `git worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} $0=="branch refs/heads/phase-<letter>"{print w}'`; no output means it's gone. `clear-worktree-scratch` the path (it syncs agent memory, backing up the `SubagentStop` hook, and deletes caliper's untracked scratch that would block the remove), then `git worktree remove` it, no `--force`. A failed clear (memory may be unsynced) or remove (uncommitted content) stops the loop with the path surfaced.

## Review Loop Protocol (Two-Pass Cap)

At most two dispatches. Residual findings fall to the next gate (the final review, then PR review), never a third pass. For each dispatch:

1. Extract the response's last `json review-summary` fenced block. Missing/malformed: on pass 1, re-dispatch once (using the pass-2 slot); on pass 2, escalate via AskUserQuestion.
2. Triage each issue: fix, or dismiss with reasoning. Issues with `non_dismissible: true` must be fixed; dismissing one invalidates the review record.
3. Fix all actionable findings, verifying each inline (grep/read), and commit the fixes: a delta pass 2 reads committed history, and Catch Up's rebase refuses a dirty tree.
4. Pass 1 found a critical or high issue → dispatch a delta pass 2 over the same scope. Otherwise, or after pass 2 (remaining findings fixed inline), append the pass record to `{PLAN_DIR}/reviews.json` and advance:
`{"type":"impl-review","scope":"{SCOPE}","pass":N,"issues_found":N,"severity":{...},"actionable":N,"dismissed":N,"dismissals":[...],"fixed":N,"remaining":0,"verdict":"pass","timestamp":"ISO8601"}`

## Single-Phase Plans

Skip the integration branch and phase worktrees; work in the feature worktree. Below (After All Phases too), `--check-workflow` means `validate-plan --check-workflow "$PLAN_JSON" --branch <feature>` (multi-phase: `integrate/<feature>`, as plan.json's `integration_branch` records), the branch a literal: pr-merge's cleanup leaves the CWD on main.

1. If phase A's status already starts with "Complete", a stopped run got past its wrap-up: skip to step 2. Otherwise run Prepare Phase steps 2–6, dispatch and complete tasks with the same dispatch protocol, then Phase Wrap-Up steps 1–6 (scope `phase-a`; step 5 has nothing downstream to hand off). Step 6 marks phase A Complete, which `--plan --status done` requires.
2. `validate-plan --criteria "$PLAN_JSON" --plan`
3. `validate-plan --update-status "$PLAN_JSON" --plan --status done`
4. Route on workflow:
   - `"orchestrate"`: `--check-workflow`, report the worktree path, stop
   - `"pr-create"`: pr-create (targets main), `--check-workflow`, stop
   - `"pr-ready"`: pr-create (targets main), then pr-review --automated-fix, `--check-workflow`, stop; the PR is left at the bar or stuck, unmerged
   - `"pr-merge"`: pr-create, read `REVIEW_WAIT=$(caliper-settings get review_wait_minutes)`, pr-review --automated-merge (if `$REVIEW_WAIT` is 0, pr-merge directly instead), `--check-workflow`

## After All Phases (Multi-Phase Only)

1. `validate-plan --criteria "$PLAN_JSON" --plan`. If it exits 1, don't mark complete.
2. Final review: dispatch implementation-review over `PLAN_BASE_SHA..HEAD`; run the Review Loop Protocol (scope: `final`).
3. `validate-plan --check-review "$PLAN_JSON" --type impl-review --scope final`
4. `validate-plan --update-status "$PLAN_JSON" --plan --status done`
5. Route on workflow:
   - `"orchestrate"`: `--check-workflow`, report the worktree path, stop
   - `"pr-merge"`: create the final PR, pr-review --automated-merge (if `$REVIEW_WAIT`, read as in 7b, is 0, pr-merge directly instead; no pre-merge check poll, as in 7c), `--check-workflow`, clean up
   - `"pr-create"`: create the final PR, `--check-workflow`, stop
   - `"pr-ready"`: create the final PR, pr-review --automated-fix, `--check-workflow`, stop

Run continuously: beyond the stops named above, only Rule 4 deviations pause the loop, and `pr-review --automated-merge` auto-fixes review feedback.

## Integration

**Workflow:** design → draft-plan → **this skill** → pr-create → pr-review → pr-merge
**See:** `skills/implement/tdd.md`
