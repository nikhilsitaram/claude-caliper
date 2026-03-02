# Phased Plans Design

**Issue:** #16 — Brainstorming and writing-plans should write plans in phases when necessary for complex work. Phases should follow logical order of dependencies.

## Problem

The skills infrastructure supports multi-phase plans (template structure exists, SDD executes phases correctly), but neither brainstorming nor writing-plans provides guidance on **when** to phase, **how** to determine phase boundaries, or **why** a particular ordering is correct. Good phasing currently depends on the human bringing that judgment.

## Evidence

The `investing` repo's post-migration-fixes plan demonstrates exemplary phasing — 6 phases, 37 tasks, dependency-ordered, independently shippable, each phase with a clear rationale. This quality emerged from human judgment, not skill guidance.

Meanwhile, the superpowers repo's three-level-integration-testing plan crammed 9 tasks into a single phase where phasing could have helped.

## Solution: Inline Guidance in Two Skills

Add phasing criteria and approval flow directly into the existing SKILL.md files. No new skills, no new files.

### Brainstorming Changes

**1. Phasing awareness during design presentation**

When presenting architecture, identify dependency layers — shared foundations (utilities, interfaces, schemas) consumed by downstream components. This surfaces phasing candidates naturally as part of architectural discussion.

**2. Phase approval gate**

After presenting all design sections, present a phasing recommendation as its own approval step:

- **Simple work:** "This is straightforward — single phase, no dependency layers. Sound right?"
- **Complex work:** "This has N dependency layers. Proposed phases: Phase 1 — [name + rationale], Phase 2 — [name + rationale], ... Does this phasing look right, or would you restructure it?"

Use AskUserQuestion so the user can approve, adjust, merge, split, or override to single-phase.

**3. Design doc "Implementation Approach" section**

When multi-phase work is approved, the design doc includes an "Implementation Approach" section capturing: approved phase names, ordering rationale, and which layers must land first. Omitted for single-phase work.

### Writing-Plans Changes

**1. Phasing Decision section**

New section between plan template and task writing guidance. Contains three triggers for multi-phase work:

- **Dependency layers** — Phase N creates things (utilities, interfaces, schemas) consumed by Phase N+1
- **Verification gates** — Phase N must be verified working before Phase N+1 can meaningfully start
- **Independent shippability** — each phase should be deployable/revertible on its own

Single-phase criteria: all tasks are independent or share only a linear dependency chain with no natural cut points. Don't phase for phasing's sake.

**2. Phase boundary guidance**

How to determine where one phase ends and the next begins:

- A boundary falls where "run full suite and verify" is meaningful — the work so far stands alone
- Each phase ends with a verification task ("Phase N commit — run full suite")
- Phase rationale required: one sentence per phase explaining why it exists and why it's in this position

**3. Design doc phasing inheritance**

If the design doc includes an "Implementation Approach" section with approved phases, writing-plans uses those as the starting structure rather than re-deriving from scratch. May refine (split, add verification tasks) but should not contradict approved phasing without flagging it.

## What Does NOT Change

- **Phase template format** — already correct (`### Phase N — [Name]` with status and checklist)
- **Task structure** — unchanged (Files, Verification, Done when, Avoid, Steps)
- **subagent-driven-development** — already handles multi-phase execution correctly
- **No new files or skills** — pure inline additions to 2 existing SKILL.md files

## Token Impact

~15-20 lines added per skill. No new skills to load.

## Signal Flow

```text
brainstorming: identify dependency layers during architecture
    -> present phasing recommendation to user
    -> user approves/adjusts
    -> design doc captures approved phases in "Implementation Approach"

writing-plans: read design doc phasing (if present)
    -> apply 3 triggers to validate/refine
    -> write phase boundaries with rationale + verification tasks
    -> hand off to SDD (unchanged)
```

## Closes

Issue #16
