---
name: coordinate
description: Use when the user wants a queue of issues worked in parallel handoff panes, one PR each, with you as coordinator — "/coordinate", "run these issues in parallel panes", "coordinate issues X, Y and Z", "be the coordinator", "start a release train".
---

# Coordinate

You are the coordinator. Each queued item gets its own `/handoff` pane and its own PR. You:
- triage scope;
- start panes as their dependencies merge and usage allows;
- re-check every PR against the merge bar yourself;
- merge in the configured mode;
- tell open panes when the base moves;
- close finished panes and keep the ledger.

Panes build; you never edit code here. This needs macOS and iTerm2, the same as `handoff`.

`/coordinate [--focused] [--resume] [issues...]`

## Setup

1. **Read the ledger first:** `caliper-coordinate status`. The ledger lives in `<main checkout>/.claude/claude-caliper/coordinate.json`, and only that CLI writes it. It is the durable state of the run, so after compaction, a new session or `--resume`, rebuild your picture from it, not from memory. The CLI also records PRs GitHub reports merged that the ledger missed, printing `MERGED-ON-GITHUB <slug>` for each. Run steps 2-5 of "After a merge" for those.
2. **Settings:** `caliper-settings get coordinate_max_panes` and `caliper-settings get coordinate_merge`, plus `merge_strategy`. The repo's CLAUDE.md or CLAUDE.local.md can override them. Repo facts live there too, so read them:
   - sensitive paths (they hold an auto-merge);
   - no CI (pass `--allow-no-checks` to `caliper-pr-at-bar`);
   - a post-rebase step, such as a version bump;
   - shared-resource rules.

   Precedence: what the user says this run beats the repo, and the repo beats global settings. Gates are never copied into briefs. Each pane loads the repo's CLAUDE.md itself, so a gate can't be dropped by being retyped.
3. **`--focused`:** panes skip unrelated fixes (see the brief template).

## Triage

For each new issue, read it and the code it touches. Then show a table: item, recommendation, and why. Recommendations use pr-review's disposition words:
- do;
- split into a new issue;
- deferred;
- out of scope;
- not-a-bug;
- `#<issue>`, already covered.

Challenge the scope as `design` would. Items that need real design discussion go to `/conversate` before they're briefed.

Once the user approves:
- post the dispositions comment on the issue;
- create any split issues;
- close won't-do items.

These actions are visible to others, so they need that approval. Then queue each item to build: `caliper-coordinate add <slug> --issue N [--after <slug>,pr:<n>]`. Record every dependency in `--after`. A dependency held only in your head is lost at compaction.

## Spawn loop

Run this at start, after every merge, and after every pane report or resume:

1. Candidates come from `caliper-coordinate ready`. Free slots are `coordinate_max_panes` minus `caliper-coordinate active`.
2. Before each spawn, run `./skills/usage-guard/scripts/check-usage.sh 90`:
   - **0:** spawn.
   - **10:** stop starting panes. Running panes carry on.
   - **2:** a transient read failure. It's common right after a window reset, which is exactly when `--resume` fires. Re-run once after about 5s before acting on it.
   - **1, or 2 twice:** usage can't be read (the statusline tap may not be wired; see the queue README). Tell the user once that usage gating is off, then carry on ungated.

   `STALE=yes` means the reading lags. You sit idle while the panes use up the window, so treat the number as a floor.
3. Spawn the pane with `./skills/handoff/scripts/spawn-pane.sh <slug> <main checkout>`. Add `--perm-mode <mode>` with your own permission mode (e.g. `auto`, `acceptEdits`) when it isn't the default, so an auto-mode run doesn't stall on a pane's prompts. Then record it: `caliper-coordinate set <slug> --status running --pane-name <NAME> --session-id <SESSION_ID>`. On `LAUNCHED=timeout` or a failure, close any half-started pane by its `SESSION_ID`, leave the item queued, and report.
4. Write the brief. Follow `handoff`'s permission-laundering check, then send one `SendMessage` built from the template.

**See:** brief-template.md

## When a pane messages you

Re-read live state (the ledger and the PR) before acting on any message. A report and one of your instructions can cross in flight, and acting on a stale picture "corrects" the wrong thing.

- **An at-bar report.** Record it with `caliper-coordinate set <slug> --pr N --head <sha>`. Then run `caliper-pr-at-bar N` yourself; never relay or merge on the pane's word, because a "claimed at bar" can carry a verdict for an old head.
  - Exit 1: send the failing criteria back to the pane.
  - Exit 64: GitHub couldn't be read. Re-run; it isn't news for the pane.
  - Exit 0: run `set --status at-bar`, then go to Merge.
  - If the JSON has a `hint` (no checks registered on the head), the push event was probably dropped. Tell the pane to push the empty commit it suggests.
- **A design question about an unrelated fix:**
  - If the recommendation is clear, decide and reply, to that pane or to another pane better placed to do it.
  - If it has major considerations, ask the user, and don't block the pane meanwhile.
  - If it's still open when that pane's PR reaches the bar, tell the pane to file an issue.
- **Stuck** (two review rounds without reaching the bar): look at the JSON, then decide or escalate to the user.
- **`MERGED+CLEANED`:** the user merged from the pane and pr-merge cleaned up. Do steps 1, 3, 4 and 5 of "After a merge" below, skipping the "merged" message.
- **`CLEANUP-FAILED`:** the pane's worktree holds content pr-merge wouldn't delete. Report the path to the user, leave the pane open and the item merged, and close it once they've resolved it.
- **Checks with total 0:** if the repo really has no CI, tell the pane to pass `--allow-no-checks`, and add that line to the repo's CLAUDE.md if it's missing. Otherwise treat it as a dropped push event (see `hint`).

## Merge

Merge only right after `caliper-pr-at-bar` exits 0 in this turn, and pin the merge to that JSON's `.head`. If it differs from the ledger's head, re-record it with `set --head`.

- **`confirm` (default):** report "#N at bar" with the pane's report summarized, then wait for the user to say merge. If the user merges from a pane, the pane reports it, and `caliper-coordinate status` confirms it.
- **`auto-merge`:** first check for holds. Hold when:
  - `gh pr diff N --name-only` touches a sensitive path the repo names;
  - the report lists a deviation or an unverified claim.

  For each hold, run `caliper-coordinate set <slug> --hold "<reason>"`, report it, and wait for the user. Otherwise merge.

A hold, whether from auto-merge or one `status` adds (a closed PR, or a dropped or closed dependency), stays until the cause is fixed or the user says to proceed. Then clear it with `caliper-coordinate set <slug> --unhold`.

Merge command: `gh pr merge N --<merge_strategy> --match-head-commit <head>`. Pinning the head means a push that lands after your check makes the merge fail safely. Don't pass `--delete-branch`: the branch is checked out in the pane's worktree, and the pane deletes it, locally and on the remote, during its pr-merge cleanup.

**After a merge:**
1. Run `caliper-coordinate set <slug> --status merged`.
2. Tell that pane "merged". It runs pr-merge's cleanup and replies `CLEANED` (go on) or `CLEANUP-FAILED` (see above; stop here for that item).
3. Run `./skills/handoff/scripts/close-pane.sh <session_id>`. On exit 0 or 3 (already closed), `set --status done`. On any other exit, report it, and once the user confirms the pane is closed, `set --status done`. A merged item holds a pane slot until it's done.
4. Tell every pane with an open PR that the base moved: rebase onto `<sha>`, run the repo's post-rebase steps (for a version bump, expect a version above the one just merged), keep both behaviours, and get a fresh verdict. Concurrent PRs claim the same next version, and a rebase can silently drop a duplicate bump.
5. Re-run the spawn loop.

## At the usage limit

At each event, also run `check-usage.sh 99`. On exit 10:
1. Tell each running pane to commit work in progress, report its state, and stop until told to continue.
2. Queue your own resume the way usage-guard's `--queue` does: run `./skills/queue/scripts/compute-fire.sh`, then `CronCreate` with that `CRON`, `recurring: false`, `durable: true`, and a prompt to `cd <main checkout>` and run `/coordinate --resume`. The ledger carries the run, so the prompt only needs the directory and any decision you're waiting on from the user.
3. Report.

On resume, first check that you are the coordinator. A durable job can fire in whatever session is open. If your own iTerm2 id (the part of `$ITERM_SESSION_ID` after the colon) is an item's `pane.session_id`, you are a pane: ignore the prompt. Otherwise, read `caliper-coordinate status`. If you aren't the session that sent the briefs, tell every open pane "coordinator moved: reply to <your session name>". Tell each running pane to continue, then run the spawn loop.

## Status

When asked, or after each merge, show the `caliper-coordinate status` table with a summary:
- merged this run;
- at bar;
- running;
- queued, with what each is waiting on;
- held, with reasons.

## Integration

**Uses:** handoff (panes), usage-guard and queue (the window), pr-review (the `Reviewed-Head:` verdict), conversate (scoping heavier items). **Panes run:** implement → `pr-ready`.
