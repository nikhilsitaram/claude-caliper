# queue

Schedule commands to fire later **in the same Claude Code session**, via a
one-shot `CronCreate` job. By default it fires ~90 seconds after the current
5-hour usage window resets (so deferred work lands on fresh quota); you can also
give an explicit time/duration (`/queue in 2h …`, `/queue 3pm …`,
`/queue 10am tomorrow …`).

Pairs with the `usage-guard` skill, which reads the same usage state.

## Requirement: the statusline tap

The 5-hour window reset time (`rate_limits.five_hour.resets_at`) and percent used
are exposed by Claude Code **only** in the JSON piped to your `statusLine`
command's stdin — not in any file or CLI. So reset-mode depends on a thin
statusline wrapper that captures those fields to a state file on the way through
to your real statusline renderer.

`scripts/statusline-wrapper.sh` does exactly that: it reads stdin once and writes
`{resets_at, used_percentage, captured_at}` to the state file. It then renders the
statusline itself — a compact `dir (branch) · model · 5h NN% (resets HH:MM)`
line — so **no external statusline tool is required**. If you already use a
statusline renderer (ccstatusline or anything else), set `QUEUE_STATUSLINE` and
the wrapper forwards the same stdin to it instead of rendering its own line.

### Wiring it in

Point your `statusLine` command at the wrapper. Because plugin cache paths change
on update, the robust setup is to copy the wrapper to a stable location and point
`settings.json` there:

```bash
mkdir -p ~/.claude/queue
cp "<plugin>/skills/queue/scripts/statusline-wrapper.sh" ~/.claude/queue/
chmod +x ~/.claude/queue/statusline-wrapper.sh
```

```jsonc
// ~/.claude/settings.json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/queue/statusline-wrapper.sh",
  "padding": 0,
  "refreshInterval": 10
}
```

With nothing else configured the wrapper renders its own line. Already running a
custom statusline? Set `QUEUE_STATUSLINE` to it and the wrapper forwards stdin to
that command instead:

```bash
# any renderer:
QUEUE_STATUSLINE="my-statusline --flags" bash ~/.claude/queue/statusline-wrapper.sh
# ccstatusline specifically:
QUEUE_STATUSLINE="bunx -y ccstatusline@latest" bash ~/.claude/queue/statusline-wrapper.sh
```

Set it via the `statusLine.command`'s `env`, or export it before Claude starts.

Give the terminal ~10–15 s to render once, then confirm:

```bash
cat ~/.claude/queue/state.json   # {"resets_at":…, "used_percentage":…, "captured_at":…}
```

`resets_at`/`used_percentage` only appear for Pro/Max subscribers, after the
first API response of a session.

## Configuration (env)

| Var | Default | Purpose |
|-----|---------|---------|
| `QUEUE_STATE_FILE` | `~/.claude/queue/state.json` | Where state is read/written |
| `QUEUE_STATUSLINE` | _(unset)_ | External statusline command to forward stdin to; unset renders the built-in line |

## Notes & limits

- **macOS/BSD only** — the scripts use `date -r <epoch>` / `date -j -f`.
- **Session-only by default** — `CronCreate` jobs live in memory and die when
  Claude exits (pass `durable: true` to persist). They fire only while the REPL
  is idle.
- The fire time dodges the `:00`/`:30` minute marks in reset mode, because
  `CronCreate` fires one-shots landing there up to 90 s early.
- Cron is **minute-granular**; sub-minute durations bump to the next whole minute.

## Files

- `SKILL.md` — model-facing instructions.
- `scripts/compute-fire.sh` — resolves reset time (or an explicit epoch) into a one-shot cron expression.
- `scripts/statusline-wrapper.sh` — the statusline tap.

Tests: `tests/queue/caliper-test_compute_fire.sh` (compute-fire unit tests) and
`tests/queue/caliper-test_statusline_seam.sh` (end-to-end: wrapper → state file →
both consumers).
