# usage-guard

Work a task autonomously and continuously, checking 5-hour usage-window
consumption at each checkpoint, and stop cleanly at a threshold (default 99%)
instead of getting rate-limited mid-action.

```
/usage-guard [--queue] [--at <pct>] <task>
```

- **Default:** at the threshold, stop and report what's done + what's still open.
- **`--queue`:** at the threshold, queue the remaining work to auto-resume in the
  next 5-hour block. The continuation re-invokes `/usage-guard --queue`, so a task
  bigger than one block chains block-to-block until the open list is empty.
- **`--at <pct>`:** override the threshold.

## Requirement

Reads usage from the **`queue` skill's** state file (`~/.claude/queue/state.json`),
kept fresh by its statusline wrapper. Set that up first — see `../queue/README.md`.
`scripts/check-usage.sh` reads the file and exits `0` (under) / `10` (at/over) /
`1|2` (no data). Honors `QUEUE_STATE_FILE`. macOS/BSD only.

## How the stop works (honest limits)

- **Checkpoint-granular, not a hard interrupt** — the model checks between work
  chunks, so it stops at the first check at/after the threshold; actual usage may
  be a hair above it. That's what the 1% headroom (default 99) is for, and why the
  loop bounds chunk size near the ceiling.
- **`--queue` chains use `durable: true`** so they survive a restart, but still
  only fire while some Claude session is running and idle — not a headless runner.
- A resumed block starts **cold**; the chain is only as good as the continuation
  payload (the skill requires a fixed set of fields in it).

## Files

- `SKILL.md` — model-facing instructions (work loop, threshold branches, `--queue` chaining).
- `scripts/check-usage.sh` — reads usage state, float-safe threshold compare, staleness signal.

Tests: `tests/usage-guard/caliper-test_check_usage.sh`.
