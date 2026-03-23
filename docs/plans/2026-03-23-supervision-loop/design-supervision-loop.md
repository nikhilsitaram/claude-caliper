# Design: Two-Level Supervision Loop for Orchestrate

## Problem

Phase dispatchers are 15+ minute black boxes. When they hit issues (permission prompts, repeated errors, wrong code patterns), nobody notices until completion or user intervention. This affects both levels of the hierarchy:

- **L1 (Orchestrator → Phase Dispatchers):** The orchestrator has zero visibility into running phases. It blocks waiting for each phase to return, with no way to detect or intervene when a dispatcher is stuck.
- **L2 (Phase Dispatcher → Task Implementers):** Phase dispatchers dispatch implementers synchronously and block until return. When an implementer gets stuck (e.g., permission prompt loop, repeated error pattern), the dispatcher wastes its entire remaining token budget waiting. The existing post-task review loop catches quality issues but not liveness issues — a stuck implementer never reaches the review stage.

Observed in practice: a phase dispatcher spent significant time debugging a `set -e` + command substitution interaction because the task prose used a broken pattern — the orchestrator had no visibility until the user noticed permission prompts.

Additionally, orchestrate's SKILL.md specifies "Dispatch ready phases IN PARALLEL (one Agent per phase)" but the current prompt templates dispatch synchronously — the orchestrator blocks waiting for each phase dispatcher to return. Supervision requires async dispatch because the supervisor must remain free to poll while workers execute; bundling both concerns is intentional.

## Goal

Add a two-level supervision hierarchy to orchestrate:
- **L1 (Orchestrator → Phase Dispatchers):** Async dispatch of independent phases with 60s polling, progress updates to user, and intervention capability.
- **L2 (Phase Dispatcher → Task Implementers):** Async dispatch of sequential tasks with 30s polling, intervention capability, and escalation to orchestrator when unresolvable.

## Success Criteria

1. Independent phases in the same wave execute concurrently (dispatched with `run_in_background: true`).
2. The user sees a progress update every 60s showing task completion counts and health status per active phase.
3. A stuck task implementer is detected and intervention begins within 2 minutes of the implementer becoming stuck.
4. A stuck phase dispatcher is detected and the user is notified within 3 minutes of the dispatcher becoming stuck.
5. An unresolvable task (2 failed interventions) is escalated via `escalation.json`, surfaced to the user on next orchestrator poll, and the phase continues to the next task.
6. Task implementers within a phase still execute sequentially (one at a time) to avoid git conflicts.

## Architecture

### Tool Availability

The supervision loop relies on these Claude Code built-in tools for background agent management. These are platform-level tools (not codebase artifacts) — verified via `ToolSearch` which returned their full JSON schemas:

- **`Agent(run_in_background: true)`** — dispatches a subagent that runs independently; returns a task ID immediately. The parent agent continues processing. Schema confirms `run_in_background` boolean parameter.
- **`TaskOutput(task_id, block, timeout)`** — reads output from a running or completed background task. `block: false` returns immediately with current status; `block: true` waits for completion. Used with `block: false` each poll cycle to check for error patterns. Schema: `task_id` (required string), `block` (boolean, default true), `timeout` (number, default 30000ms, max 600000ms).
- **`TaskStop(task_id)`** — terminates a running background task. Schema: `task_id` (string). Used as the primary intervention mechanism — stop the stuck agent, then re-dispatch with additional context.

**Not available:** `SendMessage` (referenced in Agent tool documentation but not present as a callable tool via ToolSearch). This means mid-flight guidance injection is not possible — intervention requires stopping and re-dispatching the agent.

The existing orchestrate skill already uses `Agent` (foreground); the change is adding `run_in_background: true` and using the companion tools for supervision. `TaskOutput` returns the agent's cumulative output text; the supervisor parses the last portion for error patterns using string matching.

### Two-Level Hierarchy

```
Orchestrator (L1 supervisor — polls every 60s, user progress updates)
  ├── Phase Dispatcher A (L2 supervisor — polls every 30s)
  │     ├── Task Implementer 1 (worker, background, sequential)
  │     ├── Task Implementer 2 (worker, background, sequential)
  │     └── ...
  └── Phase Dispatcher B (L2 supervisor — polls every 30s)
        ├── Task Implementer 1 (worker, background, sequential)
        └── ...
```

### Escalation Chain

```
Implementer stuck
  → Phase dispatcher: TaskStop + re-dispatch with diagnosis and additional context
  → 2nd attempt: TaskStop + re-dispatch with broader context (prior output summary)
  → After 2 failed re-dispatches: write escalation.json, skip to next task
  → Orchestrator reads escalation.json on next poll → alerts user

Phase dispatcher stuck
  → Orchestrator: TaskStop + re-dispatch with diagnosis
  → 2nd attempt: AskUserQuestion to user (user decides: re-dispatch or abort)
```

### L1: Orchestrator Supervision Loop

The wave loop changes from synchronous dispatch to async dispatch + supervision:

```
for each wave:
  dispatch phase dispatchers (run_in_background: true) → capture agent_ids

  SUPERVISION LOOP (every 60s):
    for each active phase:
      read plan.json from phase worktree → task completion counts
      check escalation.json → surface to user if present
      TaskOutput(phase_agent_id) → health signals
      git log in phase worktree → commit recency

      healthy → log progress
      degraded → TaskStop + re-dispatch with diagnosis
      stuck → escalate to user via AskUserQuestion

    OUTPUT PROGRESS UPDATE to user:
      "[2m] Phase A: 3/5 tasks, healthy | Phase B: 1/4 tasks, healthy"

    PROCESS COMPLETED PHASES (serially, inline):
      A phase is "complete" when TaskOutput(task_id, block: false)
      returns a completed status (the phase dispatcher has returned).
      For each completed phase, run post-phase processing inline
      (review loop → rebase → create-pr → poll → review-pr → merge).
      This blocks the supervision loop for that phase's processing,
      but other active phases continue running in background —
      they are checked on the next poll cycle after processing finishes.
    if all phases complete → break
```

**Completion processing vs. polling:** Post-phase processing (steps 6-18 from current SKILL.md) runs inline within the supervision loop when a phase is detected as complete. This temporarily pauses polling for other active phases, but since post-phase processing (review, PR, merge) takes 5-10 minutes and phases run independently, the delay is acceptable. The alternative (spawning post-phase processing as another background agent) would add complexity without meaningful benefit — active phases don't need sub-minute polling precision.

### L2: Phase Dispatcher Supervision Loop

Tasks remain sequential. The change is that each implementer is dispatched in the background so the phase dispatcher can supervise:

```
for each task in phase (sequential):
  dispatch implementer (run_in_background: true) → agent_id

  SUPERVISION LOOP (every 30s):
    check TaskOutput(agent_id) → error patterns, progress
    git log in worktree → commit recency

    healthy → continue polling
    stuck → intervene (see intervention protocol)
    complete → break

  post-task review (existing per-task reviewer)
  THEN next task
```

### Detection Signals

Each poll cycle checks (cheapest first):

| Signal | How to check | Indicates |
|--------|-------------|-----------|
| Escalation file | `cat escalation.json` | L2 escalated to L1 |
| Commit recency | `git log --oneline -1 --format=%ct` | Forward progress |
| TaskOutput patterns | `TaskOutput(task_id, block: false)` — parse last 50 lines of output text | Error loops, permission blocks |
| Task status | `jq` on plan.json in worktree | Completion count |

**Stuck indicators** (any one triggers intervention):
- TaskOutput shows the same error repeated 3+ times
- TaskOutput shows "permission" / "denied" / "blocked" language
- No new commits since last poll AND no new tool output
- Implementer has returned with an error exit

**Healthy indicators** (all must hold):
- New commits or new tool output since last poll
- No error patterns in recent output

### Detection Logic

TaskOutput returns cumulative text. The supervisor stores the previous output length and reads only the new portion (characters after the stored offset) each cycle.

**Permission blocks:** Match the Claude Code interactive prompt structure, not bare keywords. Look for multiline patterns containing "Do you want to proceed" followed by numbered options (e.g., `1. Yes`, `2. Yes, and don't ask again`). Single keywords like "permission" or "denied" in isolation are not sufficient — they appear in legitimate output (documentation, test names, code comments). The pattern to match is the full permission prompt format.

**Repeated errors:** Extract lines from new output matching error patterns (`error:`, `Error:`, `failed:`, `FAILED`, `Traceback`, `panic:`). Note the trailing colon/capitalization to reduce false positives from grep results or documentation. Require the same error line to appear on 3+ consecutive lines (not just 3 occurrences scattered across the output window) — scattered matches likely indicate a search or test summary, while consecutive identical lines indicate a retry loop.

**No progress:** Compare current `git log --format=%H -1` and TaskOutput length against values stored from the previous cycle. If both are unchanged → no progress. Two consecutive no-progress cycles → stuck.

**Completion:** `TaskOutput(task_id, block: false)` returns status information. If the task status indicates completion → complete.

### Intervention Protocol

Since `SendMessage` is not available, all intervention uses `TaskStop` + re-dispatch. The re-dispatched agent receives the diagnosis and prior output summary as additional context in its prompt, so it can avoid the same failure pattern.

**Phase dispatcher → implementer (L2):**

| Attempt | Action |
|---------|--------|
| 1st | `TaskStop(task_id)` + re-dispatch with diagnosis and guidance in prompt |
| 2nd | `TaskStop(task_id)` + re-dispatch with broader context (full prior output summary) |
| Escalation | Write `escalation.json`, mark task blocked, move to next task |

`max_intervention_attempts` (default 2) controls attempts 1-2. The escalation step is not an intervention — it's the fallback after all interventions are exhausted.

**Orchestrator → phase dispatcher (L1):**

| Attempt | Action |
|---------|--------|
| 1st | `TaskStop(task_id)` + re-dispatch with diagnosis |
| 2nd | `AskUserQuestion` — user decides: re-dispatch with guidance, or abort phase |

L1 never auto-kills a phase dispatcher without user consent — always escalates on second attempt.

### Escalation File Format

Written per-task to phase worktree root as `escalation-{task_id}.json` (e.g., `escalation-A3.json`). Unique filenames prevent overwrite if multiple tasks escalate before the next L1 poll cycle.

```json
{
  "task_id": "A3",
  "issue": "Implementer stuck on permission prompt for database migration",
  "attempts": 2,
  "last_output_snippet": "...",
  "timestamp": "ISO8601"
}
```

The orchestrator reads all `escalation-*.json` files from the phase worktree on each poll cycle and surfaces each to the user.

### Progress Update Format

Orchestrator outputs to user every 60s:

```
[1m] Phase A: 1/5 tasks, healthy | Phase B: 0/4 tasks, starting
[2m] Phase A: 3/5 tasks, healthy | Phase B: 1/4 tasks, healthy
[3m] Phase A: 4/5 tasks, healthy | Phase B: 2/4 tasks, degraded (no commits)
[3m] ⚠ Phase B task B2: intervening — TaskStop + re-dispatch
[5m] Phase A: 5/5 tasks → review | Phase B: 4/4 tasks → review
```

### Configuration

New optional fields in plan.json:

```json
{
  "supervision": {
    "orchestrator_poll_seconds": 60,
    "dispatcher_poll_seconds": 30,
    "max_intervention_attempts": 2
  }
}
```

All fields optional with defaults shown.

## Key Decisions

1. **Inline polling loop over stop-hook pattern and foreground dispatch + monitor:** Three approaches considered: (a) Stop-hook pattern (ralph-loop): fires on exit attempts, not on a timer — semantic mismatch for periodic monitoring. (b) Foreground dispatch + parallel monitor agent: keeps synchronous dispatch but adds a monitoring subagent alongside — avoids TaskOutput/TaskStop dependency but the monitor can't intervene (it has no authority over the foreground-blocking parent). (c) Inline polling with `Bash("sleep N")`: supervisor dispatches background agents and actively polls — full tool access, direct intervention capability. Chose (c). **Risk:** Sleep-based polling loops are a novel pattern in this codebase. If `Bash("sleep N")` blocks agent responsiveness or the agent fails to continue the loop reliably, the fallback is: replace the sleep-based loop with a single-shot monitor subagent dispatched per poll cycle. Each monitor agent sleeps, checks signals, writes results to a status file, and exits. The supervisor reads the status file and decides whether to intervene. This trades one long-lived loop for N short-lived agents but preserves the same detection/intervention logic.

2. **L1 never auto-kills phases:** A phase timeout isn't meaningful because legitimate tasks can run 20+ minutes. The only signal is lack of progress, and even then, the user should decide whether to kill a phase dispatcher — the system can't distinguish "genuinely stuck" from "working on a hard problem slowly."

3. **Sequential tasks with background dispatch:** Tasks within a phase stay sequential (git conflict avoidance). `run_in_background: true` is for supervision visibility, not parallelism. The phase dispatcher sends one task at a time but can poll and intervene while it runs.

4. **escalation.json for L2→L1 communication:** Phase dispatchers can't signal the orchestrator directly (no inter-agent messaging available). File-based signaling via a known path in the phase worktree is simple and the orchestrator already polls the worktree. **Alternatives considered:** (a) Shared message queue file — rejected as over-engineered for the single-message escalation use case. (b) Phase dispatcher returns early with escalation info — rejected because it terminates the dispatcher, losing progress on remaining tasks.

## Non-Goals

- **Auto-recovery from all failure modes:** Some failures need human judgment. The system detects and escalates; it doesn't try to fix everything.
- **Parallel task execution within a phase:** Git conflicts make this impractical. Sequential dispatch is intentional.
- **Token optimization of the polling loop:** Per-cycle cost estimate: ~500-1500 tokens (sleep command ~10, TaskOutput read ~500-1000, git log ~50, jq ~50, progress output ~30, reasoning ~200). For a 60-minute orchestration with 60s polls, that's ~60 cycles × ~1000 tokens = ~60K tokens of supervision overhead. Claude Code's context window (200K) and automatic compression mean this is manageable — older poll cycles get compressed as the context fills. If context pressure becomes an issue, the per-cycle monitor subagent fallback (Key Decision 1) naturally isolates each cycle's tokens.

## Implementation Approach

Single phase — this is a fundamental control flow rewrite of both the orchestrator (SKILL.md) and phase dispatcher (phase-dispatcher-prompt.md) prompt templates, plus schema validation changes. Async dispatch and supervision are bundled intentionally: supervision without async dispatch is impossible (the supervisor must be free to poll), and async dispatch without supervision recreates the black-box problem at a higher concurrency level. Separating them would mean shipping unmonitored parallel execution as an intermediate state.

0. **Validate polling pattern (prerequisite)** — Before modifying any prompt templates, prototype the sleep-based polling loop: dispatch a no-op background agent (`Agent(run_in_background: true)`), call `Bash("sleep 10")`, then `TaskOutput(task_id, block: false)`. If TaskOutput returns the agent's output and the supervisor can continue processing after sleep, the pattern is validated. If it fails, switch to the per-cycle monitor subagent fallback before proceeding.
1. **Update `phase-dispatcher-prompt.md`** — Replace the existing synchronous "For each task" loop in `## Your Process` with a background-dispatch + polling pattern. Add sections: supervision loop (sleep 30s, check signals, evaluate health), intervention protocol (TaskStop + re-dispatch → escalation.json), and escalation file writing. The sequential task constraint remains — background dispatch is for supervision visibility, not parallelism.
2. **Update `SKILL.md`** — Replace the "Per-Phase Execution (Wave Loop)" pseudocode (current steps a-e) with async dispatch + L1 supervision loop. Steps a-c become: build DAG, dispatch all ready phases with `run_in_background: true`, capture task IDs. Steps d-e become the supervision loop: sleep, poll each active phase (TaskOutput + git log + plan.json + escalation files), evaluate health, output progress, intervene if needed. Existing per-phase post-processing (current steps 6-18: review loop, rebase, create-pr, poll, review-pr, merge, cleanup) remains unchanged but moves inside the supervision loop's completion handler — it runs inline when a phase is detected as complete via TaskOutput status.
3. **Update `scripts/validate-plan`** — Add schema validation for the optional `supervision` object at plan.json root level (fields: `orchestrator_poll_seconds`, `dispatcher_poll_seconds`, `max_intervention_attempts`, all optional integers with defaults).
4. **Update SKILL.md phase cleanup** — Add `escalation.json` removal to the Per-Phase Execution step 18 (worktree removal) so escalation files don't persist after merge.
