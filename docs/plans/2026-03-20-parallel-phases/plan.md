---
status: Complete
---

# Enable parallel phase execution via per-phase worktrees and integration branches Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Enable parallel phase execution via per-phase worktrees and integration branches
**Architecture:** Extend plan.json schema with workflow routing and phase-level depends_on. Update validate-plan for new fields and cycle detection. Update design, draft-plan, orchestrate, ship, and merge-pr skills to use integration branch model with per-phase worktrees. Add DAG-based wave dispatch for concurrent phase execution.
**Tech Stack:** Bash (validate-plan script), Markdown (SKILL.md files), jq, git worktree, gh CLI

---

## Phase A — Schema, Routing, and Integration Branch Model
**Status:** Complete (2026-03-20) | **Rationale:** Foundation layer: schema validation, workflow routing, and the integration branch model must exist before Phase B can add parallel dispatch on top. All skill updates in this phase switch to the integration branch model with sequential phase dispatch.

- [x] A1: Add workflow and phase depends_on validation to validate-plan — *validate-plan --schema validates workflow enum (ship|review-only|plan-only), phase-level depends_on arrays (valid letters only, backward references), and detects circular phase dependencies; all new schema tests pass*
- [x] A2: Update test fixture for new schema fields — *Valid plan fixture includes workflow field and phase depends_on arrays; all test suites pass with updated fixture*
- [x] A3: Update draft-plan SKILL.md for workflow and phase depends_on — *draft-plan SKILL.md documents workflow field (ship|review-only|plan-only) in plan.json example and fields table; phase-level depends_on documented in plan.json example with explanation; word count remains under 1000*
- [x] A4: Update design SKILL.md for integration branch and workflow routing — *Design SKILL.md step 7 uses .claude/worktrees/<feature>/ path and integrate/<feature> branch naming; new step after draft-plan asks user about workflow preference (ship/review-only/plan-only) and writes it to plan.json; word count remains under 1000*
- [x] A5: Add --base argument to ship SKILL.md — *Ship SKILL.md Arguments table includes --base <branch> argument; Step 8 (Create PR) uses gh pr create --base when --base is provided, defaults to $DEFAULT_BRANCH when omitted; word count remains under 1000*
- [x] A6: Update orchestrate SKILL.md for integration branch model — *Orchestrate SKILL.md reads workflow field from plan.json and routes accordingly (ship/review-only/plan-only); uses integration branch naming (integrate/<feature>); creates per-phase worktrees at .claude/worktrees/<feature>-phase-{letter}/; ships phase PRs with --base integrate/<feature>; final PR targets main; PRIOR_COMPLETIONS scoped to transitive depends_on closure; word count remains under 1000*
- [x] A7: Update phase-dispatcher-prompt.md for integration branch PR targeting — *Phase dispatcher prompt notes that {REPO_PATH} is the phase worktree path (not main repo); prior completions scoped to dependency chain (not all prior phases); no other behavioral changes*

## Phase B — Parallel Dispatch and Merge Flow
**Status:** Complete (2026-03-20) | **Rationale:** Builds on Phase A's integration branch model to add concurrent phase execution. Requires the schema, worktree layout, and integration branch conventions from Phase A to be in place.

- [x] B1: Add DAG wave logic for parallel phase dispatch to orchestrate — *Orchestrate SKILL.md includes DAG construction from phase depends_on; wave-based dispatch loop (identify ready phases, dispatch in parallel, process completions serially); example workflow shows diamond dependency (A->B+C->D) with parallel B+C dispatch; sequential plans degrade gracefully*
- [x] B2: Add rebase-before-merge step for parallel phases to orchestrate — *Orchestrate SKILL.md documents rebase step after each parallel phase completes: rebase phase branch on latest integration, trivial conflicts (no markers) proceed with test verification, non-trivial conflicts (markers present) pause for user; serialized completion processing prevents race conditions*
- [x] B3: Update merge-pr SKILL.md for final integration-to-main merge — *Merge-pr SKILL.md handles integration branch PRs: detects integrate/<feature> branch pattern; cleanup removes all phase worktrees (.claude/worktrees/<feature>-phase-*) and integration worktree (.claude/worktrees/<feature>); deletes integration branch and phase branches; word count remains under 1000*
- [x] B4: Add dependency reconciliation step to orchestrate — *Orchestrate SKILL.md includes a Dependency Reconciliation sub-step between phase completion processing and dispatching newly-ready phases: for each non-root phase, run git diff --name-only against dependency phases, detect file overlap and semantic impacts against current phase tasks, filter out declared dependencies, inject Reconciliation sections into affected task .md files after H1 and any Handoff sections, log injections; key constraints table includes reconciliation entry; example workflow shows reconciliation log line*
- [x] B5: Bump marketplace.json version — *All three plugin entries in marketplace.json have version bumped from 1.6.0 to 1.7.0*
