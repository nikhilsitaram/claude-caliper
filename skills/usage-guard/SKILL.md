---
name: usage-guard
description: Work a task autonomously and continuously, checking usage-window consumption (the 5-hour block by default, or the 7-day/weekly cap with `--window 7d`) at each checkpoint, and stop when usage hits a threshold (default 99%) instead of getting rate-limited mid-action. Use when the user runs `/usage-guard <task>`, `/usage-guard --queue <task>`, `/usage-guard --window 7d <task>`, says "keep going until I'm almost out of usage", "grind on this until the 5-hour limit", "use up my block on this", "stop when I'm near my weekly/7-day limit", or "work until 99% then stop / then queue the rest".
---

# /usage-guard — work until the 5-hour usage window is nearly spent

Run a task as a continuous autonomous work session, self-checking how much of
the current 5-hour usage window has been consumed, and stop cleanly at a
threshold (default **99%**) — leaving 1% headroom so the stop/report (or queue)
actions don't trip a real rate limit mid-action.

`/usage-guard [--queue] [--at <pct>] <task>`

## Parse the invocation

- `--queue` — at the threshold, don't just stop: queue the remaining work to
  auto-resume in the next 5-hour block (see "At the threshold" below).
- `--at <pct>` — override the threshold (e.g. `--at 95`). Default 99.
- Everything else is the **TASK**. If no task is given, treat the current
  in-progress work / the conversation's active objective as the task; if that's
  unclear, ask what to grind on before starting.

## How usage is read

`./skills/usage-guard/scripts/check-usage.sh [--window 5h|7d] [threshold]`
(invoke directly — executable, no `bash` prefix) reads `~/.claude/queue/state.json`,
kept fresh by the queue skill's statusline wrapper. It prints `WINDOW=`, `USED_PCT=`,
`VERDICT=` (UNDER/OVER), `CAPTURED_AGE_SEC=`, `STALE=` (yes/no), `RESETS_AT_HUMAN=`,
`RESETS_IN_MIN=` and exits **0 = under**, **10 = at/over**, **1/2 = data unavailable**.

- `--window` selects the rolling window (default `5h`). Pass `--window 7d` to guard
  the **weekly** cap instead — e.g. "stop when I'm near my 7-day limit". The work
  loop is otherwise identical; just thread the same `--window` value through every
  check this run so cadence and the threshold branch track one window.
- This depends on the **queue skill's statusline wrapper** being wired in. If
  check-usage exits 1/2, relay its stderr and stop — usage can't be read. One
  exception: exit 2 with a *past `resets_at`* stderr is a transient cross-session
  glitch (a stale blob from another session, overwritten within ~10s). Re-run once
  after ~5s before stopping; only stop if it repeats.
- `STALE=yes` (the same >90s cutoff `compute-fire.sh` uses) means the statusline
  hasn't rendered recently — terminal idle/unfocused — so `USED_PCT` lags reality.
  Note it; the number may be behind.

## The work loop

1. **Set up a ledger.** Use the task list (TaskCreate/TaskUpdate) to break the
   TASK into trackable sub-tasks and keep it current. This ledger IS your
   "what's done / what's still open" for the stop report and the queue payload.
   In `--queue` mode, also write the rate-limit backstop marker once now (see
   "Rate-limit backstop"), and — at the very start of any run — check for a
   leftover breadcrumb from a previously interrupted run.
2. **Do a chunk** of the work (a sub-task, or a small batch of steps).
3. **Update the ledger** (mark finished items done) — do this *before* the usage
   check so the check/branch always sees a current ledger.
4. **Check usage** by running check-usage.sh:
   - Exit 0 (UNDER) → continue to the next chunk.
   - Exit 10 (OVER) → go to "At the threshold".
   - Exit 1/2 → relay and stop.
5. **Cadence AND chunk size** — the overshoot guard. Checking often isn't enough
   if a single chunk between checks can itself burn several percent:
   - Check after each sub-task while usage is low; past ~90% `USED_PCT`, check
     after *every* step.
   - Past ~90%, also keep chunks **small** — do NOT start a single long-running
     action (big build, wide subagent fan-out, large batch) that could plausibly
     consume more than the remaining headroom. If the next step might, check/stop
     *before* it, not after.
   - If `STALE=yes` near the ceiling, the reading lags reality — treat
     `USED_PCT` as a floor and stop early rather than trusting a sub-threshold
     number.
6. **If the task completes before the threshold** → stop and report it done; do
   NOT queue, and clear the backstop marker. (A finished task ends the chain.)

Work continuously without pausing to ask between chunks — that's the point of
the guard. Only stop for the threshold, task completion, a hard error, or a
genuine decision that's the user's to make.

## At the threshold (VERDICT=OVER)

First, make the ledger accurate (mark what's done; the open items are what
remains). Then:

**Default (no `--queue`):** stop now and report:
- `USED_PCT` reached and that the window resets at `RESETS_AT_HUMAN`,
- what got done this run,
- what's still open (the remaining ledger items),
- how to resume (a one-line "say continue / re-run with --queue" pointer).

**With `--queue`:** queue the remainder to resume in the next block.

- **First, the termination guard:** if no open ledger items remain, the task is
  effectively done — report it done and do **NOT** queue. Only queue when real
  work remains.

1. Compose a **CONTINUATION PAYLOAD** — a self-contained resume prompt, because
   the resumed session is **cold** (no task list, no file context, no memory of
   this run except this string). It MUST include all of:
   - (i) the **original task statement, verbatim** — so block N hasn't drifted;
   - (ii) **done so far** (the completed ledger items);
   - (iii) **still open** (the remaining ledger items, in order);
   - (iv) **environment** — working directory, git branch/worktree, and key file
     paths / IDs / URLs needed to resume;
   - (v) **decisions & constraints** already settled this run.
2. Get the fire time: `./skills/queue/scripts/compute-fire.sh`
   (reset mode — fires ~90s after the window resets). Relay stderr and stop if
   it errors; if it prints `STALE=yes`, refresh the statusline first.
3. `CronCreate` with: `cron` = its `CRON` value, `recurring: false`,
   **`durable: true`** (a multi-block chain almost always outlives this terminal,
   so persist it — unlike a plain `/queue`, which defaults session-only), and
   `prompt`:
   > Your queued usage-guarded work is due — the 5-hour window has reset. First
   > `cd` to the working directory named below. Then resume by invoking
   > `/usage-guard --queue` on the following remaining work, so it keeps guarding
   > usage and re-queues anything still open at the next threshold:
   >
   > <CONTINUATION PAYLOAD>
4. **Clear the backstop marker** — the work is durably queued now, so the
   StopFailure hook must not double-queue it:
   `./skills/usage-guard/scripts/guard-marker.sh clear`
5. Report: what got done, that the rest is queued for `FIRE_HUMAN` (job ID), and
   the caveats below. Because the continuation re-invokes `/usage-guard --queue`,
   a task bigger than one block chains block-to-block until the open list is
   empty (the termination guard above is what ends it).

(Default-mode stop also clears the marker — there's no queued continuation to
protect.)

## Rate-limit backstop (`--queue`, opt-in hook)

usage-guard's job is to **stop** before the limit; this is just a light safety net
for the overshoot case (one oversized action trips a real rate limit before the
next check). An opt-in `StopFailure` hook (matcher `rate_limit`) records — it does
NOT auto-resume — so an interrupted `--queue` run isn't silently lost.

- **At `--queue` run start**, write the marker once with the original task + the
  environment needed to resume (working dir, branch/worktree, key paths/IDs):
  `printf '%s' "<task + env>" | ./skills/usage-guard/scripts/guard-marker.sh set`
- **Clear it** the moment the run ends — task completion, a clean stop, or right
  after the CronCreate above (steps 4/6): `guard-marker.sh clear`.

If a rate limit hits while the marker is live, the hook copies it to
`~/.claude/queue/pending-resume.json` (a breadcrumb). **At the start of any
`/usage-guard` run, check for that file; if present, fold its task/env into this
run and delete it** so it isn't picked up twice. The hook is opt-in (a plugin
can't edit settings.json) — wiring + caveats in the README.

## Caveats (state these when stopping)

- **Checkpoint-granular, not a hard interrupt** — the stop lands at the first
  check at/after the threshold, so actual usage may be a hair above it. That's
  what the 1% headroom is for.
- **`--queue` chains are `durable: true`** — they persist to disk and survive a
  restart (a 5h+ chain won't keep one terminal open). But a durable job still
  only fires **while some Claude session is running and idle** — if nothing is
  running at reset time it fires late, when you next open Claude. It is not a
  headless/background runner. `CronList` / `CronDelete <id>` to inspect or cancel.
- The continuation resumes **cold** in whatever session fires it — its quality is
  only as good as the CONTINUATION PAYLOAD (hence the required fields above).
