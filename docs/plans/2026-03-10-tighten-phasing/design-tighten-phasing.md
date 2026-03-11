# Design: Tighten Phasing Model

## Goal

Restructure the phasing system to enforce strict context isolation at each orchestration level, introduce letter+number task labeling, stacked per-phase PRs, and a cleaner plan document structure with separated completion notes.

## Non-Goals

- No changes to reviewer prompts (spec, code quality)
- No changes to TDD or testing workflow
- No changes to build/brainstorming skill
- No changes to merge-pr skill

## Key Decisions

1. **Labeling:** Phases use letters (A, B, C), tasks use letter+number (A1, A2, B1, B2). Grep-friendly, visually distinct from version numbers.
2. **Handoff notes:** Plan author places placeholders on *target* tasks (e.g., B2 gets a placeholder "Handoff from A2: [TBD]"). Phase A's dispatcher fills in the actual details (real function signatures, file paths) by writing into B2's task block after completing A2. Phase B's dispatcher then naturally sees the handoff when extracting B2.
3. **Stacked per-phase PRs:** Each phase ships its own PR. Branches stack (phase-b branches from phase-a tip). All PRs merged in order at the end. Main stays clean until user is ready.
4. **Same worktree:** All phases work in the same worktree, creating new branches with `git checkout -b` rather than separate worktrees per phase.
5. **Completion notes:** Single section per phase between checklist and task details. Contains dispatcher summary + implementation review changes (appended by orchestrator).
6. **Context isolation:** Orchestrator sees full plan. Dispatcher sees only prior completion notes + current phase section. Implementer sees only its task block with inline handoff notes.

## Plan Document Structure

```markdown
---
status: Not Yet Started
---
# Feature Name

**Goal:** ...
**Architecture:** ...
**Tech stack:** ...

## Phase A — [Name]
**Status:** Not Started | **Rationale:** ...

### Phase A Checklist
- [ ] A1: [name]
- [ ] A2: [name]

### Phase A Completion Notes
<!-- Written by dispatcher after all tasks complete.
     Implementation review changes appended here by orchestrator. -->

### Phase A Tasks

#### A1: [name]
Files: ...
Verification: ...
Done when: ...
Avoid + WHY: ...
Steps: ...

#### A2: [name]
Files: ...
Steps: ...

---

## Phase B — [Name]
**Status:** Not Started | **Rationale:** ...

### Phase B Checklist
- [ ] B1: [name]
- [ ] B2: [name]

### Phase B Completion Notes

### Phase B Tasks

#### B1: [name]
...

#### B2: [name]

> **Handoff from A2:** [placeholder — Phase A dispatcher fills this in with actual interface/output after completing A2]

Steps: ...
```

### Section Purposes

- **Phase Checklist:** Quick progress view. Orchestrator updates checkboxes.
- **Phase Completion Notes:** Dispatcher writes summary after all tasks pass. Orchestrator appends implementation review changes. Next dispatcher receives this as context.
- **Phase Tasks:** Full task specifications. Dispatcher passes individual tasks to implementers.
- **Inline Handoff Notes:** Plan author places placeholders on *target* tasks (e.g., `> **Handoff from A2:** [TBD]` on B2). Source phase's dispatcher fills in actual details after completing the producing task. Already inline on the target task when the consuming phase's dispatcher extracts it.

## Context Isolation Model

```
Level           Receives                            Does NOT Receive
─────────────   ─────────────────────────────────   ──────────────────────
Orchestrator    Full plan document                  (sees everything)
Dispatcher      All prior Phase Completion Notes    Other phases' task details,
                + current phase section             plan header/goal/arch
                (checklist + tasks)
Implementer     Single task block (#### AX: ...)    Other tasks, completion
                including any inline handoff        notes, phase structure
                notes targeting this task
```

### How Orchestrator Extracts Context for Dispatcher

The orchestrator reads the full plan and constructs dispatcher input by:

1. Extracting all `### Phase X Completion Notes` sections from prior phases (concatenated in order)
2. Extracting the current phase section (from `## Phase X` header through end of that phase's tasks section, before the next `## Phase` header)

This is prompt construction — the plan stays as one document.

### How Dispatcher Extracts Context for Implementer

The dispatcher extracts a single task block:

1. From `#### AX: [name]` through the next `####` header (or end of tasks section)
2. This naturally includes any inline handoff notes (blockquotes tagged with this task's ID)

## Stacked Per-Phase PR Flow

```
Same worktree:
  git checkout -b phase-a
  → Phase A work → impl review → ship PR (base: main)

  git checkout -b phase-b    # branches from phase-a tip
  → Phase B work → impl review → ship PR (base: phase-a)

  git checkout -b phase-c    # branches from phase-b tip
  → Phase C work → impl review → ship PR (base: phase-b)

User merges in order: phase-a → main, phase-b → main, phase-c → main
```

**Key details:**
- Each PR only shows its phase's diff (because base is the prior phase branch, not main)
- After phase-a merges to main, GitHub auto-retargets phase-b's PR base to main
- Orchestrator creates new branch after shipping each phase's PR
- No merge-wait-rebase cycle between phases — implementation flows continuously
- `gh pr create --base phase-a` sets the correct PR base for stacked PRs

## What Changes

| Skill File | Change Summary |
|------------|----------------|
| `skills/draft-plan/SKILL.md` | New plan format: letter labeling, phase sections with checklist/completion/tasks subsections, handoff note placeholder syntax, single-phase plans still use A-prefix |
| `skills/orchestrate/SKILL.md` | Per-phase PR flow with stacked branches, context extraction logic for dispatcher, handoff note orchestration, completion note append logic |
| `skills/orchestrate/phase-dispatcher-prompt.md` | Receives only completion notes + phase plan, writes handoff notes on target tasks in future phases after completing producing tasks, writes completion notes section |
| `skills/orchestrate/implementer-prompt.md` | Clarify it receives single task block only (already close to this) |
| `skills/implementation-review/SKILL.md` | No structural changes — already supports phase-scoped review via BASE_SHA/HEAD_SHA |
| `skills/ship/SKILL.md` | No changes — already handles current branch |

## Implementation Approach

Single phase. All changes are to prompt/template files with no dependency ordering between them — the plan format, orchestrator, dispatcher, and implementer prompts can be updated independently. The only constraint is internal consistency (labeling conventions must match across all files).
