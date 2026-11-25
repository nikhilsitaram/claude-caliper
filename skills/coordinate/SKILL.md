---
name: coordinate
description: Use when the user wants a queue of issues worked in parallel handoff panes, one PR each, with you as coordinator — "/coordinate", "run these issues in parallel panes", "coordinate issues X, Y and Z", "be the coordinator", "start a release train".
---

# Coordinate

You are the coordinator. Each queued item gets its own `/handoff` pane and its own PR. You triage scope, start panes as dependencies and usage allow, re-check every PR against the merge bar yourself, merge in the configured mode, tell open panes when the base moves, close finished panes and keep the ledger. Panes build; you never edit code here. This needs macOS and iTerm2, the same as `handoff`.

`/coordinate [--focused] [--resume] [issues...]`

## Setup

1. **Read the ledger first:** `caliper-coordinate status`. The ledger lives in `<main checkout>/.claude/claude-caliper/coordinate.json`, and only that CLI writes it. After compaction, a new session or `--resume`, rebuild your picture from it, not from memory. It also records PRs GitHub reports merged that the ledger missed, printing `MERGED-ON-GITHUB <slug>`; run steps 2-5 of "After a merge" for those. Any other unheld item in `merged` means a run stopped partway through those steps, so resume it at step 2 too. A merged item holds a pane slot until it's done.
2. **Settings:** `caliper-settings get coordinate_max_panes` and `caliper-settings get coordinate_merge`, plus `merge_strategy`. The repo's CLAUDE.md or CLAUDE.local.md can override them. Repo facts live there too, so read them:
   - sensitive paths (they hold an auto-merge);
   - no CI (pass `--allow-no-checks` to `caliper-pr-at-bar`);
   - a post-rebase step, such as a version bump;
   - shared-resource rules.

   Precedence: the user this run beats the repo, which beats global settings. Gates are never copied into briefs: each pane loads the repo's CLAUDE.md itself, so a gate can't be dropped by being retyped.
3. **`--focused`:** panes skip unrelated fixes (see the brief template).

## Triage

For each new issue, read it and the code it touches. Then show a table of item, recommendation and why, using pr-review's disposition words: do, split into a new issue, deferred, out of scope, not-a-bug, or `#<issue>` (already covered). Challenge the scope as `design` would; items needing real design discussion go to `/conversate` first.

Once the user approves, post the dispositions comment on the issue, create any split issues and close won't-do items. These are visible to others, so they need that approval. Then queue each item: `caliper-coordinate add <slug> --issue N [--after <slug>,pr:<n>] [--soft-after <slug>]`. Record every dependency; one held only in your head is lost at compaction. Offer hard or soft for each:
- **Hard** (`--after`, don't start until merged): B edits A's files or needs A's real shape.
- **Soft**: their files and concepts differ, and A's interface is predictable from its brief. B starts once A has started, builds against what it anticipates from A, and rebases once A merges.

## Spawn loop

Run this at start, after every merge, and after every pane report or resume:

1. Candidates come from `caliper-coordinate ready`. Free slots are `coordinate_max_panes` minus `caliper-coordinate active`.
2. Before each spawn, run `./skills/usage-guard/scripts/check-usage.sh 90`:
   - **0:** spawn.
   - **10:** stop starting panes. Running panes carry on.
   - **2:** a transient read failure, common right after a window reset (when `--resume` fires). Re-run once after about 5s.
   - **1, or 2 twice:** usage can't be read (the statusline tap may not be wired; see the queue README). Tell the user once that usage gating is off, then carry on ungated.

   `STALE=yes` means the reading lags while panes keep using the window, so treat it as a floor.
3. Spawn the pane with `./skills/handoff/scripts/spawn-pane.sh <slug> <main checkout>`. Add `--perm-mode <mode>` with your own permission mode (e.g. `auto`, `acceptEdits`) when it isn't the default, so an auto-mode run doesn't stall on a pane's prompts. Then record it: `caliper-coordinate set <slug> --status running --pane-name <NAME> --session-id <SESSION_ID>`. On `LAUNCHED=timeout` or a failure, close any half-started pane by its `SESSION_ID`, leave the item queued, and report.
4. Write the brief. Follow `handoff`'s permission-laundering check, then send one `SendMessage` built from the template. Both ends of a soft dependency still unmerged get a `Soft link` line and the SOFT LINK block. If the other end is already running, send it its line (with this pane's name), plus the block if its brief lacked one.

**See:** brief-template.md

## When a pane messages you

Re-read live state (the ledger and the PR) before acting on any message; a report and your instruction can cross in flight.

- **An at-bar report.** Record it with `caliper-coordinate set <slug> --pr N --head <sha>`. Then run `caliper-pr-at-bar N` yourself; never relay or merge on the pane's word, since a new push or bot comment may have landed since.
  - Exit 1: send the failing criteria back to the pane.
  - Exit 64: GitHub couldn't be read. Re-run; it isn't news for the pane.
  - Exit 0: run `set --status at-bar`, send its soft dependents (by `soft_after` in `caliper-coordinate list`) the PR number as early warning, then go to Merge.
  - If the JSON has a `hint` (no checks registered on the head), the push event was probably dropped. Tell the pane to push the empty commit it suggests.
- **A design question about an unrelated fix:** if the answer is clear, decide and reply, to that pane or one better placed. Otherwise ask the user without blocking the pane, and if it's still open when that PR reaches the bar, tell the pane to file an issue.
- **`WAITING <slug> on <a>`:** a soft dependent is built and parked before pr-create; it holds its assumptions list. Nothing to do until `<a>` merges; if its `soft_after` items have all merged already, send S4's message now. A copied peer note about an interface change needs you only if it changes scope.
- **Stuck** (pr-review's loop gave up short of the bar): look at the reason and the JSON, then decide or escalate to the user.
- **`MERGED+CLEANED`:** the user merged from the pane and pr-merge cleaned up. Do steps 1, 3, 4 and 5 of "After a merge" below, skipping the "merged" message.
- **`CLEANUP-FAILED`:** the pane's worktree holds content pr-merge wouldn't delete. Run `set <slug> --hold "cleanup failed: <path>"`, so a resume doesn't retry it, and report the path to the user. Leave the pane open; once they've resolved it, `--unhold`, close it and set it done.
- **Checks with total 0:** if the repo really has no CI, tell the pane to pass `--allow-no-checks`, and add that line to the repo's CLAUDE.md if it's missing. Otherwise treat it as a dropped push event (see `hint`).

## Merge

Merge only right after `caliper-pr-at-bar` exits 0 in this turn, and only if the ledger item isn't held and `status` shows no `(soft)` dependency for it, in either mode. Pin the merge to that JSON's `.head`. If it differs from the ledger's head, re-record it with `set --head`. With several at the bar, merge first what unblocks queued or waiting items (hard or soft), then narrow before broad.

- **`confirm` (default):** report "#N at bar" with the pane's report summarized, then wait for the user to say merge. If the user merges from a pane, the pane reports it, and `caliper-coordinate status` confirms it.
- **`auto-merge`:** first check for holds. Hold when:
  - `gh pr diff N --name-only` touches a sensitive path the repo names;
  - a reported deviation changes the approved scope;
  - an unverified claim is material to correctness and you can't verify it yourself (read the code, run the test or command; no edits). Name what you tried in the hold reason.

  Judge minor deviations and claims yourself, and list them in the merge report. For each hold, run `caliper-coordinate set <slug> --hold "<reason>"`, report it, and wait for the user. Otherwise merge.

In both modes, name the bar JSON's waived checks, `broken_names` and `cancelled_bot_names`, since nothing vouched for them. In auto-merge they don't hold the merge; list them in the merge report.

A hold, whether from auto-merge or one `status` adds (a closed PR, or a dropped or closed dependency), stays until the cause is fixed or the user says to proceed. Then clear it with `caliper-coordinate set <slug> --unhold`; for a dropped dependency, first remove it with `set --after` or `--soft-after`, or `status` re-holds. Tell a running soft dependent its dependency was dropped, and re-scope it with the user.

Merge command: `gh pr merge N --<merge_strategy> --match-head-commit <head>`. Pinning the head means a push that lands after your check makes the merge fail safely. Don't pass `--delete-branch`: the branch is checked out in the pane's worktree, and the pane deletes it (local and remote) in its pr-merge cleanup.

**After a merge:**
1. Run `caliper-coordinate set <slug> --status merged`.
2. Tell that pane "merged". It runs pr-merge's cleanup and replies `CLEANED`, or `CLEANUP-FAILED` (see above: skip step 3 for that item, but still do steps 4 and 5, since the base has moved either way).
3. Run `./skills/handoff/scripts/close-pane.sh <session_id>`. On exit 0 or 3 (already closed), `set --status done`. On any other exit, report it, and once the user confirms the pane is closed, `set --status done`.
4. Send each running soft dependent of the merged item (by `soft_after` in `list`; the table drops it once merged) "<slug> merged at <sha>": rule S4 of its brief. Tell every pane with an open PR "base moved" with `<sha>` and the version just merged: concurrent PRs claim the same next version, and a rebase can silently drop a duplicate bump.
5. Re-run the spawn loop.

## At the usage limit

At each event, also run `check-usage.sh 99`. On exit 10:
1. Tell each running pane to commit work in progress, report its state, and stop until told to continue.
2. Queue your own resume the way usage-guard's `--queue` does: run `./skills/queue/scripts/compute-fire.sh`, then `CronCreate` with that `CRON`, `recurring: false`, `durable: true`, and a prompt to `cd <main checkout>` and run `/coordinate --resume`. The ledger carries the run; the prompt needs only the directory and any pending user decision.
3. Report.

On resume, first check that you are the coordinator, since a durable job fires in whatever session is open. If your iTerm2 id (`$ITERM_SESSION_ID` after the colon) is an item's `pane.session_id`, you are a pane: don't act on the prompt, but forward it with `SendMessage` to the coordinator named in your brief, or tell the user if that session isn't listed. Otherwise, read `caliper-coordinate status`. If you aren't the session that sent the briefs, tell every open pane "coordinator moved: reply to <your session name>". Tell each running pane to continue, re-send S4's message to any whose `soft_after` items have all merged (repeats are harmless), then run the spawn loop.

## Status

When asked, or after each merge, show the `caliper-coordinate status` table with a summary: merged this run, at bar, running, queued (with what each waits on), and held (with reasons).

## Integration

**Uses:** handoff (panes), usage-guard and queue (the window), pr-review (bot comments addressed), conversate (scoping heavier items). **Panes run:** implement → `pr-ready`.
