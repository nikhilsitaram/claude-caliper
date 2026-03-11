---
status: Not Yet Started
---

# Tighten Phasing Model Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Restructure the phasing system across skill files to enforce letter+number task labeling, strict context isolation, inline handoff notes, per-phase completion notes, and stacked per-phase PRs.

**Architecture:** All changes are to markdown prompt/template files. The plan format (draft-plan), orchestration loop (orchestrate), dispatcher prompt (phase-dispatcher-prompt), and implementer prompt all update in parallel with the only constraint being consistent labeling conventions (A/B/C for phases, A1/A2/B1 for tasks) across all files.

**Tech Stack:** Markdown skill files, Claude Code plugin system (SKILL.md + supporting .md files)

---

## Phase A — Rewrite Skill Files

**Status:** Not Started
**Rationale:** All four files can change independently since they are prompt templates with no runtime dependencies. The only cross-file constraint is consistent labeling conventions, which a single phase handles naturally.

### Phase A Checklist

- [ ] A1: Rewrite draft-plan SKILL.md
- [ ] A2: Rewrite orchestrate SKILL.md
- [ ] A3: Rewrite phase-dispatcher-prompt.md
- [ ] A4: Rewrite implementer-prompt.md
- [ ] A5: Update plan-review reviewer-prompt.md

### Phase A Completion Notes
<!-- Written by dispatcher after all tasks complete.
     Implementation review changes appended here by orchestrator. -->

### Phase A Tasks

#### A1: Rewrite draft-plan SKILL.md

**Files:**
- Modify: `skills/draft-plan/SKILL.md`

**Verification:** Read the file and confirm all checklist items below are present. Word count under 1,000.

**Done when:** The draft-plan SKILL.md uses the new plan document structure from the design doc, letter+number labeling, and all structural changes listed in the steps below.

**Avoid:** Do not add content Claude already knows (general TDD, general markdown formatting). Every line must justify its token cost — the 1,000-word cap is a hard constraint. Do not use `@filename` references (they force-load files into context).

**Step 1: Read the current file and the design doc**
Read `skills/draft-plan/SKILL.md` and `docs/plans/2026-03-10-tighten-phasing/design-tighten-phasing.md` to understand both the current structure and the target state.

**Step 2: Rewrite the Plan Document Structure section**
Replace the current plan document structure template with the design doc's structure. Key changes:
- Phases use letters (A, B, C) not numbers (1, 2, 3)
- Tasks use letter+number (A1, A2, B1) not plain numbers (Task 0, Task 1)
- Each phase has three subsections: `### Phase X Checklist`, `### Phase X Completion Notes`, `### Phase X Tasks`
- Task details live inside their phase (under `### Phase X Tasks`) not in a separate flat `## Task Details` section
- Task headers use `#### A1: [name]` format
- Completion notes section has a comment explaining it's written by the dispatcher post-completion
- Handoff note placeholder syntax: `> **Handoff for B2:** [description — written by dispatcher after this task completes]`
- Phase status line format: `**Status:** Not Started | **Rationale:** ...`
- Remove the `> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate` line from the template (move it to a note that the planner should include it)
- Single-phase plans still use A-prefix (A1, A2, etc.)

**Step 3: Update the Task Structure section**
- Change task template heading from `### Task N: [Component Name]` to `#### A1: [Component Name]`
- Remove the standalone "Task 0" concept. Instead, note that the first task in a phase can be broad integration tests when cross-task data flow exists, labeled A1 (or whatever the first task ID is)
- Keep all 5 required fields (Files, Verification, Done when, Avoid+WHY, Steps)
- Add guidance about handoff note placeholders: when a task produces output consumed by a future phase, end the task block with a handoff placeholder blockquote tagged with the target task ID

**Step 4: Update the Phasing section**
- Replace "Phase N" / "Phase N+1" language with letter-based "Phase A" / "Phase B"
- Preserve the complexity gates (8+ tasks needs phasing, 7+ per phase examine cut points)
- Preserve "design doc inheritance" guidance

**Step 5: Update remaining references**
- Execution Handoff section: no structural changes needed, but update any "Phase 1" references to "Phase A"
- Plan Review Gate section: no changes needed (dispatches plan-review which will be updated in A5)
- Workflow section: no changes needed

**Step 6: Verify word count and token efficiency**
Count words. If over 1,000, cut content Claude already knows. The current file is ~820 words; the new version should stay under 1,000.

**Step 7: Commit**
```bash
git add skills/draft-plan/SKILL.md
git commit -m "refactor: update draft-plan to letter-based phasing with new plan structure"
```

---

#### A2: Rewrite orchestrate SKILL.md

**Files:**
- Modify: `skills/orchestrate/SKILL.md`

**Verification:** Read the file and confirm all checklist items below are present. Word count under 1,000.

**Done when:** The orchestrate SKILL.md uses letter-based phase/task labeling, context extraction logic for dispatcher (completion notes from prior phases + current phase section), stacked per-phase PRs with `git checkout -b` branching, and the new completion notes append flow.

**Avoid:** Do not add content Claude already knows (git branching basics, general subagent concepts). Do not bloat — the current file is ~950 words and the new version needs to stay under 1,000 while adding new concepts. Cut aggressively. Do not use `@filename` references.

**Step 1: Read the current file and the design doc**
Read `skills/orchestrate/SKILL.md` and the design doc sections on Context Isolation Model, Stacked Per-Phase PR Flow, and Plan Document Structure.

**Step 2: Update the Subagent Hierarchy**
No structural changes to the hierarchy itself, but update any "Phase 1" / "Phase 2" references to letter-based naming.

**Step 3: Rewrite the Per-Phase Execution section**
Replace the current per-phase loop. The new loop for each phase:
1. Record `PHASE_BASE_SHA=$(git rev-parse HEAD)`
2. If not Phase A: `git checkout -b phase-{letter}` (branches from prior phase tip)
   - Phase A: `git checkout -b phase-a` (branches from current HEAD)
3. Extract context for dispatcher:
   - Concatenate all `### Phase X Completion Notes` sections from prior phases (in order)
   - Extract current phase section (from `## Phase X` through end of that phase's tasks, before next `## Phase`)
4. Dispatch phase dispatcher with: prior completion notes as PHASE_CONTEXT, current phase section (checklist + tasks), PHASE_BASE_SHA
   - Dispatcher does NOT receive the plan header/goal/architecture or other phases' task details
5. After dispatcher returns: dispatch implementation-review (BASE_SHA = PHASE_BASE_SHA)
6. Triage findings through deviation rules, dispatch implementer fixes
7. Append implementation review changes to `### Phase X Completion Notes` (the dispatcher already wrote its summary there; orchestrator appends review fixes below it)
8. Emit phase summary
9. Update phase status
10. Ship phase PR: invoke ship, which creates PR with `--base phase-{prior-letter}` (or `--base main` for Phase A)

**Step 4: Rewrite the Handoff Notes section**
Replace the current standalone `### Phase N Handoff Notes` format. In the new model:
- Handoff notes are inline blockquotes on individual tasks, written by the dispatcher after task completion
- The orchestrator does NOT write separate handoff notes sections
- Remove the old Handoff Notes Format section entirely
- Add a brief note that the dispatcher writes inline handoff notes on tasks whose output feeds future phases

**Step 5: Update the Example Workflow**
Replace numbered phases with lettered phases. Update to show the stacked PR flow and context extraction. Example:

```text
[Read plan, identify phases]

git checkout -b phase-a
Phase A BASE_SHA = $(git rev-parse HEAD)
[Extract Phase A section from plan]
[Dispatch dispatcher: Phase A section only, no prior context]
  ...returns with completion notes written to plan...
[Dispatch implementation-review: PHASE_BASE_SHA..HEAD]
[Append review fixes to Phase A Completion Notes]
[Ship PR: --base main]

git checkout -b phase-b  (from phase-a tip)
Phase B BASE_SHA = $(git rev-parse HEAD)
[Extract Phase A Completion Notes + Phase B section]
[Dispatch dispatcher: completion notes as context + Phase B section]
  ...
[Ship PR: --base phase-a]
```

**Step 6: Update Plan Doc Updates table**
- Replace "Task N" with "A1" style labels
- Replace "Phase completion report written to plan doc by dispatcher" with "Dispatcher writes summary to Phase X Completion Notes"
- Add row: "Phase PR shipped" → "Ship creates PR with stacked base branch"
- Update "handoff notes" row to reflect inline handoff notes written by dispatcher

**Step 7: Update Key Constraints table**
- Add constraint: "Extract only completion notes + current phase for dispatcher" with why: "Context isolation prevents dispatcher from being overwhelmed by irrelevant phase details"
- Add constraint: "Ship per-phase PR with stacked base" with why: "Each PR shows only its phase's diff, making review manageable"

**Step 8: Verify word count**
Count words. Must be under 1,000. The current file is ~950 words. Aggressively cut anything the model already knows to make room for new concepts. Candidates for cutting: the full deviation rules table (already in dispatcher prompt), the full Rule 4 Handling section (move critical details to dispatcher prompt, keep only a brief reference here), verbose re-review gate details.

**Step 9: Commit**
```bash
git add skills/orchestrate/SKILL.md
git commit -m "refactor: update orchestrate to stacked PRs with context isolation"
```

---

#### A3: Rewrite phase-dispatcher-prompt.md

**Files:**
- Modify: `skills/orchestrate/phase-dispatcher-prompt.md`

**Verification:** Read the file and confirm all checklist items below are present.

**Done when:** The dispatcher prompt receives only prior completion notes + current phase section (not the full plan), uses letter+number task labels, writes inline handoff notes after task completion, and writes to the Phase Completion Notes section.

**Avoid:** Do not add content the dispatcher model already knows. The prompt is injected per-phase dispatch so token cost matters.

**Step 1: Read the current file and the design doc**
Read `skills/orchestrate/phase-dispatcher-prompt.md` and the design doc sections on Context Isolation Model, Plan Document Structure, and Section Purposes.

**Step 2: Update the variable substitution header**
Change from:
- `{PHASE_NUMBER}`, `{PHASE_NAME}`, `{TASK_LIST}`, `{PHASE_CONTEXT}`, `{PLAN_FILE_PATH}`, `{REPO_PATH}`

To:
- `{PHASE_LETTER}` — the phase letter (A, B, C)
- `{PHASE_NAME}` — the phase name
- `{PHASE_SECTION}` — the full phase section extracted by orchestrator (from `## Phase X` through end of tasks). This includes checklist, completion notes placeholder, and all task blocks.
- `{PRIOR_COMPLETION_NOTES}` — concatenated completion notes from all prior phases (empty for Phase A)
- `{PLAN_FILE_PATH}` — path to plan file (dispatcher still needs this to write updates)
- `{REPO_PATH}` — working directory

**Step 3: Update the dispatcher's input section**
Replace the current "## Plan" and "## Phase {PHASE_NUMBER}" sections with:
- `## Prior Phase Context` containing `{PRIOR_COMPLETION_NOTES}` (with note: "empty for Phase A")
- `## Phase {PHASE_LETTER} — {PHASE_NAME}` containing `{PHASE_SECTION}`
- Remove the instruction to "paste full text of each task" — the phase section already contains them

**Step 4: Update "Your Process" section**
- Change "Task N" references to letter+number format
- Add step after implementer returns: if this task's output feeds a future phase (indicated by a handoff placeholder blockquote in the task block), write the actual handoff note replacing the placeholder. Use real outputs: actual function signatures, file paths, config keys — not predictions.
- Update checkbox format: `- [ ] A1` → `- [x] A1`

**Step 5: Update "When All Tasks Are Done" section**
Replace the current Completion Report format. Instead of writing a separate `## Completion Report — Phase {PHASE_NUMBER}` section, the dispatcher writes to the `### Phase {PHASE_LETTER} Completion Notes` section that already exists in the plan (as a placeholder). Content:

```markdown
### Phase {PHASE_LETTER} Completion Notes

**Date:** YYYY-MM-DD
**Summary:** [2-4 sentences: what was built]
**Deviations:** [Each: A1 — what changed — Rule N — reason. "None" if plan followed exactly.]
```

**Step 6: Update "Report Back" section**
- Change "Tasks completed" to use letter+number format
- Keep HEAD SHA, integration test status, deviations, concerns

**Step 7: Update deviation rules**
- Change "Task N" to letter+number format in examples
- No structural changes to the rules themselves

**Step 8: Commit**
```bash
git add skills/orchestrate/phase-dispatcher-prompt.md
git commit -m "refactor: update dispatcher prompt for context isolation and inline handoffs"
```

---

#### A4: Rewrite implementer-prompt.md

**Files:**
- Modify: `skills/orchestrate/implementer-prompt.md`

**Verification:** Read the file and confirm it clarifies single-task-block input and uses letter+number labels.

**Done when:** The implementer prompt makes clear it receives only a single task block (#### AX: ...) including any inline handoff notes, uses letter+number labels, and does not reference phase structure or other tasks.

**Avoid:** Do not make unnecessary changes. The current implementer prompt is already close to the target — it receives a single task and implements it. Only adjust what the design doc requires.

**Step 1: Read the current file and the design doc**
Read `skills/orchestrate/implementer-prompt.md` and the design doc's Context Isolation Model (Implementer row).

**Step 2: Update the template header and description**
- Change `"Implement Task N: [task name]"` to `"Implement {TASK_ID}: [task name]"` where TASK_ID is like A1, B2
- Change `You are implementing Task N: [task name]` to `You are implementing {TASK_ID}: [task name]`

**Step 3: Update the Task Description section**
- Change `[FULL TEXT of task from plan - paste it here, don't make subagent read file]` to clarify: this is a single task block extracted from `#### {TASK_ID}: [name]` through the next `####` header. It includes any inline handoff notes (blockquotes) targeting this task from prior phases.
- Remove the separate `## Context` section with `[Scene-setting: where this fits, dependencies, architectural context]`. The handoff notes inline in the task block serve this purpose. Adding a separate context section risks leaking phase-level information that violates isolation.

**Step 4: Verify no references to phase structure**
Confirm the prompt does not reference phase numbers, other tasks, completion notes, or phase-level concepts. The implementer should only know about its single task block.

**Step 5: Commit**
```bash
git add skills/orchestrate/implementer-prompt.md
git commit -m "refactor: clarify implementer receives single task block with inline handoffs"
```

---

#### A5: Update plan-review reviewer-prompt.md

**Files:**
- Modify: `skills/plan-review/reviewer-prompt.md`

**Verification:** Read the file and confirm it validates the new plan structure (letter labeling, phase subsections, handoff placeholders).

**Done when:** The plan-review reviewer prompt checks for: letter+number task labeling, phase subsections (checklist/completion notes/tasks), inline handoff placeholders on cross-phase dependency tasks, and correct phase status line format.

**Avoid:** Do not change the 6-point checklist structure — it works well. Only update the specifics within each check to match the new plan format.

**Step 1: Read the current file**
Read `skills/plan-review/reviewer-prompt.md`.

**Step 2: Update Completeness check (#5)**
- Change task field references from `### Task N:` format to `#### A1:` format
- Add check: each phase has three subsections (Checklist, Completion Notes, Tasks)
- Add check: completion notes section exists with placeholder comment

**Step 3: Update Dependency Ordering check (#1)**
- Add: verify inline handoff placeholders exist on tasks whose output feeds future phases
- Use letter+number task IDs in examples

**Step 4: Update Phase Checks section**
- Change phase numbering examples from "Phase 1" / "Phase 2" to "Phase A" / "Phase B"
- Add check: tasks within each phase use correct letter prefix (Phase A tasks are A1, A2; Phase B tasks are B1, B2)
- Add check: handoff placeholders reference valid future task IDs

**Step 5: Update examples throughout**
- Replace `Task N` with `A1`, `B2` etc. in flag examples
- Replace `Phase 1` / `Phase 2` with `Phase A` / `Phase B`

**Step 6: Commit**
```bash
git add skills/plan-review/reviewer-prompt.md
git commit -m "refactor: update plan-review for letter-based labeling and new phase structure"
```

> **Handoff for evals:** After Phase A completes, the skill-eval system should be used to verify the rewritten skills produce correct output. The eval scenarios should test: plan generation with new format, orchestration with context isolation, dispatcher receiving scoped context. Written by dispatcher after task completion.
