---
name: queue
description: Queue commands to fire automatically at a future time — by default right after the current Claude 5-hour usage window resets (so the work runs on the fresh quota in this same session), or at a time the user names. Use when the user runs `/queue <commands>`, `/queue <when> <commands>`, says "queue this for the next window", "run this after my limit resets", "defer this to the next 5-hour block", "run this in 2 hours", "do this at 3pm", or "10am tomorrow run X".
---

# /queue — schedule commands to fire in this session at a future time

The user wants a set of commands to run later, **in this same session**, via a
one-shot `CronCreate` job. The default trigger is the moment their current
5-hour usage window resets (so the work lands on fresh quota); they can instead
name an explicit time or duration.

`/queue [<when>] <commands>` — `<when>` is optional; everything else is the
QUEUED PAYLOAD.

> **Requires the statusline tap** for reset-mode (the default): the wrapper
> `./skills/queue/scripts/statusline-wrapper.sh` must be wired in as your
> `statusLine` command so it can capture the 5-hour reset time to the state
> file — see this skill's `README.md`. Without it, reset-mode has no data, but
> explicit `<when>` targets still work. (macOS/BSD `date` only.)

## Resolve the fire time

Inspect the start of the invocation for an optional `<when>`. **Times are local —
cron fires in the machine's local timezone, so no conversion is needed; let
`date` resolve it (if the user names a different zone, convert to local).**

- **No time given** → 5h-window-reset mode. Run the helper with no args:
  ```
  ./skills/queue/scripts/compute-fire.sh
  ```
  (Invoke it directly — it's executable. Do NOT prefix with `bash`.)

- **A duration** ("in 2h", "in 90m", "2h30m") or **clock time** ("3pm", "15:00",
  "3:30pm") or **natural language** ("10am tomorrow", "tomorrow at 9",
  "friday 5pm") → resolve it yourself to an absolute Unix epoch, then:
  1. Get current epoch + wall clock from the machine: `date '+%s | %Y-%m-%d %H:%M:%S %Z'`.
     **Let `date` own the timezone** — compute the epoch for the intended
     wall-clock in the machine's local zone (don't hand-apply a Central offset).
  2. Compute the target epoch. A bare clock time means the next occurrence —
     today if still future, else tomorrow.
  3. **Always confirm before scheduling:** run `date -r <epoch>` and check the
     printed wall-clock matches what the user meant. Don't skip this.
  4. Run: `./skills/queue/scripts/compute-fire.sh --epoch <epoch>`

  Cron is **minute-granular** — sub-minute durations ("in 30s") can't be honored
  exactly; the helper bumps them to the next whole minute. The helper floors to
  the minute and honors explicit times; if the named time lands on `:00`/`:30`,
  mention it may fire up to ~90s early (CronCreate one-shot jitter) and offer to
  nudge a minute.

The helper prints `CRON=`, `FIRE_HUMAN=`, `MINUTES_AWAY=`, and either
`RESET_HUMAN=` (reset mode) or `TARGET_HUMAN=` (explicit). In reset mode it also
prints `STALE=yes|no`. On non-zero exit, relay the stderr message and do not
schedule — exit 1/2 = no reset time captured (keep terminal focused ~10-15s and
retry); 3 = target in the past; 4 = bad `--epoch`. If a `WARNING:` is printed
(stale state, or a DST-gap fire time), surface it: for `STALE=yes`, refresh the
statusline (focus terminal ~10s, re-run) before trusting the reset time.

## Schedule the one-shot

With the helper's output, call `CronCreate`:
- `cron`: the `CRON` value, verbatim.
- `recurring`: `false`
- `durable`: `false` — session-only, matches keep-this-session-open. Only `true`
  if the user explicitly wants it to survive a restart.
- `prompt`: re-state the payload and instruct execution now. Template:
  > Your queued task is due. Execute the following queued work now, in order. If
  > a step is a slash command, run it; otherwise treat it as an instruction.
  >
  > <QUEUED PAYLOAD>

If the user passed no commands, ask what to queue — don't schedule an empty job.

## Report back

State: fire time (`FIRE_HUMAN`), the basis (`RESET_HUMAN`/`TARGET_HUMAN`),
minutes away, the returned **job ID**, and the two caveats:
- **Session-only** — keep this session/terminal open or the job dies with it.
- **Fires only while the REPL is idle** — if you're mid-task at fire time, it
  queues until the turn finishes.

In reset mode, the fire time is keyed to the *last observed* window reset; if the
real reset drifts slightly, the +90s/round-up cushion absorbs it.

## Managing queued jobs

- `CronList` — show what's scheduled this session.
- `CronDelete <id>` — cancel a queued job.
- Each `/queue` adds another one-shot; they don't replace each other.
