# coordinate

One coordinator session works a queue of issues through parallel `/handoff` panes, one PR per item. It does the following:
- triages scope with you;
- starts panes as hard dependencies merge (soft ones once the other has started) and the usage window allows;
- re-checks every PR against the merge bar itself (`caliper-pr-at-bar`);
- merges in the configured mode;
- tells open panes when the base moves;
- closes finished panes by id;
- keeps a durable ledger (`caliper-coordinate`).

Dependencies come in two kinds. `--after` waits for the other item to merge. `--soft-after` starts as soon as the other item has started (so parked dependents never take its slot), building against what it expects the other item's interface to be, and rebases and checks those assumptions once that item merges.

## Requirements

- **macOS + iTerm2.** Panes come from `handoff`, so its requirements and one-time Automation grant apply. See [handoff/README](../handoff/README.md).
- **Usage gating (optional).** The coordinator stops starting panes at 90% of the 5-hour window, and checkpoints them and queues its own resume at 99%. Both read usage through the queue skill's statusline tap, which you wire into `statusLine` yourself; see [queue/README](../queue/README.md). Without it, `coordinate` runs ungated and tells you so.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `coordinate_max_panes` | `10` | Most panes open at once. `0` pauses new spawns while running panes finish. |
| `coordinate_merge` | `confirm` | `confirm`: the coordinator merges an at-bar PR only after you say so. `auto-merge`: it merges unless a hold applies (sensitive paths touched, a deviation that changes the approved scope, or an unverified claim material to correctness that it can't verify itself). |

Set them globally with `/caliper-settings`. A repo can override them, and declare its own facts, in `CLAUDE.md` or `CLAUDE.local.md`:
- sensitive paths that hold an auto-merge;
- "no CI" (the bar then accepts zero checks);
- a post-rebase step such as a version bump;
- a post-merge step such as a GitHub release;
- shared-resource rules.

Panes load the same files, so gates are never copied into briefs.

## The bar

Ready to merge means every bot comment is addressed and CI is green. `caliper-pr-at-bar <pr>` exits 0 only when all of these hold:
- the PR is open;
- CI is green: no check pending (a bot still reviewing counts as pending) and none failed;
- every review thread, bot or human, is resolved or has a reply;
- the PR is mergeable;
- it is 0 commits behind base.

**Safety valve for broken CI.** A check that fails on the PR is waived if its latest run on the base branch's head also failed. That's breakage the PR didn't cause, like a repo whose main is red. Waived checks are listed in `broken_names` and reported every time, because while base is red a regression the PR adds to that same check is masked. A failure the base doesn't share still blocks, including a check that never runs on the base (a `pull_request`-only workflow).

**Cancelled bot checks don't block.** A check from an app outside GitHub Actions that concludes `CANCELLED` (for example CodeRabbit giving up on a review) is listed in `cancelled_bot_names` and reported. A cancelled Actions job still blocks. Third-party CI apps, such as Cloudflare Workers Builds, are also outside Actions, so their cancellations are waived the same way.

## Files

- `SKILL.md`: the coordinator's instructions.
- `brief-template.md`: the pane brief (its standing rules and report schema).
- `bin/caliper-coordinate`: the ledger CLI. `bin/caliper-pr-at-bar`: the bar check.
- `skills/handoff/scripts/spawn-pane.sh` and `close-pane.sh`: open a pane, and close it by `SESSION_ID`.
