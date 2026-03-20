---
status: In Development
design-doc: docs/plans/2026-03-19-design-review/design-design-review.md
---

# Design Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add design-review skill, success criteria to design doc template, and traceability from criteria through plan-review and implementation-review — so implementation success is measured against the design spec, not just code correctness.

**Architecture:** All changes are to markdown skill/prompt files. Two new files create the design-review skill (SKILL.md + reviewer-prompt.md). Seven existing skill files gain patches for the design doc template upgrade, design-review dispatch step, design-doc path propagation via plan frontmatter, and new review checks for success criteria coverage/fulfillment. One JSON config file adds the new skill to plugin arrays and bumps the version.

**Tech Stack:** Markdown skill files, Claude Code plugin system (SKILL.md + supporting .md files), JSON plugin manifest

---

## Phase A — Design Review Skill and Downstream Patches

**Status:** Not Started | **Rationale:** All changes target independent markdown/JSON files with no runtime dependencies between them. The design doc explicitly specifies single-phase. The cross-file constraint is consistent terminology (success criteria format, design doc path variable name, section ordering) which is manageable in a single phase. Complexity gate note: 10 tasks exceeds the 8-task guideline, but these are all independent prompt-file edits with no dependency ordering — splitting into phases would add overhead without reducing risk.

### Phase A Checklist
- [x] A1: Create design-review SKILL.md
- [x] A2: Create design-review reviewer-prompt.md
- [x] A3: Update design skill template and workflow
- [x] A4: Add design-doc field to draft-plan frontmatter
- [x] A5: Add Success Criteria Coverage check to plan-review SKILL.md
- [x] A6: Add Success Criteria Coverage check to plan-review reviewer-prompt.md
- [x] A7: Add Success Criteria Fulfillment to implementation-review SKILL.md
- [x] A8: Add Success Criteria Fulfillment to implementation-review reviewer-prompt.md
- [x] A9: Add design-doc path extraction to orchestrate SKILL.md
- [x] A10: Register design-review skill in marketplace.json

### Phase A Completion Notes

**Date:** 2026-03-19
**Summary:** Created the design-review skill (SKILL.md + reviewer-prompt.md) with an 8-point checklist for validating design docs before planning. Updated the design skill to dispatch design-review as a hard gate before draft-plan. Added success criteria traceability: design-doc path in plan frontmatter, Success Criteria Coverage check in plan-review, Success Criteria Fulfillment check in implementation-review, and design-doc path extraction in orchestrate. Registered the new skill in marketplace.json with version bump to 1.2.0.
**Deviations:** None

### Phase A Tasks

#### A1: Create design-review SKILL.md

**Files:**
- Create: `skills/design-review/SKILL.md`

**Verification:** Read `skills/design-review/SKILL.md` and confirm: (1) frontmatter has name and description fields, (2) 8-point checklist present with one-line descriptions, (3) dispatch instructions reference reviewer-prompt.md, (4) word count under 1,000, (5) description starts with "Use when..."

**Done when:** `skills/design-review/SKILL.md` exists with frontmatter (name: design-review, description starting with "Use when..."), explains when to use, lists the 8-point review checklist by name with one-line descriptions, includes dispatch instructions listing design doc path and repo root as inputs, output format description, and fix loop guidance.

**Avoid:** Don't expand each check into full sub-checks in SKILL.md — that detail belongs in reviewer-prompt.md only. SKILL.md lists the 8 checks by name with one-line descriptions (matching plan-review's SKILL.md pattern where the checklist is a summary table, not the full prompt). Don't use `@filename` references (they force-load files into context). Don't include content Claude already knows (general review practices).

**Step 1: Read pattern files**

Read `skills/plan-review/SKILL.md` to understand the established pattern for review skills. Note:
- Frontmatter format: `name:` and `description:` fields
- "When to Use" section
- "Dispatch" section with variable table
- Checklist as a summary table (not expanded sub-checks)
- "Output" section describing what the reviewer produces
- "Integration" section

**Step 2: Create the skill file**

Create `skills/design-review/SKILL.md` with this content:

```markdown
---
name: design-review
description: Use when a design doc has been written and before draft-plan is dispatched
---

# Design Review

Dispatch an Opus subagent to validate a design doc before planning. Catches spec gaps that are cheap to fix in design but expensive to fix mid-implementation.

**Core principle:** Designs are hypotheses about what to build. Validate before committing to a plan.

## When to Use

- After the design skill writes a design doc (auto-dispatched)
- When asked to review any existing design doc
- Before draft-plan is dispatched (hard gate)

**Skip for:** Trivially small changes with no design doc.

## Dispatch

Gather inputs:
- **Design doc** — `docs/plans/YYYY-MM-DD-topic/design-topic.md`
- **Repo root** — the worktree the design targets

Dispatch with `model: "opus"` — fresh-eyes review requires strong reasoning to catch blind spots the designer and user converged past.

**See:** reviewer-prompt.md

## 8-Point Checklist

1. **Problem Clarity** — specific problem, who is affected, consequences of not solving
2. **Success Criteria Quality** — human-verifiable, implementation-independent, collectively complete, individually necessary
3. **Architecture-Problem Fit** — architecture addresses stated problem, feasibility risks identified
4. **Alternative Assessment** — considers more effective or efficient approaches
5. **Scope Alignment** — solves stated problem and not more, non-goals correctly scoped
6. **Decision Justification** — key decisions include trade-off analysis
7. **Internal Consistency** — names, paths, concepts consistent across sections
8. **Handoff Quality** — plan drafter with zero context can produce correct plan from doc alone

## Output

Reviewer produces:
- Issues Found (category, problem, fix with specific text suggestions)
- Assessment table (PASS/FAIL per check)
- "Ready for planning?" verdict

**Pass:** Zero issues, or all issues fixed and confirmed clean
**Fail:** Return to design skill to fix, then re-run design-review

**Re-review gate:** If the reviewer finds more than 5 issues, after all fixes, dispatch a fresh reviewer with the same full scope to confirm clean.

## Integration

**Auto-dispatched by:** design (after design doc written)

**Leads to:** draft-plan (once review passes)
```

**Step 3: Verify**

Read the created file. Confirm all 8 checks present, word count under 1,000, no `@filename` references, description starts with "Use when...".

---

#### A2: Create design-review reviewer-prompt.md

**Files:**
- Create: `skills/design-review/reviewer-prompt.md`

**Verification:** Read `skills/design-review/reviewer-prompt.md` and confirm: (1) has `{DESIGN_DOC_PATH}` and `{REPO_PATH}` placeholder variables, (2) all 8 checks expanded with sub-checks, flag conditions, and heuristics, (3) output format includes issues + assessment table + verdict, (4) follows the fenced code block pattern from `skills/plan-review/reviewer-prompt.md`

**Done when:** `skills/design-review/reviewer-prompt.md` exists with a prompt template in a fenced code block containing `{DESIGN_DOC_PATH}` and `{REPO_PATH}` variables, all 8 checks expanded with specific sub-checks and flag conditions, and output format matching the assessment table pattern.

**Avoid:** Don't deviate from the established reviewer-prompt pattern in `skills/plan-review/reviewer-prompt.md` — same structure (intro paragraph, yaml-like dispatch header, fenced prompt block with inputs/checks/output/rules sections). Don't add checks beyond the 8 specified in the design doc. Don't make the output format inconsistent with plan-review's output format.

**Step 1: Read pattern file**

Read `skills/plan-review/reviewer-prompt.md` to understand the exact structure:
- Opening paragraph explaining when to dispatch
- Fenced code block with `Agent tool (general-purpose):` header
- `model:`, `description:`, `prompt:` fields
- Inside prompt: Inputs section with variables, numbered checklist sections each with sub-checks and Flag items, Output section with Issues Found + Assessment table, Rules section

**Step 2: Create the reviewer prompt file**

Create `skills/design-review/reviewer-prompt.md` following the exact same structure as `skills/plan-review/reviewer-prompt.md`. The file has three parts:

**Part 1 — Header** (outside the code block):

A level-1 heading "Design Review Prompt Template", a one-line description paragraph ("Dispatch an Opus reviewer subagent to validate a design doc before planning begins."), and a bold note ("Only dispatch after the design doc is fully written and saved.").

**Part 2 — Fenced prompt block** (single `yaml` code fence, matching plan-review's pattern):

```yaml
Agent tool (general-purpose):
  model: "opus"
  description: "Design doc review"
  prompt: |
    You are reviewing a design doc BEFORE any planning or implementation begins.
    Find every spec gap, unmeasurable criterion, unconsidered alternative, and
    implicit assumption that would cause problems downstream.

    ## Inputs

    **Design doc:** {DESIGN_DOC_PATH}
    **Codebase:** {REPO_PATH} (read existing files to verify paths, check for existing patterns)

    ## 8-Point Checklist

    Work through each systematically. Read the FULL design doc first, then evaluate.

    ### 1. Problem Clarity
    Verify the Problem section:
    - States a specific problem (not vague dissatisfaction)
    - Identifies who is affected
    - States consequences of not solving (what happens if we do nothing)

    - Flag: "We need X" without saying why
    - Flag: Problem statement that describes the solution instead of the problem
    - Flag: Missing "who is affected" — can't verify success without knowing the user

    ### 2. Success Criteria Quality
    For each criterion in the Success Criteria section:
    - Human-verifiable: a person can confirm yes/no by observing behavior or outcomes
    - Implementation-independent: doesn't reference specific code, tests, or tools (e.g., "pytest passes" is implementation-dependent; "users can log in" is not)
    - Collectively complete: if ALL criteria pass, the Goal is fully met
    - Individually necessary: removing any single criterion would leave a gap

    - Flag: "Tests pass" or "middleware installed" (implementation-dependent)
    - Flag: Criterion that can't be verified without reading code
    - Flag: Goal mentions X but no criterion covers X (collectively incomplete)
    - Flag: Two criteria that say the same thing differently (redundant, not necessary)
    - Flag: Missing Success Criteria section entirely

    ### 3. Architecture-Problem Fit
    Verify the architecture addresses the stated problem:
    - Each architectural component traces to a part of the problem
    - No component exists without a problem-driven reason
    - Scope is appropriate (not over-engineered, not under-specified)
    - Feasibility: are there technical risks or unproven assumptions?

    - Flag: Architecture component with no connection to the problem
    - Flag: Problem aspect with no architectural response
    - Flag: Unproven assumption stated as fact (e.g., "X library supports Y" without verification)
    - Flag: Technical risk not acknowledged

    ### 4. Alternative Assessment
    Check whether the design considered alternatives:
    - Does an existing skill already partially cover this functionality?
    - Does the codebase have a similar pattern that could be extended?
    - Are there established approaches in the problem domain?
    - Is the chosen approach the most effective path to meeting success criteria?

    - Flag: No alternatives section or discussion
    - Flag: Alternatives dismissed without trade-off analysis
    - Flag: Existing codebase pattern could be extended but isn't mentioned
    - Flag: Chosen approach is more complex than an alternative with equivalent effectiveness

    ### 5. Scope Alignment
    Verify the design solves the stated problem and not more:
    - Every change is justified by the problem statement
    - Features beyond what the problem requires are flagged as potential scope creep
    - Non-goals are correctly scoped with rationale
    - Non-goals don't exclude things that the problem actually requires

    - Flag: Change that doesn't trace back to the problem
    - Flag: Missing non-goals section when the design touches multiple systems
    - Flag: Non-goal that contradicts a success criterion
    - Flag: Scope creep — feature/complexity beyond what the problem demands

    ### 6. Decision Justification
    For each key decision:
    - Trade-off analysis present (what was gained, what was given up)
    - Alternatives considered and reasons for rejection
    - Decision is consistent with success criteria

    - Flag: Decision stated without alternatives considered
    - Flag: Decision contradicts a success criterion
    - Flag: "We chose X" without explaining why not Y

    ### 7. Internal Consistency
    Cross-reference across all sections:
    - Names, paths, and concepts used identically everywhere
    - Architecture section matches the file change table
    - No contradictions between sections
    - Section references are accurate

    - Flag: Same concept with different names in different sections
    - Flag: File path in architecture differs from file change table
    - Flag: Architecture says X, key decisions says Y (contradiction)
    - Flag: Section references something not present in the referenced section

    ### 8. Handoff Quality
    Evaluate whether a plan drafter with zero conversation context can produce a correct plan:
    - No implicit assumptions left uncaptured
    - File paths and change descriptions are specific enough
    - Architecture is concrete, not hand-wavy
    - Implementation approach gives clear direction

    - Flag: "Modify the handler" without specifying which file
    - Flag: Architecture describes behavior but not structure
    - Flag: Implicit knowledge required (e.g., assumes reader knows the codebase convention)
    - Flag: File change table missing or incomplete

    ## Output

    ### Issues Found

    For each issue:
    - **Category** (1-8)
    - **Problem** (specific, quote the design doc)
    - **Fix** (what to change, with specific text suggestions)

    ### Assessment

    | Check | Status |
    |-------|--------|
    | Problem clarity | PASS/FAIL |
    | Success criteria quality | PASS/FAIL |
    | Architecture-problem fit | PASS/FAIL |
    | Alternative assessment | PASS/FAIL |
    | Scope alignment | PASS/FAIL |
    | Decision justification | PASS/FAIL |
    | Internal consistency | PASS/FAIL |
    | Handoff quality | PASS/FAIL |

    **Issues:** [count]
    **Severity:** Critical (blocks planning) / High (likely causes plan failure) / Medium (may cause confusion) / Low (cosmetic)
    **Ready for planning?** Yes / Yes after fixes / No, needs rework

    ## Rules

    - This is a DESIGN QUALITY check, not a code review or style review
    - Be specific: quote design doc text, reference section names
    - If zero issues, say so — don't invent problems
    - READ-ONLY: Do not modify any files
    - DO check codebase when design references existing files or patterns
    - Success criteria are about outcomes, not implementation — flag any criterion that references code, tests, or tools
```

The prompt content (everything between the `prompt: |` and the closing fence) is indented 4 spaces, matching the plan-review pattern. The full prompt content is provided above in the checklist sections (Steps 2's content between `prompt: |` and the closing fence includes: Inputs section, 8-Point Checklist with all 8 numbered checks including sub-checks and Flag items, Output section with Issues Found and Assessment table, and Rules section).

**Step 3: Verify**

Read the created file. Confirm: all 8 checks expanded with sub-checks and Flag items, `{DESIGN_DOC_PATH}` and `{REPO_PATH}` placeholders present, output section has assessment table, follows plan-review's structural pattern.

---

#### A3: Update design skill template and workflow

**Files:**
- Modify: `skills/design/SKILL.md`

**Verification:** Read `skills/design/SKILL.md` and confirm: (1) Design Doc Contents section lists Problem and Success Criteria sections in correct order, (2) checklist step 9 dispatches design-review, (3) checklist step 10 dispatches draft-plan, (4) word count under 1,000

**Done when:** The design skill's checklist inserts a design-review dispatch step between "Write design doc" and "Dispatch draft-plan," the Design Doc Contents section lists sections in order (Problem, Goal, Success Criteria, Architecture, Key Decisions, Non-Goals, Implementation Approach), and the design-review dispatch uses the same Agent pattern as the existing draft-plan dispatch.

**Avoid:** Don't restructure sections that aren't changing — the Checklist, Challenging Assumptions, Smart Question Batching, and Presenting the Design sections stay as-is except for checklist renumbering. Don't exceed 1,000 words — the design doc template additions must be concise.

**Step 1: Read current file**

Read `skills/design/SKILL.md` to confirm the exact current text of the sections being modified.

**Step 2: Update the checklist**

Replace the current steps 8-9 in the checklist:

Current:
```
8. **Write design doc** — `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`, commit
9. **Dispatch draft-plan subagent** — fresh Opus agent with design doc path and worktree path (zero design context)
```

New:
```
8. **Write design doc** — `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`, commit
9. **Dispatch design-review subagent** — fresh Opus agent validates design before planning (hard gate)
10. **Dispatch draft-plan subagent** — fresh Opus agent with design doc path and worktree path (zero design context)
```

**Step 3: Add design-review dispatch block**

Locate the existing draft-plan dispatch code block (the `Agent(` block ending with `Working directory: <absolute-worktree-path>"`). Insert the design-review dispatch block BEFORE it, so the reading order matches the checklist (design-review first, then draft-plan):

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Review the design doc at docs/plans/<folder>/design-<topic>.md
    using the design-review skill.
    Working directory: <absolute-worktree-path>"
)
```

After the design-review dispatch block, add a brief fix-loop note:

```markdown
If design-review finds issues, present them to the user, collaboratively fix the design doc, and re-dispatch design-review until clean. Only dispatch draft-plan after design-review passes.
```

Then the existing draft-plan block follows. The dispatch blocks and fix-loop note should appear in checklist order: design-review dispatch, fix-loop, then draft-plan dispatch.

**Step 4: Update Design Doc Contents section**

Replace the current Design Doc Contents section:

Current:
```markdown
## Design Doc Contents

When writing the design doc (`docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`):
- Include: goal, architecture approach, key decisions, non-goals
- If multi-phase: add **Implementation Approach** section with phase rationale
```

New:
```markdown
## Design Doc Contents

When writing the design doc (`docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`):
- Sections in order: Problem, Goal, Success Criteria, Architecture, Key Decisions, Non-Goals, Implementation Approach
- **Problem** — what's broken, who's affected, consequences of not solving
- **Success Criteria** — human-verifiable behavioral statements (not "tests pass"); collectively complete (all pass = goal met), individually necessary
- If multi-phase: **Implementation Approach** includes phase rationale
```

**Step 5: Verify**

Read the modified file. Confirm checklist numbers 8/9/10 are correct, both dispatch blocks present in order, Design Doc Contents lists all sections with Problem and Success Criteria guidance. Verify word count stays under 1,000.

---

#### A4: Add design-doc field to draft-plan frontmatter

**Files:**
- Modify: `skills/draft-plan/SKILL.md`

**Verification:** Read `skills/draft-plan/SKILL.md` and confirm: (1) plan document structure template's YAML frontmatter includes `design-doc: <path>` field, (2) brief guidance on when to include it

**Done when:** The plan document structure template in draft-plan SKILL.md shows `design-doc: <path>` in the YAML frontmatter, and there is a note explaining that the plan drafter writes this field when a design doc exists.

**Avoid:** Don't modify any other part of draft-plan SKILL.md — this is a minimal addition to the frontmatter template only.

**Step 1: Read current file**

Read `skills/draft-plan/SKILL.md` and locate the plan document structure template (the fenced markdown block showing the plan format with YAML frontmatter).

**Step 2: Update the frontmatter in the template**

In the Plan Document Structure section, find the YAML frontmatter block:

Current:
```markdown
---
status: Not Yet Started
---
```

New:
```markdown
---
status: Not Yet Started
design-doc: docs/plans/YYYY-MM-DD-topic/design-topic.md
---
```

**Step 3: Add guidance note**

After the plan document structure template's closing code fence, the file continues with the Phasing section. Add a one-line note right after the closing fence of the template, before the Phasing section header:

Find the text `## Phasing` and insert before it:

```markdown
Write `design-doc: <path>` in frontmatter when a design doc exists. Downstream skills (plan-review, implementation-review) use this path to verify criteria coverage and fulfillment.

```

**Step 4: Verify**

Read the modified file. Confirm the frontmatter template shows `design-doc:` and the guidance note is present.

---

#### A5: Add Success Criteria Coverage check to plan-review SKILL.md

**Files:**
- Modify: `skills/plan-review/SKILL.md`

**Verification:** Read `skills/plan-review/SKILL.md` and confirm: (1) checklist is now "7-Point Checklist" (was "6-Point"), (2) item 7 is "Success Criteria Coverage", (3) "What It Catches" table has new row for orphaned criteria

**Done when:** plan-review SKILL.md lists a 7-Point Checklist with the 7th check being "Success Criteria Coverage — every criterion in the design doc maps to at least one task's done-when field," and the checklist summary table includes this new entry.

**Avoid:** Don't modify the dispatch section or the existing 6 checks — only add the 7th. Don't expand into sub-checks here (that's for the reviewer-prompt.md in A6). Keep the one-line description format consistent with existing checks 1-6.

**Step 1: Read current file**

Read `skills/plan-review/SKILL.md` to confirm the exact current text.

**Step 2: Update checklist heading**

Change `## 6-Point Checklist` to `## 7-Point Checklist`.

**Step 3: Add 7th check**

After check 6 (`6. **Different Claude Test** — Each task executable by fresh Claude with zero context`), add:

```markdown
7. **Success Criteria Coverage** — Every criterion in the design doc maps to at least one task's "done when" field (skip if no design doc)
```

**Step 4: Update the What It Catches table**

Add a new row to the table after the existing last row:

```markdown
| Orphaned criteria | Design says "users can X" but no task verifies it | Lost during decomposition |
```

**Step 5: Update the assessment reference**

The Output section references issue categories as "(1-6 or Phase)". This doesn't need changing because it's in the reviewer-prompt.md, not in SKILL.md. But verify the assessment table in the Output section — actually, SKILL.md's Output section just says "Issues Found" and "Assessment" without a detailed table. No table to update in SKILL.md.

**Step 6: Verify**

Read the modified file. Confirm "7-Point Checklist" heading, 7th check present, table row added.

---

#### A6: Add Success Criteria Coverage check to plan-review reviewer-prompt.md

**Files:**
- Modify: `skills/plan-review/reviewer-prompt.md`

**Verification:** Read `skills/plan-review/reviewer-prompt.md` and confirm: (1) `## 7-Point Checklist` heading (not 6-Point), (2) a new `### 7. Success Criteria Coverage` section exists between check 6 and the Phase Checks section, (3) it has specific sub-checks and Flag conditions, (4) the assessment table has a new "Success criteria coverage" row, (5) category references updated to "(1-7 or Phase)"

**Done when:** The reviewer prompt contains a 7th check "Success Criteria Coverage" with sub-checks for mapping criteria to tasks' "done when" fields, Flag conditions for orphaned criteria, and the assessment table includes the new row.

**Avoid:** Don't rewrite existing checks 1-6 — only add the new check 7 and update references. The mapping need not be 1:1 (one criterion can be covered by multiple tasks' "done when" fields collectively). Don't flag partially-covered criteria that are genuinely covered across multiple tasks.

**Step 1: Read current file**

Read `skills/plan-review/reviewer-prompt.md` to confirm exact text and locate insertion points.

**Step 2: Update checklist heading in prompt**

Inside the fenced code block, find `## 6-Point Checklist` (line 22 of the current file) and change to `## 7-Point Checklist`.

**Step 3: Add check 7 section**

After the `### 6. Different Claude Test` section (after its last Flag line `- Flag: References conversation context not in plan`) and before `### Phase Checks (multi-phase plans only)`, insert:

```markdown

    ### 7. Success Criteria Coverage (skip if no design doc)
    Read the Success Criteria section from the design doc at {DESIGN_DOC_PATH}.
    For each criterion, verify it maps to at least one task's "Done when" field.

    A criterion is covered if one or more tasks' "done when" fields collectively
    satisfy the criterion's behavioral intent. The mapping need not be 1:1 —
    a criterion like "users can log in" might be covered by Task A2's "login
    endpoint returns JWT" plus Task A3's "login form submits and redirects."

    - Flag: Criterion has no matching "done when" in any task (orphaned)
    - Flag: "Done when" references a criterion but doesn't actually satisfy it
    - Flag: Design doc has Success Criteria section but plan has no tasks covering them
```

**Step 4: Update category reference in Output section**

Find `- **Category** (1-6 or Phase)` and change to `- **Category** (1-7 or Phase)`.

**Step 5: Add assessment table row**

In the Assessment table, after the row `| Different Claude test | PASS/FAIL |`, add:

```markdown
    | Success criteria coverage | PASS/FAIL/SKIP |
```

**Step 6: Verify**

Read the modified file. Confirm "7-Point Checklist" heading in prompt, check 7 present with sub-checks, category reference says "1-7", assessment table has new row.

---

#### A7: Add Success Criteria Fulfillment to implementation-review SKILL.md

**Files:**
- Modify: `skills/implementation-review/SKILL.md`

**Verification:** Read `skills/implementation-review/SKILL.md` and confirm: (1) `{DESIGN_DOC_PATH}` is listed as a template variable, (2) a new category "Success Criteria Fulfillment" appears in the "What It Catches" table, (3) the How to Dispatch variable table includes the new variable

**Done when:** implementation-review SKILL.md lists `{DESIGN_DOC_PATH}` in the variable table with description "Path to design doc (from plan frontmatter, or 'None')", adds "Success Criteria Fulfillment" to the What It Catches table, and notes that this check reads only Goal and Success Criteria sections from the design doc.

**Avoid:** Don't expand the fulfillment check into detailed sub-checks — that belongs in reviewer-prompt.md (A8). Don't modify the existing 7 categories or the dispatch/review flow. Don't change any section except the variable table and the What It Catches table.

**Step 1: Read current file**

Read `skills/implementation-review/SKILL.md` to confirm exact text.

**Step 2: Add variable to dispatch table**

In the "How to Dispatch" section, find the variable table. After the last row (`| {PHASE_CONTEXT} | ... |`), add:

```markdown
| `{DESIGN_DOC_PATH}` | Path to design doc (from plan frontmatter, or "None") |
```

**Step 3: Add category to What It Catches table**

After the last row (`| Missing boundary tests | Components interact but no integration test |`), add:

```markdown
| Unmet success criteria | Design says "users can X" but implementation doesn't deliver it |
```

**Step 4: Verify**

Read the modified file. Confirm new variable row and new category row present.

---

#### A8: Add Success Criteria Fulfillment to implementation-review reviewer-prompt.md

**Files:**
- Modify: `skills/implementation-review/reviewer-prompt.md`

**Verification:** Read `skills/implementation-review/reviewer-prompt.md` and confirm: (1) `{DESIGN_DOC_PATH}` appears as an input variable, (2) a new category 8 "Success Criteria Fulfillment" exists with sub-checks, (3) the output format references categories 1-8, (4) the check reads only Goal and Success Criteria sections

**Done when:** The reviewer prompt includes `{DESIGN_DOC_PATH}` as an input, a new 8th cross-task category "Success Criteria Fulfillment" that reads Goal and Success Criteria from the design doc and verifies each criterion is met by the implementation, with Flag conditions for unmet and partially met criteria.

**Avoid:** Don't rewrite existing categories 1-7. Don't have the fulfillment check evaluate architecture or design decisions — it only checks that behavioral outcomes in Success Criteria are achieved. Make the check skip gracefully when `{DESIGN_DOC_PATH}` is "None".

**Step 1: Read current file**

Read `skills/implementation-review/reviewer-prompt.md` to confirm exact text and locate insertion points.

**Step 2: Add design doc to inputs**

In the reviewer prompt's inputs area, find the `## Phase Context (inter-phase reviews only)` section. Before it, add:

```markdown

    ## Design Doc

    {DESIGN_DOC_PATH}

    If not "None", read ONLY the Goal and Success Criteria sections.
    This check verifies outcomes, not architecture — ignore Architecture,
    Key Decisions, and Implementation Approach sections.
```

**Step 3: Add category 8**

After category 7 (`7. **Inadequate integration test coverage** ...`), before the `## Output Format` section, add:

```markdown

    8. **Success Criteria Fulfillment** (skip if design doc is "None")
       Read the Goal and Success Criteria sections from the design doc.
       For each criterion: does the implementation deliver this outcome?

       - Verify by tracing the criterion to actual code changes in the diff
       - A criterion is "met" if the implementation makes the stated behavior possible
       - A criterion is "partially met" if some but not all aspects are delivered
       - A criterion is "unmet" if no code change addresses it

       - Flag: Criterion with no corresponding implementation (unmet)
       - Flag: Criterion only partially addressed (state what's missing)
       - Flag: Implementation delivers something not covered by any criterion (potential scope creep)
```

**Step 4: Update output format**

In the `### Cross-Task Issues Found` section, change `- **Category** (1-7)` to `- **Category** (1-8)`.

**Step 5: Verify**

Read the modified file. Confirm `{DESIGN_DOC_PATH}` input section present, category 8 with sub-checks, output references 1-8.

---

#### A9: Add design-doc path extraction to orchestrate SKILL.md

**Files:**
- Modify: `skills/orchestrate/SKILL.md`

**Verification:** Read `skills/orchestrate/SKILL.md` and confirm: (1) Per-Phase Execution step 5 mentions extracting `design-doc` from plan frontmatter and passing as `{DESIGN_DOC_PATH}`, (2) the variable is passed when dispatching implementation-review, (3) word count stays under 1,000

**Done when:** orchestrate SKILL.md instructs the orchestrator to extract the `design-doc` path from plan frontmatter and pass it as `{DESIGN_DOC_PATH}` when dispatching implementation-review.

**Avoid:** Don't restructure the orchestrate skill — this is a minimal patch to the implementation-review dispatch step only. Don't add a new top-level section; weave the instruction into the existing Per-Phase Execution flow.

**Step 1: Read current file**

Read `skills/orchestrate/SKILL.md` to confirm exact text of the Per-Phase Execution section, specifically step 5 where implementation-review is dispatched.

**Step 2: Update step 5**

In the Per-Phase Execution section, find step 5:

Current:
```markdown
5. After dispatcher returns:
   - If it reported Rule 4 → ask the user directly and pause execution (see Rule 4 Handling). Do not proceed to implementation-review on partial work.
   - Otherwise → dispatch implementation-review (`skills/implementation-review/reviewer-prompt.md`)
     - BASE_SHA = PHASE_BASE_SHA, HEAD_SHA = `git rev-parse HEAD`
```

New:
```markdown
5. After dispatcher returns:
   - If it reported Rule 4 → ask the user directly and pause execution (see Rule 4 Handling). Do not proceed to implementation-review on partial work.
   - Otherwise → dispatch implementation-review (`skills/implementation-review/reviewer-prompt.md`)
     - BASE_SHA = PHASE_BASE_SHA, HEAD_SHA = `git rev-parse HEAD`
     - DESIGN_DOC_PATH = `design-doc` from plan frontmatter (or "None" if absent)
```

**Step 3: Verify**

Read the modified file. Confirm `DESIGN_DOC_PATH` extraction instruction is present in step 5.

---

#### A10: Register design-review skill in marketplace.json

**Files:**
- Modify: `.claude-plugin/marketplace.json`

**Verification:** Run `python3 -c "import json; d=json.load(open('.claude-plugin/marketplace.json')); plugins={p['name']:p for p in d['plugins']}; assert './skills/design-review' in plugins['claude-caliper']['skills']; assert './skills/design-review' in plugins['claude-caliper-workflow']['skills']; assert './skills/design-review' not in plugins['claude-caliper-tooling']['skills']; assert plugins['claude-caliper']['version'] == '1.2.0'; assert plugins['claude-caliper-workflow']['version'] == '1.2.0'; assert plugins['claude-caliper-tooling']['version'] == '1.2.0'; print('All assertions passed, version: 1.2.0')"` from the repo root — should print success message and not raise AssertionError.

**Done when:** `./skills/design-review` is in the `skills` array of both `claude-caliper` and `claude-caliper-workflow` plugins (not `claude-caliper-tooling`), and version is bumped to `1.2.0` in all three plugin entries.

**Avoid:** Don't add to `claude-caliper-tooling` — design-review is a workflow skill, not a standalone tool. Don't change any other fields in the JSON. Bump all three version fields identically.

**Step 1: Read current file**

Read `.claude-plugin/marketplace.json` to confirm current version (`1.1.0`) and skill arrays.

**Step 2: Add skill to arrays**

In the `claude-caliper` plugin's `skills` array, add `"./skills/design-review"` after `"./skills/design"` (keeping related skills adjacent):

```json
"./skills/design",
"./skills/design-review",
"./skills/draft-plan",
```

In the `claude-caliper-workflow` plugin's `skills` array, add `"./skills/design-review"` after `"./skills/design"`:

```json
"./skills/design",
"./skills/design-review",
"./skills/draft-plan",
```

Do NOT add to `claude-caliper-tooling`.

**Step 3: Bump version**

Change `"version": "1.1.0"` to `"version": "1.2.0"` in all three plugin entries.

**Step 4: Verify**

Run the verification command from the **Verification** field above. Confirm no assertion errors and version shows `1.2.0`.
