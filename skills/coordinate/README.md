# coordinate

One coordinator session works a queue of issues through parallel `/handoff` panes, one PR per item. It does the following:
- triages scope with you;
- starts panes as dependencies merge and the usage window allows;
- re-checks every PR against the merge bar itself (`caliper-pr-at-bar`);
- merges in the configured mode;
- tells open panes when the base moves;
- closes finished panes by id;
- keeps a durable ledger (`caliper-coordinate`).

It ships only in the full `claude-caliper` bundle, because its panes run the workflow skills: implement, then implementation-review, pr-create and pr-review.

## Requirements

- **macOS + iTerm2.** Panes come from `handoff`, so its requirements and one-time Automation grant apply. See [handoff/README](../handoff/README.md).
- **Usage gating (optional).** The coordinator stops starting panes at 90% of the 5-hour window, and checkpoints them and queues its own resume at 99%. Both read usage through the queue skill's statusline tap, which you wire into `statusLine` yourself; see [queue/README](../queue/README.md). Without it, `coordinate` runs ungated and tells you so.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `coordinate_max_panes` | `10` | Most panes open at once |
| `coordinate_merge` | `pr-ready` | `pr-ready`: the coordinator merges an at-bar PR only after you say so. `auto-merge`: it merges unless a hold applies (sensitive paths touched, or the pane reported a deviation or an unverified claim). |

Set them globally with `/caliper-settings`. A repo can override them, and declare its own facts, in `CLAUDE.md` or `CLAUDE.local.md`:
- sensitive paths that hold an auto-merge;
- "no CI" (the bar then accepts zero checks);
- a post-rebase step such as a version bump;
- shared-resource rules.

Panes load the same files, so gates are never copied into briefs.

## The bar

`caliper-pr-at-bar <pr>` exits 0 only when all of these hold:
- the PR is open;
- checks are green;
- the newest `Reviewed-Head: <sha> · blocking: 0` line names the head (pr-review writes this line at the end of its summary). Only lines from the gh user running the check, or from the repo's owners, members and collaborators, count, so an outside commenter can't supply the verdict;
- every review thread is resolved or answered;
- the PR is mergeable;
- it is 0 commits behind base.

## Files

- `SKILL.md`: the coordinator's instructions.
- `brief-template.md`: the pane brief (its standing rules and report schema).
- `bin/caliper-coordinate`: the ledger CLI. `bin/caliper-pr-at-bar`: the bar check.
- `skills/handoff/scripts/spawn-pane.sh` and `close-pane.sh`: open a pane, and close it by `SESSION_ID`.
