---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute plans by dispatching task-implementer subagents in parallel with worktree isolation. Phases run sequentially; tasks within a phase dispatch as their dependencies clear.

**Core principle:** The lead coordinates — dispatched implementers touch code.

Per-task review is not part of this flow. The single review gate is the per-phase implementation-review over the integrated diff (plus a final review across all phases). Implementers read the codebase directly at full context — plans carry intent, not pasted code.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./implementer-prompt.md` | Invocation template for `claude-caliper:task-implementer` |
| `skills/implementation-review/reviewer-prompt.md` | Invocation template for `claude-caliper:implementation-reviewer` |
| `./dispatch-subagents.md` | Subagents dispatch protocol |

## Progress Tracking

TaskCreate one entry per task in plan.json (e.g. "Implement A1", "Implement A2", ...) plus per phase "Phase {LETTER}: implementation review", and final "Create PR" / "Mark plan complete". Set `addBlockedBy` to mirror task `depends_on` and phase ordering. Mark `in_progress` when you dispatch a task and `completed` when its task branch merges — granular per-task tracking surfaces stuck tasks immediately rather than hiding them inside a phase-wide "Execute tasks" entry.

## Setup

Before first phase:
- Resolve main repo and plan paths. Plan artifacts live in the main repo at `$MAIN_ROOT/.claude/claude-caliper/` (gitignored, so they outlive worktree cleanup), not in the worktree CWD. The session usually runs worktree-isolated: write `$PLAN_DIR` files through Bash (`jq`, `cat >>`), never Write/Edit, and keep git calls plain (**See:** `skills/design/worktree-isolation.md`). `MAIN_ROOT` is `git rev-parse --path-format=absolute --git-common-dir` minus `/.git`; then separately:

  ```bash
  PLAN_JSON=$(realpath -- "<absolute-path-passed-by-caller>")
  PLAN_DIR=$(dirname "$PLAN_JSON")
  ```

  The caller supplies the absolute plan.json path; use the absolute `$PLAN_JSON` / `$PLAN_DIR` downstream.
- Resolve the design doc (implementers read it for feature-wide context): `DESIGN_DOC="$(ls "$PLAN_DIR"/design-*.md 2>/dev/null | head -1)"` — the design skill writes it as `$PLAN_DIR/design-<topic>.md`. Substituted into `{DESIGN_DOC}` in the implementer prompt.
- Read workflow: `WORKFLOW=$(jq -r '.workflow' "$PLAN_JSON")`
Note: `workflow` comes from plan.json (set by design), not caliper-settings — the plan is the single source of truth once created.
- Read task implementer model: `TASK_IMPLEMENTER_MODEL=$(caliper-settings get task_implementer_model)`
- Read implementation reviewer model: `IMPL_REVIEWER_MODEL=$(caliper-settings get implementation_reviewer_model)`
Note: These model settings are substituted into dispatch template variables `{TASK_IMPLEMENTER_MODEL}` and `{IMPL_REVIEWER_MODEL}` when dispatching implementers and the phase implementation-review.
- Count phases: `PHASE_COUNT=$(jq '.phases | length' "$PLAN_JSON")`
- Validate schema: `validate-plan --schema "$PLAN_JSON"`
- Validate entry gate: `validate-plan --check-entry "$PLAN_JSON" --stage execution`
- Validate base branch: `validate-plan --check-base "$PLAN_JSON"`
- Validate consistency: `validate-plan --consistency "$PLAN_JSON"`
- `validate-plan --update-status "$PLAN_JSON" --plan --status "In Development"`
- `PLAN_BASE_SHA` is what `validate-plan --set-base "$PLAN_JSON" --plan --sha HEAD --if-unset` prints: it records HEAD on the first run and keeps that base on a resume.
- `[ -f "$PLAN_DIR/reviews.json" ] || echo '[]' > "$PLAN_DIR/reviews.json"`
- Push branch: `git push -u origin HEAD`
- Read the dispatch protocol: **See:** `./dispatch-subagents.md`

## Per-Phase Execution (Sequential)

Process phases in order (A, B, C...). For each phase:

### Prepare Phase

1. Enter the phase worktree (multi-phase only — single-phase stays in the feature worktree). Phase status is the signal: squash-merge in step 7 usually deletes the phase branch, so ancestry checks are unreliable.
   - If phase status starts with "Complete": run `gh pr list --base integrate/<feature> --head phase-<letter> --state merged --json number --jq 'length'`. If non-zero, the phase is fully merged — skip to next phase. If zero (status Complete but PR not yet merged), skip directly to Phase Wrap-Up step 7, reusing any open PR or creating one if absent.
   - Otherwise (status "Not Started" or "In Progress"): re-validate the base branch **before creating the worktree** — `validate-plan --check-base "$PLAN_JSON"` demands the current branch equal `integration_branch`, so it can never pass once you're on `phase-<letter>`. The phase worktree nests inside the integration worktree — `PHASE_WORKTREE="$MAIN_ROOT/.claude/worktrees/<feature>/.claude/worktrees/phase-<letter>"` (a sibling under the main checkout is unusable under isolation). From the integration worktree root, run `git worktree prune` and reuse what a stopped run left. A surviving branch (`git rev-parse --verify --quiet refs/heads/phase-<letter>` succeeds) must have forked from this integration branch: if `git merge-base --is-ancestor HEAD phase-<letter>` fails, it's stale from another plan — stop and surface it to the user. Then: if `git worktree list --porcelain` lists `branch refs/heads/phase-<letter>`, use that worktree (its `worktree` line is `PHASE_WORKTREE`); else if the branch exists, `git worktree add .claude/worktrees/phase-<letter> phase-<letter>` (no `-b`); else `git worktree add .claude/worktrees/phase-<letter> -b phase-<letter>`. `cd` into it and `seed-agent-memory "$PHASE_WORKTREE"` so the Phase Wrap-Up implementation-reviewer reads accumulated memory (synced back at step e). Continue with the remaining numbered steps below.
2. `PHASE_BASE_SHA`: run Setup's `--set-base` command from the worktree, with `--phase {LETTER}` in place of `--plan`.
3. **Bootstrap dependencies** in the worktree. **See:** skills/design/dependency-bootstrap.md
4. Extract context: tasks JSON, plan dir, phase dir, prior completions (from depends_on closure) — prior-phase handoff notes are recorded in plan.json (written at prior phase's wrap-up via `--add-handoff`) and render into plan.md
5. Set phase to "In Progress": `validate-plan --update-status "$PLAN_JSON" --phase {LETTER} --status "In Progress"` — required before any task can be marked in_progress (transition gate rejects task advancement when parent phase is "Not Started")
6. Reconcile tasks a stopped run left behind. **See:** `./dispatch-subagents.md` Resuming In-Flight Tasks

### Dispatch and Complete Tasks

Follow the dispatch protocol in `./dispatch-subagents.md`. Invariants:
- Only dispatch what `validate-plan --ready "$PLAN_JSON" --phase {LETTER}` lists
- On implementer completion: verify the commit landed on the task branch, validate criteria (`validate-plan --criteria "$PLAN_JSON" --task {TASK_ID} --cwd "$TASK_WORKTREE"`), merge it into the phase branch, then check for newly unblocked tasks
- No per-task review — the phase implementation-review (Phase Wrap-Up) is the review gate

### Phase Wrap-Up

After all tasks complete and branches merged:
1. Dispatch implementation-review with `PHASE_BASE_SHA..HEAD` using `model: "$IMPL_REVIEWER_MODEL"`, run Review Loop Protocol (scope: `phase-{letter_lower}`)
2. `validate-plan --check-review "$PLAN_JSON" --type impl-review --scope phase-{letter_lower}`
3. Append review changes to `${PHASE_DIR}/completion.md` (`cat >>`)
4. Run phase criteria: `validate-plan --criteria "$PLAN_JSON" --phase {LETTER}`
5. **Record cross-phase handoff notes** for downstream tasks. For each task in a future phase whose `depends_on` references a task from this phase, record a handoff in plan.json describing the shipped interface — names, paths, signatures, usage. Recording post-wrap-up (rather than before next-phase dispatch) means notes reflect the shipped reality, including any review-driven interface changes:

   ```bash
   validate-plan --add-handoff "$PLAN_JSON" --task {DOWNSTREAM_ID} --from {SOURCE_ID} --note "Auth middleware exports validateToken() from src/auth/middleware.ts. Use as Hono middleware: app.use('/dashboard/*', validateToken())."
   ```

   This writes the handoff into plan.json (the single source of truth) and re-renders it into plan.md — no task `.md` files are touched.

   **Ad-hoc handoffs (no current `depends_on` link).** When implementation surfaces context useful to a future task that wasn't anticipated at design time, register the dependency first: `validate-plan --add-dep "$PLAN_JSON" --task {DOWNSTREAM_ID} --depends-on {SOURCE_ID}`, then record the handoff with `--add-handoff` as above.

   **Opt-out.** If downstream tasks can derive everything they need from `completion.md` alone, append a `## Handoff Notes` section to `{PHASE_DIR}/completion.md` whose first content line starts with `None` (e.g., `None — downstream tasks derive context from completion.md.`).

   **Validate:** `validate-plan --check-handoffs "$PLAN_JSON" --phase {LETTER}` — fails if any later-phase task depending on a task in this phase lacks a recorded handoff AND no opt-out block exists.
6. Update status: `validate-plan --update-status "$PLAN_JSON" --phase {LETTER} --status "Complete (YYYY-MM-DD)"` — only after criteria and handoff validation pass, so a resumed run never sees a phase claiming completion with gates unmet.
7. (Multi-phase) Merge phase PR into integration branch — runs unconditionally for every phase including the last, regardless of `workflow` setting. The final integrate->main PR is created separately in "After All Phases".
   a. From the phase worktree, open the phase PR: if one is already open (`gh pr list --head phase-<letter> --state open --json url --jq '.[0].url'`), reuse it; otherwise run `pr-create --base integrate/<feature>`.
   b. `REVIEW_WAIT=$(caliper-settings get review_wait_minutes)`
   c. If `$REVIEW_WAIT` == 0: invoke `pr-merge` directly. Else: invoke `pr-review --automated-merge` (which invokes `pr-merge`). No pre-merge `gh pr checks` poll — `pr-merge` enables auto-merge so GitHub gates on CI, then waits (up to `merge_wait_minutes`) for the `MERGED` flip before returning. Then confirm `gh pr view <phase PR> --json state -q .state` prints `MERGED`; if not (the wait timed out), stop the loop and resume once GitHub merges it — step d's `--ff-only` would succeed as a no-op and branch the next phase without this one
   d. Return to the integration worktree (the orchestrate lead's primary CWD established at Setup) and fast-forward local integrate to the merged tip: `cd "$MAIN_ROOT/.claude/worktrees/<feature>" && git pull --ff-only origin integrate/<feature>` — absolute, since a relative `cd` fails from inside the nested phase worktree. `--ff-only` surfaces divergent commits instead of letting a hard reset silently destroy them. If it fails, stop the loop and surface to the user with the worktree path.
   e. Remove the phase worktree if it still exists (pr-merge usually has; on resumption it may be gone). Locate it by branch (a resumed older plan may use the sibling layout): `git worktree list --porcelain | awk '/^worktree /{w=substr($0,10)} $0=="branch refs/heads/phase-<letter>"{print w}'`, then `clear-worktree-scratch` the printed path (syncs agent memory, a backstop for the `SubagentStop` hook, and deletes caliper's untracked scratch so it can't block the remove) and `git worktree remove` it. No output means it's gone. No `--force`; a failed clear (memory may be unsynced) or remove (uncommitted content) stops the loop with the path surfaced.
   f. Continuity: only Rule 4 deviations stop the loop. Review feedback is auto-fixed by `pr-review --automated-merge`.

## Review Loop Protocol (Two-Pass Cap)

The review loop is capped at two dispatches. Pass 1 is discovery. The lead fixes all findings and verifies each fix inline (grep/read). A delta pass 2 is dispatched only if pass 1 found critical or high issues; after pass 2, any remaining findings are fixed inline and the loop records pass — never a third dispatch. Residual leakage is caught by the next downstream gate (the final cross-phase review, then PR review), not by additional same-gate passes.

For each dispatch:

1. Extract the last `json review-summary` fenced block from the response. Missing/malformed on pass 1 -> re-dispatch once (that consumes the pass-2 slot); missing on pass 2 -> escalate via AskUserQuestion.
2. Triage issues: "fix" or "dismiss" (with reasoning). **Issues with `non_dismissible: true` must take the 'fix' branch** — dismissing them invalidates the review record. (gh issue #243: a dismissed boundary-test finding let 22+ commits of contract drift leak through the seam.)
3. Fix all actionable findings and verify each inline (grep/read).
4. If this was pass 1 AND pass 1 surfaced any critical or high issue -> dispatch delta pass 2 over the same scope. Otherwise -> write the reviews.json pass record and advance.
5. After pass 2 -> fix any remaining findings inline, write the reviews.json pass record, advance. No third dispatch.

Append record to `{PLAN_DIR}/reviews.json`:
`{"type":"impl-review","scope":"{SCOPE}","pass":N,"issues_found":N,"severity":{...},"actionable":N,"dismissed":N,"dismissals":[...],"fixed":N,"remaining":0,"verdict":"pass","timestamp":"ISO8601"}`

## Single-Phase Plans

Skip integration branch and phase worktrees. Work directly in the feature worktree:

1. If phase A's status already starts with "Complete", a stopped run got past review — skip to step 3. Otherwise run Prepare Phase steps 2–6, then dispatch tasks, process completions, wrap up (same dispatch protocol as above)
2. Dispatch implementation-review with `PHASE_BASE_SHA..HEAD`, run Review Loop Protocol (scope: `phase-a`)
3. `validate-plan --check-review "$PLAN_JSON" --type impl-review --scope phase-a`
4. Run plan criteria: `validate-plan --criteria "$PLAN_JSON" --plan`
5. `validate-plan --update-status "$PLAN_JSON" --plan --status done`
6. Route on workflow:
   - `"orchestrate"`: `validate-plan --check-workflow "$PLAN_JSON"`, report worktree path, stop
   - `"pr-create"`: invoke pr-create (targets main), `validate-plan --check-workflow "$PLAN_JSON"`, stop
   - `"pr-merge"`: invoke pr-create, read `REVIEW_WAIT=$(caliper-settings get review_wait_minutes)`, invoke pr-review --automated-merge (skip if $REVIEW_WAIT is 0; if skipped, invoke pr-merge directly), `validate-plan --check-workflow "$PLAN_JSON"`

## After All Phases (Multi-Phase Only)

1. Run plan criteria: `validate-plan --criteria "$PLAN_JSON" --plan`. If exit 1, do not mark complete.
2. Final review: dispatch implementation-review with `PLAN_BASE_SHA..HEAD`, run Review Loop Protocol (scope: `final`)
3. `validate-plan --check-review "$PLAN_JSON" --type impl-review --scope final`
4. `validate-plan --update-status "$PLAN_JSON" --plan --status done`
5. Route on workflow:
   - `"orchestrate"`: `validate-plan --check-workflow "$PLAN_JSON"`, report worktree path, stop
   - `"pr-merge"`: create final PR, pr-review --automated-merge (no pre-merge check poll — pr-merge auto-merges and waits for `MERGED`), `validate-plan --check-workflow "$PLAN_JSON"`, clean up
   - `"pr-create"`: create final PR, `validate-plan --check-workflow "$PLAN_JSON"`, stop

**Continuity:** Run continuously. Pause only for Rule 4 violations.

## Key Constraints

| Constraint | Why |
|------------|-----|
| Resolve `PLAN_JSON` as absolute path at setup | Phase worktrees don't have the gitignored plan artifacts; one absolute path means every agent reads the same file |
| Validate schema before execution | Catches file-set overlap and structural issues early |
| Record plan and phase bases with `--set-base --if-unset` | Review ranges start where the plan/phase did, even after a resume |
| Use validate-plan for all status updates | Keeps plan.json and plan.md in sync |
| All tasks complete before advancing phase | Phase completion gate prevents unresolved work |
| Run gate checks at startup and after status changes | Entry gates prevent wasted work, base-branch checks prevent wrong-worktree dispatch, consistency checks catch state drift |

## Integration

**Workflow:** design → draft-plan → **this skill** → pr-create → pr-review → pr-merge
**See:** `skills/implement/tdd.md`
