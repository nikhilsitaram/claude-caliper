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

## Rate-limit backstop (opt-in)

The proactive stop is checkpoint-granular, so one oversized action can trip a real
rate limit before the next check queues the work. Claude Code fires a `StopFailure`
hook (matcher `rate_limit`) when a turn ends that way. `scripts/stopfailure-resume.sh`
is a defense-in-depth backstop: **only while a `--queue` run is active** (the skill
keeps an `active-guard.json` marker live via `guard-marker.sh`), it records the
remaining work to `pending-resume.json`, keyed off the **last-known `resets_at`**
in the state file (the hook payload carries no quota data). `scripts/pending-resume.sh`
is a `SessionStart` hook that surfaces a due record so the next session resumes
`/usage-guard --queue`. Outside an active run, both no-op.

A plugin can't edit your `settings.json`, so this is opt-in — wire both hooks
yourself (copy the scripts to a stable path, as with the queue statusline tap):

```jsonc
// ~/.claude/settings.json
"hooks": {
  "StopFailure": [
    { "matcher": "rate_limit",
      "hooks": [{ "type": "command", "command": "bash ~/.claude/queue/stopfailure-resume.sh" }] }
  ],
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": "bash ~/.claude/queue/pending-resume.sh" }] }
  ]
}
```

Caveats: macOS/BSD only; the `StopFailure` payload has **no reset time**, so the
backstop relies on a previously-captured `resets_at` (a stale/absent one surfaces
the resume as "due now" on the next session rather than losing it); it only acts
during an active `--queue` run and stays silent otherwise.

## Files

- `SKILL.md` — model-facing instructions (work loop, threshold branches, `--queue` chaining, backstop marker).
- `scripts/check-usage.sh` — reads usage state, float-safe threshold compare, staleness signal.
- `scripts/guard-marker.sh` — set/clear the active-`--queue`-run marker the backstop keys on.
- `scripts/stopfailure-resume.sh` — `StopFailure`/`rate_limit` hook; records a pending resume.
- `scripts/pending-resume.sh` — `SessionStart` hook; surfaces a due pending resume.

Tests: `tests/usage-guard/caliper-test_check_usage.sh`, `tests/usage-guard/caliper-test_stopfailure.sh`.
