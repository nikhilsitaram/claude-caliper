---
status: In Development
---

# Add two-level supervision loop to orchestrate for async phase dispatch with stuck detection and intervention Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add two-level supervision loop to orchestrate for async phase dispatch with stuck detection and intervention
**Architecture:** Rewrite orchestrate SKILL.md wave loop to async dispatch + L1 polling supervision (60s). Rewrite phase-dispatcher-prompt.md task loop to background dispatch + L2 polling supervision (30s). Both levels use TaskOutput for health checks, TaskStop + re-dispatch for intervention, and escalation-*.json for L2-to-L1 communication. Add optional supervision config schema to validate-plan.
**Tech Stack:** Markdown (SKILL.md and prompt template), Bash (validate-plan script), jq (JSON schema validation), Claude Code tools (Agent, TaskOutput, TaskStop)

---

## Phase A — Supervision loop implementation
**Status:** Complete (2026-03-23) | **Rationale:** Single phase per design doc. The orchestrator and phase dispatcher are tightly coupled — supervision at L1 dispatches the L2-supervised phase dispatchers, and L2 writes escalation files that L1 reads. Separating them would require shipping unmonitored parallel execution as an intermediate state.

- [x] A1: Validate sleep-based polling pattern — *Prototype confirms: (a) Bash sleep 10 returns control to agent, (b) TaskOutput(task_id, block: false) returns background agent output and status after sleep, (c) supervisor executes a second sleep+TaskOutput cycle proving loop continues, (d) background agent completes independently. If any criterion fails, plan is blocked — stop and escalate.*
- [x] A2: Rewrite phase-dispatcher-prompt.md with L2 supervision loop — *Phase dispatcher prompt includes: (1) background dispatch of each implementer with run_in_background: true, (2) 30s polling loop with sleep + TaskOutput + git log checks, (3) detection logic for permission blocks, repeated errors, and no-progress, (4) intervention protocol (TaskStop + re-dispatch with max 2 attempts), (5) escalation-{task_id}.json writing after failed interventions, (6) sequential task constraint preserved. Word count stays under 2,000.*
- [x] A3: Rewrite orchestrate SKILL.md with L1 supervision loop — *Orchestrate SKILL.md includes: (1) async dispatch of ready phases with run_in_background: true, (2) 60s L1 polling loop with TaskOutput + plan.json + escalation file checks + git log, (3) progress update output format, (4) L1 intervention protocol (TaskStop + re-dispatch, then AskUserQuestion), (5) inline completion processing when phase detected complete, (6) escalation file surfacing to user. Word count stays under 2,000.*
- [x] A4: Add supervision schema validation to validate-plan — *validate-plan --schema accepts optional supervision object at plan.json root level. Valid fields: orchestrator_poll_seconds (positive integer), dispatcher_poll_seconds (positive integer), max_intervention_attempts (positive integer). Rejects non-integer values, negative values, and unknown keys. Existing valid plans without supervision field still pass. All tests pass.*
- [x] A5: Bump version in marketplace.json — *All three plugin versions in marketplace.json bumped to 1.13.0 (from 1.12.0). Single consistent version across all three plugins.*
- [x] A6: Run skill-eval for orchestrate — *Skill eval run for orchestrate covering scenarios: (1) multi-phase plan triggers async dispatch with run_in_background, (2) supervision loop includes polling and progress updates, (3) stuck detection triggers intervention, (4) escalation files surfaced to user. After variant pass rate >= before variant. Any regressions investigated and fixed.*
