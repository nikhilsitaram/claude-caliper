---
status: Complete (2026-03-02)
---

# Phased Plans Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add phasing guidance to brainstorming and writing-plans skills so plans use multi-phase structure when dependency layers, verification gates, or shippability warrant it.

**Architecture:** Inline additions to two existing SKILL.md files. Brainstorming surfaces phasing candidates during design and gets user approval. Writing-plans adds a phasing decision framework with three triggers and boundary rules. No new files or skills.

**Tech Stack:** Markdown skill files

**Design doc:** `docs/plans/2026-03-02-phased-plans/design-phased-plans.md`

**Task 0 skipped:** Purely additive Markdown changes to two independent files, no cross-task data flow, no code.

---

## Phases

### Phase 1 — Phasing Guidance
**Status:** Complete (2026-03-02)

- [x] Task 1: Add phasing awareness and approval gate to brainstorming
- [x] Task 2: Add phasing decision section to writing-plans

---

## Task Details

---

### Task 1: Add phasing awareness and approval gate to brainstorming

**Files:**
- Modify: `skills/brainstorming/SKILL.md:104-120`

**Verification:** `grep -c "phasing\|Implementation Approach" skills/brainstorming/SKILL.md` returns 4+

**Done when:** brainstorming/SKILL.md contains: (1) phasing awareness bullet in "Presenting the design" section, (2) phasing recommendation subsection with single-phase and multi-phase scripts, (3) AskUserQuestion instruction for phase approval, (4) "Implementation Approach" design doc section guidance.

**Avoid:** Don't add a new checklist item — phasing approval is part of existing step 5 ("Present design"). Don't change the DOT diagram — it's already complex enough and the phasing approval lives within "Present design sections" → "User approves design?" flow.

**Step 1: Add phasing awareness to "Presenting the design" section**

After the existing bullet list ending at line 109, add a phasing awareness bullet. Find:

```markdown
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense
```

Replace with:

```markdown
- Cover: architecture, components, data flow, error handling, testing
- When the architecture reveals shared foundations (utilities, interfaces, schemas) consumed by downstream components, note these as **phasing candidates**
- Be ready to go back and clarify if something doesn't make sense
```

**Step 2: Add phasing recommendation subsection**

Between the last bullet of "Presenting the design" (line 109: "Be ready to go back and clarify if something doesn't make sense") and the `## After the Design` heading (line 111), add:

```markdown

**Phasing recommendation:**

After presenting all design sections, present a phasing recommendation before moving to worktree setup:

- **Simple work (single phase):** "This is straightforward — single phase, no dependency layers. Sound right?"
- **Complex work (multi-phase):** "This has N dependency layers. Proposed phases: Phase 1 — [name + rationale], Phase 2 — [name + rationale], ... Does this phasing look right, or would you restructure it?"

Use AskUserQuestion with options like "Looks good" / "Adjust phases" so the user can approve, adjust, merge, split, or override to single-phase.
```

**Step 3: Add Implementation Approach to design doc guidance**

In the "After the Design > Documentation" section, find:

```markdown
- Commit the design document to git
```

Replace with:

```markdown
- When multi-phase work was approved, include an **Implementation Approach** section in the design doc: approved phase names, ordering rationale, which layers must land first
- Commit the design document to git
```

**Step 4: Verify**

Run: `grep -c "phasing\|Implementation Approach" skills/brainstorming/SKILL.md`
Expected: 4 or more matches

**Step 5: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat(brainstorming): add phasing awareness and approval gate (closes #16)"
```

---

### Task 2: Add phasing decision section to writing-plans

**Files:**
- Modify: `skills/writing-plans/SKILL.md:78-80`

**Verification:** `grep -ic "dependency layers\|verification gates\|shippability\|Implementation Approach" skills/writing-plans/SKILL.md` returns 4+

**Done when:** writing-plans/SKILL.md contains: (1) "Phasing Decision" section with three triggers (dependency layers, verification gates, shippability), (2) single-phase criteria, (3) phase boundary rules (verification task, rationale requirement), (4) design doc phasing inheritance instruction.

**Avoid:** Don't change the existing phase template format — it's already correct. Don't change the Task Structure section. Don't move existing content — insert between the existing single-phase paragraph (line 78) and the Task Structure heading (line 80).

**Step 1: Add Phasing Decision section**

Find the blank line between the single-phase paragraph and Task Structure:

```markdown
For single-phase plans, use one phase section. The phase structure is required even for single-phase work — it keeps the format consistent and supports future phase additions.

## Task Structure
```

Insert between them:

```markdown
For single-phase plans, use one phase section. The phase structure is required even for single-phase work — it keeps the format consistent and supports future phase additions.

## Phasing Decision

Before writing tasks, determine whether the plan needs multiple phases.

**Use multiple phases when ANY of these apply:**

1. **Dependency layers** — Phase N creates things (utilities, interfaces, schemas) consumed by Phase N+1. Example: shared utility extraction must land before bug fixes that import those utilities.
2. **Verification gates** — Phase N must be verified working before Phase N+1 can meaningfully start. Example: database schema changes must be tested before API routes that depend on the new schema.
3. **Independent shippability** — each phase should be deployable and revertible on its own. Example: "critical bugs" phase can ship independently of "code quality" phase.

**Stay single-phase when:** All tasks are independent or share only a linear dependency chain with no natural cut points. Don't phase for phasing's sake — one phase with 5 tasks is better than 5 phases with 1 task each.

**Phase boundary rules:**

- A boundary falls where "run full suite and verify" is meaningful — the work so far stands alone
- Each phase ends with a verification task ("Phase N commit — run full suite")
- Phase rationale required: one sentence per phase explaining why it exists and why it's in this position (e.g., "Everything downstream imports these. Must land first.")

**Design doc inheritance:** If the design doc includes an **Implementation Approach** section with approved phases from brainstorming, use those as the starting structure. You may refine (split a phase, add verification tasks) but should not contradict approved phasing without flagging the deviation to the user.

## Task Structure
```

**Step 2: Verify**

Run: `grep -ic "dependency layers\|verification gates\|shippability\|Implementation Approach" skills/writing-plans/SKILL.md`
Expected: 4 or more matches

**Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat(writing-plans): add phasing decision framework (closes #16)"
```

---

## Completion Report — Phasing Guidance

**Completed:** 2026-03-02

### Summary

Added phasing awareness and approval gate to the brainstorming skill (3 insertions: phasing candidates bullet, phasing recommendation subsection with AskUserQuestion, Implementation Approach design doc guidance). Added a Phasing Decision section to the writing-plans skill (1 insertion: three triggers, single-phase criteria, boundary rules, design doc inheritance). Both skills now guide Claude to evaluate and recommend phasing when dependency layers, verification gates, or independent shippability warrant it.

### Deviations from Plan

None — implemented as planned.
