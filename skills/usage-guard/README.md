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
`scripts/check-usage.sh [--window 5h|7d] [threshold]` reads the file and exits
`0` (under) / `10` (at/over) / `1|2` (no data) / `64` (bad flag). `--window 7d`
guards the weekly cap instead of the 5-hour block. Honors `QUEUE_STATE_FILE`.
macOS/BSD only.

## How the stop works (honest limits)

- **Checkpoint-granular, not a hard interrupt** — the model checks between work
  chunks, so it stops at the first check at/after the threshold; actual usage may
  be a hair above it. That's what the 1% headroom (default 99) is for, and why the
  loop bounds chunk size near the ceiling.
- **`--queue` chains use `durable: true`** so they survive a restart, but still
  only fire while some Claude session is running and idle — not a headless runner.
- A resumed block starts **cold**; the chain is only as good as the continuation
  payload (the skill requires a fixed set of fields in it).

## Rate-limit backstop (opt-in breadcrumb)

The point of usage-guard is to **stop** before the limit; this is a light safety
net, not a second scheduler. The proactive stop is checkpoint-granular, so one
oversized action can trip a real rate limit before the next check. Claude Code
fires a `StopFailure` hook (matcher `rate_limit`) when a turn ends that way.
`scripts/stopfailure-resume.sh` is a single opt-in hook that — **only while a
`--queue` run is active** (the skill keeps an `active-guard.json` marker live via
`guard-marker.sh`) — copies that marker to `pending-resume.json` as a breadcrumb.
It does **not** auto-resume: the next `/usage-guard` run checks for the breadcrumb
and offers to pick the work back up. Outside an active run it no-ops.

A plugin can't edit your `settings.json`, so this is opt-in — wire the one hook
yourself (copy the script to a stable path, as with the queue statusline tap):

```jsonc
// ~/.claude/settings.json
"hooks": {
  "StopFailure": [
    { "matcher": "rate_limit",
      "hooks": [{ "type": "command", "command": "bash ~/.claude/queue/stopfailure-resume.sh" }] }
  ]
}
```

Caveats: it only records during an active `--queue` run and stays silent
otherwise; resume is **manual** (picked up on the next `/usage-guard` run), not
automatic; the `StopFailure` payload carries no quota data, so the breadcrumb is
just the marker (original task + env) plus when the limit hit.

## Files

- `SKILL.md` — model-facing instructions (work loop, threshold branches, `--queue` chaining, backstop marker).
- `scripts/check-usage.sh` — reads usage state, float-safe threshold compare, staleness signal.
- `scripts/guard-marker.sh` — set/clear the active-`--queue`-run marker the backstop keys on.
- `scripts/stopfailure-resume.sh` — opt-in `StopFailure`/`rate_limit` hook; records an interrupted-run breadcrumb.

Tests: `tests/usage-guard/caliper-test_check_usage.sh`, `tests/usage-guard/caliper-test_stopfailure.sh`.
