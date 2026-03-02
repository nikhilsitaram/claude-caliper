---
status: Complete (2026-03-01)
---

# Plan Lifecycle Tracking & Completion Reports — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Make plan documents living records that track status, accumulate completion reports during execution, and carry handoff notes between phases.

**Architecture:** Modify four existing skill markdown files. No new skills, no code, no tests. Each task edits one skill file with specific text additions. The directory convention change (brainstorming, writing-plans) is independent of the lifecycle tracking change (orchestrators, implementation-review).

**Tech Stack:** Markdown skill files in `skills/` directory

---

## Phases

### Phase 1 — Directory Convention & Plan Frontmatter
**Status:** Complete (2026-03-01)

- [x] Task 1: Update brainstorming output path convention
- [x] Task 2: Update writing-plans output path and add frontmatter generation
- [x] Task 3: Commit phase 1 changes

### Phase 2 — Execution Lifecycle Tracking
**Status:** Complete (2026-03-01)

- [x] Task 4: Add plan doc status updates to subagent-driven-development
- [x] Task 5: Consolidate legacy execution references into subagent-driven-development flow
- [x] Task 6: Add completion report and handoff notes to implementation-review
- [x] Task 7: Commit phase 2 changes

---

## Task Details

### Task 1: Update brainstorming output path convention

**Files:**
- Modify: `skills/brainstorming/SKILL.md:31` (checklist item 6)
- Modify: `skills/brainstorming/SKILL.md:112-113` (After the Design > Documentation section)

**Verification:** Read the modified file, confirm both locations reference the new path convention.

**Done when:** Brainstorming skill references `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md` instead of `docs/plans/YYYY-MM-DD-<topic>-design.md` in both the checklist and the documentation section.

**Avoid:** Don't change any other behavior in brainstorming — only the output path convention. Don't add lifecycle status tracking here (that's writing-plans' job).

**Step 1: Edit checklist item 6 (line 31)**

Change:
```markdown
6. **Write design doc** — save to `docs/plans/YYYY-MM-DD-<topic>-design.md` and commit
```

To:
```markdown
6. **Write design doc** — save to `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md` and commit
```

**Step 2: Edit the "After the Design > Documentation" section (lines 111-112)**

Change:
```markdown
**Documentation:**
- Write the validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`
```

To:
```markdown
**Documentation:**
- Create topic folder `docs/plans/YYYY-MM-DD-<topic>/` if it doesn't exist
- Write the validated design to `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`
```

**Step 3: Verify**

Read `skills/brainstorming/SKILL.md` and confirm both references use the new convention.

---

### Task 2: Update writing-plans output path and add frontmatter generation

**Files:**
- Modify: `skills/writing-plans/SKILL.md:18` (Save plans to line)
- Modify: `skills/writing-plans/SKILL.md:37-49` (Plan Document Header template)
- Modify: `skills/writing-plans/SKILL.md:147-172` (Task Persistence section — .tasks.json path)

**Verification:** Read the modified file, confirm the save path, header template, and .tasks.json path all reference the new convention, and the header includes the status frontmatter.

**Done when:**
- Save path says `docs/plans/YYYY-MM-DD-<topic>/plan-<topic>.md`
- Plan header template includes `status: Not Yet Started` in YAML frontmatter
- Plan header template includes per-phase status lines and task checklists
- `.tasks.json` path references the topic folder

**Avoid:** Don't change task structure, review process, or execution handoff — only the output convention and header template. Don't add completion report writing here (that's the orchestrators' job).

**Step 1: Edit the "Save plans to" line (line 18)**

Change:
```markdown
**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`
```

To:
```markdown
**Save plans to:** `docs/plans/YYYY-MM-DD-<topic>/plan-<topic>.md` (inside the topic folder created by brainstorming)
```

**Step 2: Edit the Plan Document Header template (lines 37-49)**

Replace the entire header template block with:

````markdown
**Every plan MUST start with this header:**

```markdown
---
status: Not Yet Started
---

# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---

## Phases

### Phase 1 — [Phase Name]
**Status:** Not Yet Started

- [ ] Task 1: [Task title]
- [ ] Task 2: [Task title]

### Phase 2 — [Phase Name] (if multi-phase)
**Status:** Not Yet Started

- [ ] Task 3: [Task title]
- [ ] Task 4: [Task title]

---

## Task Details
```

**Status values:** `Not Yet Started` | `In Development` | `Complete (YYYY-MM-DD)`

The orchestrator (subagent-driven-development) updates these statuses during execution. The plan author only sets the initial `Not Yet Started` values.

For single-phase plans, use one phase section. The phase structure is required even for single-phase work — it keeps the format consistent and supports future phase additions.
````

**Step 3: Edit the Task Persistence section — update .tasks.json path**

In the Task Persistence section (around line 147), change the path reference:

Change:
```markdown
**File location:** Same directory as the plan, e.g. `docs/plans/.tasks.json`
```

To:
```markdown
**File location:** Same directory as the plan, e.g. `docs/plans/YYYY-MM-DD-<topic>/.tasks.json`
```

Also update the `planFile` field in the JSON example:

Change:
```json
"planFile": "docs/plans/YYYY-MM-DD-feature-name.md",
```

To:
```json
"planFile": "docs/plans/YYYY-MM-DD-topic/plan-topic.md",
```

**Step 4: Verify**

Read `skills/writing-plans/SKILL.md` and confirm all three locations are updated.

---

### Task 3: Commit phase 1 changes

**Files:**
- Commit: `skills/brainstorming/SKILL.md`
- Commit: `skills/writing-plans/SKILL.md`

**Verification:** `git status` shows clean working tree after commit.

**Done when:** Commit exists with both files, message references directory convention and frontmatter.

**Avoid:** Don't include any phase 2 changes in this commit.

**Step 1: Stage and commit**

```bash
git add skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md
git commit -m "feat(skills): per-project plan folders and lifecycle frontmatter

Update brainstorming to write design docs into per-topic folders.
Update writing-plans to write plans into same folders with status
frontmatter and per-phase task checklists.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Add plan doc status updates to subagent-driven-development

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

**Verification:** Read the modified file, confirm the three new behaviors are documented in the right places.

**Done when:** The skill file documents: (1) flipping status to `In Development` on first task start, (2) checking off tasks in the plan doc on completion, (3) appending a completion report section after all tasks complete.

**Avoid:** Don't change the subagent dispatch flow, review process, or deviation rules. Only add plan doc update instructions. Don't add implementation-review's responsibilities (handoff notes, review changes) here.

**Step 1: Add a new section "## Plan Doc Updates" after the "Deviation Rules" section (after line 226)**

Insert after the Deviation Rules section (before Red Flags):

```markdown
## Plan Doc Updates

The orchestrator updates the plan document during execution to maintain a living record.

**On first task start:**
1. Read the plan file
2. Change the frontmatter `status: Not Yet Started` to `status: In Development`
3. Change the current phase's `**Status:** Not Yet Started` to `**Status:** In Development`

**On each task completion:**
1. In the plan file's phase checklist, change `- [ ] Task N: ...` to `- [x] Task N: ...` for the completed task

**After all tasks complete (before invoking implementation-review):**
1. Append a `## Completion Report — [Phase Name]` section to the end of the plan doc
2. Include:
   - `**Completed:** YYYY-MM-DD`
   - `### Summary` — 2-3 sentences describing what was built
   - `### Deviations from Plan` — each deviation with: what changed, why, and impact (files/scope affected). Include Rule 1-3 auto-fixes from the deviation log. If no deviations, write "None — implemented as planned."

**After implementation-review passes:**
1. Change the current phase's status to `**Status:** Complete (YYYY-MM-DD)`
2. If all phases are complete, change the frontmatter to `status: Complete (YYYY-MM-DD)`
```

**Step 2: Update the process flow diagram**

In the process flow `digraph process` (lines 40-83), find this edge:

```
    "More tasks remain?" -> "Use superpowers:implementation-review for fresh-eyes review of entire feature" [label="no"];
```

Replace it with:

```
    "Write completion report to plan doc" [shape=box];
    "More tasks remain?" -> "Write completion report to plan doc" [label="no"];
    "Write completion report to plan doc" -> "Use superpowers:implementation-review for fresh-eyes review of entire feature";
```

**Step 3: Verify**

Read `skills/subagent-driven-development/SKILL.md` and confirm the new section exists and the flow diagram is updated.

---

### Task 5: Add plan doc status updates to subagent-driven-development

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

**Verification:** Read the modified file, confirm the three new behaviors are documented.

**Done when:** The skill file documents the same three plan doc update behaviors as Task 4 (status flip, task checkbox, completion report), adapted to the batch-execution model.

**Avoid:** Don't change the batch execution flow, review process, or deviation rules. Only add plan doc update instructions. Keep the same completion report format as Task 4 for consistency.

**Step 1: Add a new section "## Plan Doc Updates" after the "When to Revisit Earlier Steps" section (after line 116, before "Remember")**

Insert:

```markdown
## Plan Doc Updates

The executor updates the plan document during execution to maintain a living record.

**On first task start (Step 2, first batch):**
1. Read the plan file
2. Change the frontmatter `status: Not Yet Started` to `status: In Development`
3. Change the current phase's `**Status:** Not Yet Started` to `**Status:** In Development`

**On each task completion (Step 2, within batch):**
1. In the plan file's phase checklist, change `- [ ] Task N: ...` to `- [x] Task N: ...` for the completed task

**After all tasks complete (Step 5, before implementation-review):**
1. Append a `## Completion Report — [Phase Name]` section to the end of the plan doc
2. Include:
   - `**Completed:** YYYY-MM-DD`
   - `### Summary` — 2-3 sentences describing what was built
   - `### Deviations from Plan` — each deviation with: what changed, why, and impact (files/scope affected). Include Rule 1-3 auto-fixes from batch reports. If no deviations, write "None — implemented as planned."

**After implementation-review passes (Step 5, after review clean):**
1. Change the current phase's status to `**Status:** Complete (YYYY-MM-DD)`
2. If all phases are complete, change the frontmatter to `status: Complete (YYYY-MM-DD)`
```

**Step 2: Verify**

Read `skills/subagent-driven-development/SKILL.md` and confirm the new section exists.

---

### Task 6: Add completion report and handoff notes to implementation-review

**Files:**
- Modify: `skills/implementation-review/SKILL.md`
- Modify: `skills/implementation-review/reviewer-prompt.md`

**Verification:** Read both files, confirm the reviewer is instructed to read the completion report and write back to the plan doc after fixups.

**Done when:** (1) SKILL.md documents the two new post-review behaviors (document fixups, write handoff notes). (2) reviewer-prompt.md tells the reviewer to read the completion report as context and includes output sections for review changes and handoff notes.

**Avoid:** Don't change the core review focus (cross-task issues). The reviewer still does read-only review. The *orchestrator* writes the fixup documentation and handoff notes after the reviewer reports, based on what was fixed. Don't make the reviewer write to files.

**Step 1: Add post-review behaviors to SKILL.md**

In `skills/implementation-review/SKILL.md`, add a new section after "Red Flags" (after line 83) and before "Integration":

```markdown
## Post-Review: Plan Doc Updates

After the implementation review passes (all issues fixed, re-review clean), the **orchestrator** (not the reviewer subagent) updates the plan document:

**Document fixups:**
- Append an `### Implementation Review Changes` subsection to the existing `## Completion Report` section
- List each change made during review fixups (e.g., "Fixed inconsistent port config across modules")
- If no fixups were needed, omit this subsection

**Write handoff notes (multi-phase plans only):**
- If the plan has future phases, write handoff notes directly into the next phase's section
- Insert as a blockquote before the task checklist:
  ```markdown
  > **Handoff from Phase N:**
  > - [Thing the next phase needs to know]
  > - [API shape changes, new dependencies, scope adjustments]
  ```
- Handoff notes should cover: API/interface changes from what the plan originally assumed, new dependencies introduced, scope adjustments that affect future phases
- If there's nothing to hand off, don't add the blockquote
```

**Step 2: Update reviewer-prompt.md to include completion report as context**

In `skills/implementation-review/reviewer-prompt.md`, add a new section to the prompt template before `## Your Focus: Cross-Task Issues` (line 37):

```
    ## Completion Report

    The orchestrator has written a completion report for this phase in the plan document.
    Read the plan file at {PLAN_FILE_PATH} to understand:
    - What was completed (Summary section)
    - What deviated from the plan and why (Deviations section)

    Use this context to distinguish intentional deviations from accidental inconsistencies.
    An intentional deviation documented in the completion report is NOT a review issue.
```

**Step 2b: Add `{PLAN_FILE_PATH}` to the "How to Dispatch" variable list in SKILL.md**

In `skills/implementation-review/SKILL.md`, find the variable list in the "How to Dispatch" section (around lines 52-56):

```markdown
Then dispatch using `./reviewer-prompt.md` template with:
- `{BASE_SHA}` — where the feature branch diverged
- `{HEAD_SHA}` — current tip
- `{FEATURE_SUMMARY}` — what the feature does (1-2 sentences)
- `{TASK_LIST}` — list of tasks that were implemented
```

Add to the end of this list:

```markdown
- `{PLAN_FILE_PATH}` — path to the plan document (contains completion report)
```

**Step 3: Add handoff notes output section to reviewer-prompt.md**

In the Output Format section of the reviewer prompt, after the `### Assessment` block (ending at line 98) and before `## Critical Rules` (line 100), add:

```
    ### Handoff Notes for Next Phase (if multi-phase)

    If this is a multi-phase plan and there are future phases, list anything
    the next phase's implementer needs to know:
    - API/interface shapes that differ from what the plan assumed
    - New dependencies or config that future phases will need
    - Scope changes that affect future phase planning

    If nothing to hand off, write "No handoff notes needed."
```

The orchestrator uses these notes (from the reviewer's output) to write the blockquote into the plan doc.

**Step 4: Verify**

Read both `skills/implementation-review/SKILL.md` and `skills/implementation-review/reviewer-prompt.md`, confirm all additions are present.

---

### Task 7: Commit phase 2 changes

**Files:**
- Commit: `skills/subagent-driven-development/SKILL.md`
- Commit: `skills/implementation-review/SKILL.md`
- Commit: `skills/implementation-review/reviewer-prompt.md`

**Verification:** `git status` shows clean working tree after commit.

**Done when:** Commit exists with all four files, message references lifecycle tracking and completion reports.

**Avoid:** Don't include phase 1 files in this commit (they should already be committed).

**Step 1: Stage and commit**

```bash
git add skills/subagent-driven-development/SKILL.md skills/implementation-review/SKILL.md skills/implementation-review/reviewer-prompt.md
git commit -m "feat(skills): plan lifecycle tracking, completion reports, and handoff notes

Add plan doc update instructions to subagent-driven-development:
status flips, task checkboxes, completion reports.
Add post-review plan doc updates to implementation-review: fixup
documentation and cross-phase handoff notes.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Completion Report — Phase 1: Directory Convention & Plan Frontmatter

**Completed:** 2026-03-01

### Summary

Updated brainstorming and writing-plans skills to use per-topic folder convention (`docs/plans/YYYY-MM-DD-<topic>/`) instead of flat file naming. Added YAML frontmatter with `status` field and per-phase status tracking with task checklists to the plan document header template.

### Deviations from Plan

None — implemented as planned.

## Completion Report — Phase 2: Execution Lifecycle Tracking

**Completed:** 2026-03-01

### Summary

Added "Plan Doc Updates" section to the subagent-driven-development skill, documenting how orchestrators should update plan documents during execution (status flips, task checkboxes, completion reports). Added post-review plan doc update instructions to implementation-review (fixup documentation, handoff notes) and updated the reviewer prompt template with completion report context and handoff notes output section.

### Deviations from Plan

None — implemented as planned.
