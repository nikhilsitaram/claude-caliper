---
status: In Development
---

# Add execution mode selection (main/subagents/agent-teams) to orchestration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add execution mode selection (main/subagents/agent-teams) to orchestration
**Architecture:** execution_mode becomes a required enum in plan.json. Mode-specific dispatch logic lives in separate template files (dispatch-main.md, dispatch-subagents.md, dispatch-agent-teams.md) referenced conditionally from orchestrate SKILL.md. The design skill replaces the agent-teams prerequisite with a combined decision point for workflow extent, execution mode, and design approval.
**Tech Stack:** Bash (validate-plan script), Markdown (SKILL.md files, dispatch templates)

---

## Phase A — Execution Modes
**Status:** Not Started | **Rationale:** Single phase — all changes are tightly coupled (design reads mode, orchestrate dispatches on mode, plan schema validates mode). Within-phase depends_on handles the T1 → [T2,T3,T7] → [T4,T5] → T6 → T8 sequencing.

- [ ] A1: Add execution_mode to validate-plan schema — *validate-plan --schema rejects plan.json missing execution_mode or with invalid values, accepts valid enum values (main, subagents, agent-teams); test_execution_mode.sh passes (note: existing test_schema.sh will fail until A8 updates the fixture)*
- [ ] A2: Rewrite design SKILL.md for execution mode selection — *Agent teams prerequisite section removed. Steps 7+8 replaced with single AskUserQuestion offering workflow extent + execution mode + design approval. Auto-suggestion logic included. Agent-teams fallback flow tells user to set env var and restart. Word count under 2000.*
- [ ] A3: Extract dispatch-agent-teams.md from current orchestrate SKILL.md — *dispatch-agent-teams.md contains the current teammate-based dispatch protocol extracted verbatim from orchestrate SKILL.md (spawn teammates, push-based completions, mailbox feedback, incremental merge, dependency gate)*
- [ ] A4: Write dispatch-subagents.md — *dispatch-subagents.md documents parallel Agent tool dispatch with isolation: worktree, run_in_background, push-based completion handling, and fresh-agent review fix cycle (no mailbox)*
- [ ] A5: Write dispatch-main.md — *dispatch-main.md documents sequential execution where the lead implements each task directly (no subagent dispatch for implementation, no teammates). Review is still dispatched as a synchronous subagent (fresh-eyes review requires a separate agent). Uses the same completion/review loop structure.*
- [ ] A6: Refactor orchestrate SKILL.md for execution_mode dispatch — *Orchestrate SKILL.md reads execution_mode from plan.json at setup. Inline dispatch logic replaced with conditional See-reference to the matching dispatch file. Agent teams env var check moved to dispatch-agent-teams.md only. Word count under 2000. marketplace.json version bumped.*
- [ ] A7: Update draft-plan to include execution_mode in plan.json — *draft-plan SKILL.md plan.json template includes execution_mode field as a placeholder (design skill overwrites it after draft-plan returns with the user's actual choice). Word count under 2000.*
- [ ] A8: Add execution_mode tests and update valid-plan fixture — *Valid-plan fixture includes execution_mode field. Full regression suite passes (all test scripts in tests/validate-plan/ and tests/hooks/). New test_execution_mode.sh tests pass.*
