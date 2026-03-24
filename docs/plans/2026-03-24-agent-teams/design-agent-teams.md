# Design: Agent Teams for Orchestrate

## Problem

The orchestrate skill's two-level polling supervision (L1: 60s, L2: 30s) has three structural problems:

1. **Token overhead**: ~60K tokens for a 60-minute orchestration, mostly sleep + TaskOutput parsing cycles that produce no useful work.
2. **Fragile detection**: Permission prompt regex, repeated-error heuristics, and no-progress consensus are all brittle against format changes. A single Claude Code UI update can silently degrade detection.
3. **Latency**: Worst-case 3 minutes to detect a stuck agent. Escalation files sit unread for up to 60 seconds between L1 polls.

The phase dispatcher intermediary adds ~1,700 words of prompt per phase. Its sole purpose — sequential task execution + supervision — can be replaced by agent teams with task dependencies and push-based notifications.

The current model also inverts parallelism suboptimally: phases run in parallel (requiring complex rebase-before-merge) while tasks within a phase run sequentially (underutilizing available concurrency).

## Goal

Replace the polling-based supervision architecture with Claude Code agent teams. The orchestrator becomes the team lead, each task becomes a teammate, and push-based idle notifications replace sleep/poll loops. Invert the parallelism model: sequential phases, parallel tasks within each phase.

## Success Criteria

1. A multi-phase plan completes with zero sleep/poll loops in the orchestrator
2. All tasks within a phase execute concurrently (one teammate per task)
3. Phases execute sequentially — Phase B tasks don't start until Phase A is fully merged
4. Parallel teammates within the same phase never produce merge conflicts
5. Stuck teammates are surfaced to the lead within 30 seconds via idle notification or direct messaging
6. Token overhead for supervision drops by >70% (from ~60K to <15K for a 60-minute orchestration)
7. Single-phase and multi-phase plans both work correctly
8. Per-task reviews begin immediately after each task completes, without waiting for other tasks in the same phase to finish
9. Plans with structural errors (missing task files, invalid task IDs, overlapping file sets within a phase, inconsistent statuses) are rejected before execution begins

## Architecture

### Current vs Proposed

```
Current:  Orchestrator ──poll 60s──▶ Phase Dispatchers ──poll 30s──▶ Task Implementers
                                     (1 per phase)                   (1 at a time)

Proposed: Lead (orchestrator) ──push notifications──▶ Teammates (1 per task, parallel)
                               ──push notifications──▶ Reviewer Teammates (1 per task, parallel)
```

### Execution Model

For each phase (sequential):

1. Lead reads plan.json, identifies the current phase's tasks
2. Lead spawns one implementer teammate per task — each gets an auto-worktree from the feature branch
3. All teammates execute in parallel (non-overlapping file sets guaranteed by plan constraints)
4. As each teammate completes, lead receives an idle notification (no polling)
5. Lead dispatches a reviewer teammate for each completed task — reviewers run concurrently with still-active implementers
6. When all implementers + reviewers for the phase are done:
   - Lead merges all task branches into the feature branch (no conflicts due to file-set isolation)
   - Lead runs implementation review (cross-task holistic) for the phase
   - Lead creates + merges phase PR (if multi-phase) or final PR (if single-phase)
7. Move to next phase from the updated feature branch

### Parallelism Inversion

| Dimension | Current | Proposed |
|-----------|---------|----------|
| Phases | Parallel (DAG-based waves) | Sequential |
| Tasks within phase | Sequential | Parallel (non-overlapping files) |
| Supervision | Polling (60s/30s) | Push (idle notifications) |
| Per-task review | Serial (after each task) | Parallel (as tasks complete) |

Sequential phases eliminate rebase-before-merge complexity. Parallel tasks within a phase are safe because each task touches a unique file set — enforced at plan time, validated before execution.

### File-Set Isolation

Each task in plan.json declares its file set via the existing `files` object (`create`, `modify`, `test` arrays). The constraint: no two tasks in the same phase may share any file path across any of these arrays.

Enforcement chain:
- **draft-plan**: Decomposes work so each task owns a unique file set
- **plan-review**: Validates file-set isolation as a review criterion
- **validate-plan**: Deterministic check — rejects plans with overlapping `create`, `modify`, or `test` paths within a phase

### Teammate Responsibilities

Implementer teammates are autonomous. Each teammate:

1. Reads its task metadata and prose
2. Marks task in-progress via `validate-plan --update-status`
3. Implements via TDD (red/green/refactor)
4. Commits work
5. Self-reviews
6. Writes task completion notes to `{PHASE_DIR}/{task_id_lower}-completion.md` (e.g., `phase-a/a1-completion.md`)
7. Marks task complete via `validate-plan --update-status`
8. Reports back to lead

This is a change from the current model where the phase dispatcher handles steps 1, 2, 7, and writes a single phase-level completion.md. With the dispatcher eliminated, teammates self-manage their lifecycle.

### Teammate Lifecycle

Each implementer teammate follows a strict lifecycle. The lead manages transitions:

```
Spawn → Implement → Idle (notify lead) → [Review Loop] → Validate → Kill
```

1. **Spawn**: Lead spawns teammate for a task. Teammate gets auto-worktree.
2. **Implement**: Teammate implements the task via TDD, commits, self-reviews, writes completion notes, marks task complete.
3. **Idle**: Teammate goes idle → lead receives notification. Teammate stays alive (not killed). The implementer's context still has all files loaded.
4. **Review loop**: Lead dispatches a reviewer teammate for the task. Reviewer produces review-summary JSON. If issues found, lead sends the review feedback to the *original implementer teammate* via messaging. Implementer fixes issues and goes idle again. Repeat until review passes.
5. **Validate**: Lead runs `validate-plan --criteria` for the task. If checks fail, lead sends feedback to implementer. Once all checks pass, lead proceeds.
6. **Kill**: Lead terminates the teammate. Worktree is preserved (has commits).

**Phase completion gate**: The lead cannot mark a phase complete until ALL teammates for that phase (implementers and reviewers) are terminated. This prevents the lead from advancing while teammates are still running or have unresolved work.

The review fix loop via messaging is a key optimization — the implementer already has all files in context, so sending it review feedback costs far fewer tokens than spawning a fresh agent to apply fixes.

### Review Stack

1. **Per-task reviewer teammate** — dispatched by lead when an implementer teammate goes idle. Runs the 6-point checklist (spec fidelity, TDD discipline, test quality, correctness, security, simplicity). Produces structured review-summary JSON. Runs concurrently with other active implementers.
2. **Review feedback loop** — if reviewer finds issues, lead sends feedback to the original implementer teammate (not a new agent). Implementer fixes and goes idle. Lead re-dispatches reviewer. Loop until clean.
3. **Implementation review** — after all tasks pass per-task review and all teammates are killed, a fresh-eyes Opus subagent reviews the full phase diff for cross-task issues (duplication, inconsistency, dead code).
4. **No per-task review blocking** — reviewer teammates don't block implementer teammates working on other tasks in the same phase.

### Agent Teams API Contract

Claude Code agent teams (experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, v2.1.32+) provide:

- **Teammate spawn**: Lead creates a team and spawns teammates. Each teammate is a separate Claude Code instance with its own context window and auto-provisioned git worktree at `.claude/worktrees/<name>/`.
- **Idle notifications**: When a teammate finishes work and is about to idle, the lead is automatically notified. This is push-based — the lead does not poll.
- **Mailbox messaging**: Teammates can send structured messages directly to the lead or to each other. Messages are delivered automatically (file-based inbox, recipient polls its own inbox, messages inject as synthetic conversation turns).
- **Shared task list**: All agents see task status. Dependencies auto-unblock when predecessors complete. Teammates claim available work.
- **Hooks**: `TeammateIdle` fires when teammate goes idle (exit code 2 sends feedback to keep working). `TaskCompleted` fires when a task is marked complete (exit code 2 prevents completion with feedback).
- **Wait semantics**: Lead receives notifications as conversation turns — no explicit blocking wait API. The lead processes notifications as they arrive.

**Feasibility risk**: This is an experimental feature. The API may change, teammate status can lag (teammates sometimes fail to mark tasks complete), and there is no session resumption with in-process teammates. The design accepts this risk — see Decision 6.

### Escalation

Teammates that hit unresolvable issues send a structured message directly to the lead via the mailbox. The lead receives it immediately (no polling delay). The lead can:
- Respond with guidance and keep the teammate working
- Stop the teammate and reassign the task
- Escalate to the user via AskUserQuestion

### Git Strategy

- **Single-phase**: Feature branch directly. Teammates work in auto-worktrees from the feature branch. Lead merges task branches into feature branch, creates PR to main.
- **Multi-phase**: `integrate/<feature>` branch. Per-phase, teammates work in auto-worktrees. Lead merges task branches into integration branch, creates phase PR. Final PR: integration branch → main.
- **Between phases**: Lead merges all task branches, ensuring the next phase's teammates start from the fully-integrated codebase.
- **No rebase-before-merge**: Phases are sequential, so the integration branch is never contested by parallel phase merges.

## Key Decisions

1. **Sequential phases, parallel tasks** — inverts the current model. Eliminates rebase-before-merge complexity. Tasks within a phase run concurrently because each touches a unique file set (enforced at plan time).

2. **File-set isolation as a plan constraint** — each task declares its file set in plan.json. No two tasks in the same phase share files. draft-plan enforces this at authoring time, plan-review validates it, validate-plan rejects violations deterministically.

3. **Flat hierarchy (no phase dispatcher)** — lead coordinates tasks directly. Phase boundaries enforced through sequential execution, not intermediary agents. Eliminates ~1,700 words of phase-dispatcher prompt per phase.

4. **Push-based completion, no polling** — idle notifications replace sleep/poll loops at both levels. Zero token overhead for supervision.

5. **Per-task reviewer teammates in parallel** — dispatched as implementer teammates finish. Run concurrently with still-active implementers. Same quality gate, no serial blocking.

6. **Agent teams only** — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. No fallback to polling. Accepted risk: if agent teams API changes or the feature flag is removed, the skill breaks entirely. Mitigation: the skill declares a hard dependency, so users without the flag simply can't invoke it. The alternative — maintaining both polling and agent-team code paths — doubles implementation and testing surface for a transitional period. One code path is worth the experimental dependency.

7. **Teammates self-manage lifecycle** — mark their own tasks in-progress/complete, write their own completion notes to `{PHASE_DIR}/{task_id_lower}-completion.md` (e.g., `phase-a/a1-completion.md`). The lead validates but doesn't micromanage.

8. **Comprehensive validate-plan checks** — new deterministic checks catch structural errors before execution begins, reducing runtime failures. See Task 8 in Implementation Approach for the specific check list.

## Alternatives Considered

**A. Keep polling, remove phase dispatcher** — simplify to one polling level (orchestrator polls task subagents directly). Partial benefit: eliminates L2 polling and dispatcher prompt overhead. Limitation: L1 polling overhead and fragile detection remain. Rejected because it addresses only half the problem.

**B. Subagents with `run_in_background` + event files** — keep the current subagent model but replace polling with file-based signaling (subagents write completion files, orchestrator watches via filesystem). Works without experimental feature flag. Limitation: still requires a watch/poll mechanism for file changes — no true push notification. Filesystem watching is platform-dependent and unreliable in worktrees. Rejected because it adds complexity without eliminating polling.

**C. Sequential everything** — no parallel execution at all (sequential phases, sequential tasks). Simplest possible implementation. Limitation: a 10-task plan takes 10x longer than necessary. Rejected because parallel task execution within a phase is a major throughput win, and agent teams make it safe via worktree isolation + file-set constraints.

**Agent teams (chosen)** — provides true push-based notifications, automatic worktree isolation, and native messaging. The experimental dependency is the tradeoff for eliminating polling entirely and getting first-class concurrency primitives.

## Non-Goals

- Parallel phase execution (sequential phases by design)
- Backward compatibility with polling-based supervision
- Language-specific linting or tooling in hooks
- Nested teams or sub-teams
- Auto-recovery from all failure modes (lead escalates to user when stuck)
- Fallback to subagent polling when agent teams feature flag is off

## Migrated Responsibilities

The phase dispatcher (phase-dispatcher-prompt.md) currently owns several responsibilities beyond task dispatch. Each must move to a new owner or be explicitly dropped:

| Responsibility | Current Owner | New Owner | Notes |
|---|---|---|---|
| Task lifecycle (mark in-progress/complete) | Phase dispatcher | Implementer teammate | Teammate self-manages via validate-plan |
| Task review dispatch | Phase dispatcher | Lead | Lead dispatches reviewer teammate on idle notification |
| Completion notes | Phase dispatcher (single completion.md) | Implementer teammate (per-task completion file) | `{task_id_lower}-completion.md` per task; lead aggregates after phase |
| Deviation rules 1-3 (auto-fix bug, add critical, fix blocker) | Phase dispatcher | Implementer teammate | Add to implementer prompt — teammates self-manage deviations |
| Deviation rule 4 (architectural change) | Phase dispatcher → orchestrator | Implementer teammate → lead | Teammate sends message to lead via mailbox; lead asks user |
| Safe commands learning loop | Phase dispatcher | Dropped | Safe commands hook handles this globally; per-phase learning loop adds no value |
| Cross-phase handoffs | Phase dispatcher | Lead | Lead writes handoff notes to next phase's task files between phases |
| Within-phase handoffs | Phase dispatcher | Dropped | Not needed — tasks within a phase are parallel with no intra-phase dependencies |

## Implementation Approach

**Single phase** — the changes are tightly coupled. The orchestrate SKILL.md rewrite depends on the implementer prompt changes, which depend on the validate-plan updates. Splitting into multiple phases would create intermediate broken states where the skill references features that don't exist yet.

### Tasks

1. **Update plan.json schema** — remove `supervision` config object. No new schema field needed — the file-set isolation constraint is on the existing `files.create`, `files.modify`, `files.test` arrays, enforced by validate-plan at execution time.
2. **Update draft-plan** — enforce file-set isolation when decomposing tasks within a phase
3. **Update plan-review** — validate file-set isolation as a review criterion
4. **Rewrite orchestrate SKILL.md** — replace wave loop + supervision with agent team coordination (sequential phases, parallel teammates, push-based completion)
5. **Delete phase-dispatcher-prompt.md** — no longer needed with flat hierarchy
6. **Update implementer-prompt.md** — teammates mark task in-progress/complete, write per-task completion notes to `{PHASE_DIR}/{task_id_lower}-completion.md`, handle deviation rules 1-3, escalate rule 4 via mailbox
7. **Update task-reviewer-prompt.md** — adapt for teammate dispatch model (reviewer is a teammate, not a subagent of the phase dispatcher)
8. **Update validate-plan** — new checks: file-set overlap for `modify`/`test` within a phase (existing check only covers `create`), status consistency (all tasks complete before phase marked complete, all phases complete before plan marked complete), task completion file exists when task status is complete, no orphaned `.md` files in phase directories, task ID prefix matches phase letter, phase letters are alphabetically ordered. Enhanced check: files declared in `files.create` exist on disk after task completion (post-implementation gate via `--criteria` flag).
9. **Bump version** — increment in marketplace.json
