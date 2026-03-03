---
status: Complete
---

# Inter-Phase Implementation Review — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development

**Goal:** Add automatic implementation review gates between phases of multi-phase plan execution, plus a >5-issue re-review rule across all review stages.

**Architecture:** Modify 4 existing skill files — SDD gains a per-phase execution loop, implementation-review gains phase-scoped context, reviewer-prompt gains phase-aware output, plan-review gains the re-review rule. No new skills or templates.

**Tech Stack:** Markdown skill files only.

---

### Phase 1 — Inter-Phase Review Gates
**Status:** Complete (2026-03-03)
**Rationale:** Single phase — all edits are independent skill file modifications with no dependency layers.

- [x] Task 1: Update implementation-review SKILL.md with inter-phase context
- [x] Task 2: Update implementation-review reviewer-prompt.md with phase-aware template
- [x] Task 3: Update SDD SKILL.md with multi-phase execution loop and >5 re-review rule
- [x] Task 4: Update plan-review SKILL.md with >5 re-review rule

Task 0 skipped: skill file edits with no cross-task data flow or imports.

**Note:** Line numbers in steps reference the original unmodified file. Use the semantic anchors (e.g., "After the existing `{REPO_PATH}` row") as the primary guide when line numbers shift due to earlier insertions within the same task.

**Testing:** SkillForge eval-driven testing deferred — these are targeted additions to existing skills, not new skill creation. Behavioral validation happens at first multi-phase plan execution.

---

## Task Details

### Task 1: Update implementation-review SKILL.md with inter-phase context

**Files:**
- Modify: `skills/implementation-review/SKILL.md`

**Verification:** Word count under 1,000w: `wc -w skills/implementation-review/SKILL.md`

**Done when:** SKILL.md includes inter-phase in When to Use, phase-scoped BASE_SHA guidance in How to Dispatch, new PHASE_CONTEXT template variable (which includes downstream phase expectations), and >5 re-review rule. Word count stays under 1,000w.

**Avoid:** Don't restructure the whole file — make targeted additions to existing sections. Don't repeat content that belongs in the reviewer-prompt.md template (Task 2 handles that).

**Step 1: Add inter-phase trigger to When to Use section**

After line 13 ("Before merging any multi-task feature branch"), add:

```markdown
- Between phases of a multi-phase plan (auto-dispatched by SDD after each phase)
```

**Step 2: Add phase-scoped variables to How to Dispatch table**

After the existing `{REPO_PATH}` row in the variable table (line 36), add:

```markdown
| `{PHASE_CONTEXT}` | Phase name, number (e.g., "Phase 1 of 3: Core API"), and what downstream phases expect (interfaces, config, APIs). Empty string for final/single-phase reviews. |
```

**Step 3: Add phase-scoped BASE_SHA guidance**

After the "Use the full diff range" paragraph (line 40), add:

```markdown
**Phase-scoped reviews:** For inter-phase reviews, `BASE_SHA` is the commit before the phase's first task — not `git merge-base origin/main`. This scopes the diff to only the current phase's changes.
```

**Step 4: Add >5 re-review rule**

After the "Post-Review: Plan Doc Updates" section (before ## Integration), add a new section:

```markdown
## Re-Review Gate

If the reviewer finds more than 5 fix-needed issues: after all fixes are applied, dispatch a fresh reviewer subagent with the same full review scope. This catches reviewer hallucination from compounding and new issues introduced by bulk fixes.

Under 5 issues, the orchestrator verifies fixes and proceeds without re-review.
```

**Step 5: Commit**

```bash
git add skills/implementation-review/SKILL.md
git commit -m "feat(implementation-review): add inter-phase review context and re-review gate"
```

---

### Task 2: Update implementation-review reviewer-prompt.md with phase-aware template

**Files:**
- Modify: `skills/implementation-review/reviewer-prompt.md`

**Verification:** Verify template renders correctly: `cat skills/implementation-review/reviewer-prompt.md`

**Done when:** Reviewer prompt includes {PHASE_CONTEXT} conditional block, "Ready for next phase?" in Assessment, and elevated Handoff Notes guidance for inter-phase reviews. Cross-phase boundary test coverage check present.

**Avoid:** Don't change the 7 cross-task issue categories — they're already comprehensive. Don't add a separate "phase review mode" — keep it one prompt with conditional sections.

**Step 1: Add PHASE_CONTEXT block after Git Range section**

After the Git Range section (after line 29 ```` ``` ````), add:

```markdown

    ## Phase Context (inter-phase reviews only)

    {PHASE_CONTEXT}

    If phase context is provided, this is an inter-phase review (not a final review).
    Pay special attention to:
    - Interface contracts that downstream phases depend on
    - Config, types, or APIs that downstream phases will consume
    - Anything that would be expensive to change after the next phase builds on it
```

**Step 2: Add cross-phase boundary test check to Integration Test Coverage output**

After the existing L3 row in the Integration Test Coverage table (line 75), add:

```markdown
    | L4: Cross-phase boundary tests | Pass/Fail/Missing | List interface contracts downstream phases depend on that lack tests |
```

**Step 3: Update Assessment section**

After line 82 ("**Ready to merge after fixing?** [Yes/No]"), add:

```markdown
    **Ready for next phase?** [Yes/No] (inter-phase reviews only)
```

**Step 4: Elevate Handoff Notes for inter-phase reviews**

Replace the current Handoff Notes section (lines 84-91) with:

```markdown
    ### Handoff Notes

    For inter-phase reviews, this is primary output. For final reviews, include if future work exists.

    List what the next implementer needs to know:
    - API/interface differences from plan assumptions
    - New dependencies or config needed
    - Scope changes affecting future phases
    - Interface contracts that downstream phases depend on — flag any without boundary tests

    If nothing: "No handoff notes needed."
```

**Step 5: Commit**

```bash
git add skills/implementation-review/reviewer-prompt.md
git commit -m "feat(implementation-review): add phase-aware reviewer template"
```

---

### Task 3: Update SDD SKILL.md with multi-phase execution loop and >5 re-review rule

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

**Verification:** Word count under 1,000w: `wc -w skills/subagent-driven-development/SKILL.md`

**Done when:** SDD includes a Multi-Phase Execution section describing the per-phase loop, >5 re-review rule as a cross-cutting principle, updated Plan Doc Updates for per-phase tracking. Single-phase behavior unchanged. Word count under 1,000w.

**Avoid:** Don't rewrite the existing per-task flow — it's correct. Don't duplicate the implementation-review dispatch details (reference the skill). Don't exceed 1,000w — the current file is ~646w, budget ~300w of additions. WHY: SDD is already the densest skill; exceeding cap would force cuts elsewhere.

**Step 1: Update "The Process" summary**

Replace lines 19-22:

```markdown
**Per task:** Dispatch implementer → spec compliance review → code quality review → mark complete

**After all tasks (per phase for multi-phase):** Write completion report → verify Task 0 integration tests → implementation review → handoff notes (if more phases) → next phase or ship
```

**Step 2: Add Multi-Phase Execution section**

After the "Example Workflow" section (after line 64), add a new section:

```markdown
## Multi-Phase Execution

For plans with multiple phases, the per-task flow runs within each phase. Between phases:

1. Record `PHASE_BASE_SHA` — commit before the phase's first task
2. Run full Task 0 test suite — failures in current phase scope are real issues; failures targeting future phases are expected (note and continue)
3. Dispatch implementation-review with phase-scoped diff (`PHASE_BASE_SHA..HEAD`) and `PHASE_CONTEXT` describing what downstream phases expect
4. Triage findings through deviation rules — dispatch fresh implementer for Rule 1-3 fixes, escalate Rule 4 to user
5. Verify cross-phase boundary tests exist for interface contracts downstream phases depend on (from reviewer handoff notes) — dispatch implementer to write missing ones
6. Orchestrator writes authoritative handoff notes into plan doc before next phase's checklist (reflects post-fix state, not reviewer suggestions)
7. Update phase status: `Complete (YYYY-MM-DD)`

After the final phase: write completion report (summary + deviations across all phases), then ship.

Single-phase plans skip this loop entirely — existing behavior unchanged.
```

**Step 3: Add >5 Re-Review Rule section**

After the new Multi-Phase Execution section, add:

```markdown
## Re-Review Gate

Applies to all review stages (spec, code quality, implementation review, plan review):

If a reviewer finds **more than 5 fix-needed issues**, after all fixes are applied, dispatch a fresh subagent with the same full review scope to confirm clean. Bulk fixes risk introducing new issues or incomplete resolution — a fresh reviewer catches what the fixer missed.

Under 5 issues: orchestrator verifies fixes and proceeds.
```

**Step 4: Update Plan Doc Updates table**

Replace the existing Plan Doc Updates section (lines 83-93, heading + intro text + table) with:

```markdown
## Plan Doc Updates

| When | Update |
|------|--------|
| First task starts | Frontmatter: `status: In Development` |
| Task completes | Change `- [ ] Task N` to `- [x] Task N` |
| Phase completes (multi-phase) | Insert handoff notes before next phase's checklist |
| Phase review passes | Phase status: `Complete (YYYY-MM-DD)` |
| All phases done | Append `## Completion Report` with summary + deviations |
```

**Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(SDD): add multi-phase execution loop and re-review gate"
```

---

### Task 4: Update plan-review SKILL.md with >5 re-review rule

**Files:**
- Modify: `skills/plan-review/SKILL.md`

**Verification:** Word count under 1,000w: `wc -w skills/plan-review/SKILL.md`

**Done when:** Plan-review SKILL.md includes the >5 re-review rule in the Output section. Word count under 1,000w.

**Avoid:** Don't change the 6-point checklist or reviewer-prompt.md — those are correct. Only add the re-review gate. WHY: plan-review is already well-scoped; the only missing piece is the >5 rule.

**Step 1: Update Output section with re-review gate**

Replace lines 63-64:

```markdown
**Pass:** Zero issues, or all issues fixed and re-reviewed
**Fail:** Return to writing-plans to fix, then re-run plan-review
```

With:

```markdown
**Pass:** Zero issues, or all issues fixed and confirmed clean
**Fail:** Return to writing-plans to fix, then re-run plan-review

**Re-review gate:** If the reviewer finds more than 5 issues, after all fixes, dispatch a fresh reviewer with the same full scope to confirm clean. Under 5 issues, verify fixes and proceed.
```

**Step 2: Commit**

```bash
git add skills/plan-review/SKILL.md
git commit -m "feat(plan-review): add >5 issues re-review gate"
```

## Completion Report

**Summary:** All 4 tasks completed. Added inter-phase review gates to SDD's execution loop, phase-scoped context and re-review gate to implementation-review, phase-aware template sections to reviewer-prompt, and >5-issue re-review rule to plan-review.

**Deviations:** None. All tasks executed as planned with no Rule 1-4 deviations.

**Word counts (all under 1,000w cap):**
- implementation-review SKILL.md: 523w
- subagent-driven-development SKILL.md: 888w
- plan-review SKILL.md: 486w
