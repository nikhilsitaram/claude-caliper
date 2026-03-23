# Design: Two-Level Supervision Loop for Orchestrate

## Problem

Phase dispatchers are 15+ minute black boxes. When they hit issues (permission prompts, repeated errors, wrong code patterns), nobody notices until completion or user intervention. The orchestrator has zero visibility into running phases, and phase dispatchers have zero visibility into running task implementers. Observed in practice: a phase dispatcher spent significant time debugging a `set -e` + command substitution interaction because the task prose used a broken pattern — the orchestrator had no visibility until the user noticed permission prompts.

Additionally, orchestrate's SKILL.md specifies "Dispatch ready phases IN PARALLEL (one Agent per phase)" but the current prompt templates dispatch synchronously — the orchestrator blocks waiting for each phase dispatcher to return. Supervision requires async dispatch because the supervisor must remain free to poll while workers execute; bundling both concerns is intentional.

## Goal

Add a two-level supervision hierarchy to orchestrate:
- **L1 (Orchestrator → Phase Dispatchers):** Async dispatch of independent phases with 60s polling, progress updates to user, and intervention capability.
- **L2 (Phase Dispatcher → Task Implementers):** Async dispatch of sequential tasks with 30s polling, intervention capability, and escalation to orchestrator when unresolvable.

## Success Criteria

1. Independent phases in the same wave execute concurrently (dispatched with `run_in_background: true`).
2. The user sees a progress update every 60s showing task completion counts and health status per active phase.
3. A stuck task implementer (repeated errors, permission blocks) is detected within two L2 poll cycles (~60s) and receives intervention.
4. A stuck phase dispatcher is detected within two L1 poll cycles (~120s) and the user is alerted via AskUserQuestion.
5. An unresolvable task (2 failed interventions) is escalated via `escalation.json`, surfaced to the user on next orchestrator poll, and the phase continues to the next task.
6. Task implementers within a phase still execute sequentially (one at a time) to avoid git conflicts.
7. Each supervision poll cycle uses fewer than 5 tool calls (sleep + signal checks + progress output).

## Architecture

### Tool Availability

The supervision loop relies on these Claude Code built-in tools for background agent management:

- **`Agent(run_in_background: true)`** — dispatches a subagent that runs independently; returns an agent ID immediately. The parent agent continues processing.
- **`TaskOutput(agent_id)`** — reads output from a running or completed background agent. Used to check for error patterns and progress signals.
- **`SendMessage(to: agent_id, message)`** — sends a message to a running background agent, resuming it with additional context. Used for mid-flight intervention.
- **`TaskStop(agent_id)`** — terminates a running background agent. Used as last-resort intervention before escalation.

These tools are available to any agent in Claude Code when managing background tasks. The existing orchestrate skill already uses `Agent` (foreground); the change is adding `run_in_background: true` and using the companion tools for supervision.

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
  → Phase dispatcher intervenes (SendMessage with guidance)
  → 2nd attempt: TaskStop + re-dispatch with additional context
  → After 2 failed interventions: write escalation.json, skip to next task
  → Orchestrator reads escalation.json on next poll → alerts user

Phase dispatcher stuck
  → Orchestrator intervenes (SendMessage)
  → 2nd attempt: AskUserQuestion to user
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
      degraded → SendMessage(phase_agent_id, guidance)
      stuck → escalate to user via AskUserQuestion

    OUTPUT PROGRESS UPDATE to user:
      "[2m] Phase A: 3/5 tasks, healthy | Phase B: 1/4 tasks, healthy"

    process completed phases serially (review → merge)
    if all phases complete → break
```

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
| TaskOutput patterns | `TaskOutput(agent_id)` tail | Error loops, permission blocks |
| Task status | `jq` on plan.json in worktree | Completion count |

**Stuck indicators** (any one triggers intervention):
- TaskOutput shows the same error repeated 3+ times
- TaskOutput shows "permission" / "denied" / "blocked" language
- No new commits since last poll AND no new tool output
- Implementer has returned with an error exit

**Healthy indicators** (all must hold):
- New commits or new tool output since last poll
- No error patterns in recent output

### Intervention Protocol

**Phase dispatcher → implementer (L2):**

| Attempt | Action |
|---------|--------|
| 1st | `SendMessage(agent_id, "<diagnosis + guidance>")` |
| 2nd | `TaskStop(agent_id)` + re-dispatch with extra context |
| Escalation | Write `escalation.json`, mark task blocked, move to next task |

`max_intervention_attempts` (default 2) controls attempts 1-2. The escalation step is not an intervention — it's the fallback after all interventions are exhausted.

**Orchestrator → phase dispatcher (L1):**

| Attempt | Action |
|---------|--------|
| 1st | `SendMessage(agent_id, "<diagnosis + guidance>")` |
| 2nd | `AskUserQuestion` — user decides: kill + re-dispatch, or let continue |

L1 never auto-kills a phase dispatcher — always escalates to user on second attempt.

### Escalation File Format

Written to phase worktree root (`escalation.json`):

```json
{
  "task_id": "A3",
  "issue": "Implementer stuck on permission prompt for database migration",
  "attempts": 2,
  "last_output_snippet": "...",
  "timestamp": "ISO8601"
}
```

### Progress Update Format

Orchestrator outputs to user every 60s:

```
[1m] Phase A: 1/5 tasks, healthy | Phase B: 0/4 tasks, starting
[2m] Phase A: 3/5 tasks, healthy | Phase B: 1/4 tasks, healthy
[3m] Phase A: 4/5 tasks, healthy | Phase B: 2/4 tasks, degraded (no commits)
[3m] ⚠ Phase B task B2: intervening — sending guidance
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

1. **Inline polling loop over stop-hook pattern:** The ralph-loop (stop-hook) pattern is designed for iterative re-prompting, not periodic monitoring. Inline polling with `Bash("sleep N")` keeps the supervisor active in the same session with full tool access. Simpler and semantically correct. **Risk:** Sleep-based polling loops are a novel pattern in this codebase. If `Bash("sleep N")` blocks agent responsiveness or the agent fails to continue the loop reliably, a fallback is to dispatch a lightweight monitor subagent per poll cycle instead of sleeping inline.

2. **L1 never auto-kills phases:** A phase timeout isn't meaningful because legitimate tasks can run 20+ minutes. The only signal is lack of progress, and even then, the user should decide whether to kill a phase dispatcher — the system can't distinguish "genuinely stuck" from "working on a hard problem slowly."

3. **Sequential tasks with background dispatch:** Tasks within a phase stay sequential (git conflict avoidance). `run_in_background: true` is for supervision visibility, not parallelism. The phase dispatcher sends one task at a time but can poll and intervene while it runs.

4. **escalation.json for L2→L1 communication:** Phase dispatchers can't SendMessage to the orchestrator (they don't know its agent ID). File-based signaling via a known path in the phase worktree is simple and the orchestrator already polls the worktree. **Alternatives considered:** (a) Pass orchestrator agent ID to phase dispatcher for direct SendMessage — rejected because agent IDs are runtime-generated and adding this parameter complicates the dispatch interface for marginal benefit. (b) Shared message queue file — rejected as over-engineered for the single-message escalation use case.

## Non-Goals

- **Auto-recovery from all failure modes:** Some failures need human judgment. The system detects and escalates; it doesn't try to fix everything.
- **Parallel task execution within a phase:** Git conflicts make this impractical. Sequential dispatch is intentional.
- **Token optimization of the polling loop:** At ~500-1500 tokens per cycle and <5% overhead, optimization isn't warranted now.

## Implementation Approach

Single phase — prompt-template modifications plus minor schema validation:

1. **Update `phase-dispatcher-prompt.md`** — Replace the existing synchronous "For each task" loop in `## Your Process` with a background-dispatch + polling pattern. Add sections: supervision loop (sleep 30s, check signals, evaluate health), intervention protocol (SendMessage → TaskStop → escalation.json), and escalation file writing. The sequential task constraint remains — background dispatch is for supervision visibility, not parallelism.
2. **Update `SKILL.md`** — Replace the "Per-Phase Execution (Wave Loop)" pseudocode (current steps a-e) with async dispatch + L1 supervision loop. Add: agent ID tracking per dispatched phase, supervision loop protocol (sleep 60s, read plan.json from phase worktrees, check escalation.json, evaluate health), progress update output format, and escalation handling (surface to user). Completion processing (review → merge) triggers when a phase is detected as complete during a poll cycle.
3. **Update `scripts/validate-plan`** — Add schema validation for the optional `supervision` object at plan.json root level (fields: `orchestrator_poll_seconds`, `dispatcher_poll_seconds`, `max_intervention_attempts`, all optional integers with defaults).
4. **Update SKILL.md phase cleanup** — Add `escalation.json` removal to the phase worktree cleanup step (current step 18) so escalation files don't persist after merge.
