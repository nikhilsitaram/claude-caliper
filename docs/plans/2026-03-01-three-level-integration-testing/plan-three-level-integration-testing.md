---
status: Complete (2026-03-01)
---

# Three-Level Integration Testing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Replace the current single-point integration testing (all tests written at implementation-review time) with a three-level approach: broad acceptance tests first (Level 1), narrow boundary tests per-task (Level 2), coverage verification at review (Level 3).

**Architecture:** Changes span 8 skill files in the superpowers repo. Task 1 defines the three-level vocabulary in testing-anti-patterns.md. Tasks 2-3 propagate Level 2 (boundary tests) into the TDD cycle and implementer prompt. Tasks 4-6 propagate Level 1 (Task 0 broad tests) into planning and orchestration skills. Tasks 7-8 shift implementation-review from "write" to "verify." Task 9 adds plan-review validation.

**Tech Stack:** Markdown skill files (no code, no tests — these are instruction documents for AI agents)

---

## Phases

### Phase 1 — Three-Level Integration Testing
**Status:** Complete (2026-03-01)

- [x] Task 1: Define three-level vocabulary in testing-anti-patterns.md
- [x] Task 2: Add boundary tests to TDD skill
- [x] Task 3: Add boundary test instruction to implementer prompt
- [x] Task 4: Add Task 0 convention to writing-plans
- [x] Task 5: Add Task 0 to subagent-driven-development flow
- [x] Task 6: Add Task 0 and verify-not-write to subagent-driven-development
- [x] Task 7: Shift implementation-review from write to verify
- [x] Task 8: Update reviewer prompt for three-level assessment
- [x] Task 9: Add Task 0 validation to plan-review

---

## Task Details

### Task 1: Define three-level vocabulary in testing-anti-patterns.md

**Files:**
- Modify: `skills/test-driven-development/testing-anti-patterns.md:228-249` (Anti-Pattern 5)
- Modify: `skills/test-driven-development/testing-anti-patterns.md:275-282` (Quick Reference table)
- Modify: `skills/test-driven-development/testing-anti-patterns.md:284-292` (Red Flags)

**Verification:** Read the file end-to-end. Three levels clearly defined. Gate function follows established pattern (matches Anti-Patterns 1-4 style). Quick Reference and Red Flags updated.

**Done when:** Anti-Pattern 5 defines Level 1 (broad acceptance tests written FIRST), Level 2 (narrow boundary tests per-task during TDD), Level 3 (verification at implementation review). Gate function exists for boundary test decisions. Quick Reference table has new row. Red Flags has new bullet.

**Avoid:** Don't restructure the entire file — only modify Anti-Pattern 5, Quick Reference, and Red Flags. Don't change Anti-Patterns 1-4.

**Step 1: Rewrite Anti-Pattern 5 (lines 228-249)**

Replace the current Anti-Pattern 5 section with a version that:
- Renames to "Anti-Pattern 5: Integration Tests at the Wrong Time"
- Defines the three levels in a table:
  | Level | What | When | Who |
  |-------|------|------|-----|
  | **Level 1: Broad acceptance tests** | End-to-end tests defining feature "done" | FIRST — before any implementation (Task 0) | Plan author / orchestrator |
  | **Level 2: Narrow boundary tests** | Tests at cross-task seams using real components | During TDD, when task consumes another task's output | Implementer (per-task) |
  | **Level 3: Coverage verification** | Verify Level 1 passes, Level 2 covers seams, fill gaps | At implementation review, after all tasks | Reviewer / orchestrator |
- Shows two violations (bad examples):
  1. All integration tests written after implementation (current anti-pattern)
  2. Only unit tests per task, broad tests at the end
- Shows the fix (good example): Level 1 first, Level 2 during TDD, Level 3 is verification only

**Step 2: Add boundary test gate function (after rewritten Anti-Pattern 5)**

Add a gate function following the same fenced-code-block pattern as Anti-Patterns 1-4:

```
BEFORE completing a task that touches cross-task boundaries:
  Ask: "Does this task import, call, or read data produced by another task?"

  IF yes:
    Write a narrow integration test at the boundary (Level 2)
    Use real components, not mocks
    Follow the same red-green-refactor cycle
    This is part of your TDD, not a separate phase

  IF no cross-task dependency:
    No boundary test needed for this task

  Red flags:
    - "I'll add integration tests later"
    - "The implementation-review will handle integration testing"
    - "Mocking the boundary is good enough"
```

**Step 3: Update Quick Reference table (lines 275-282)**

Add row: `| Integration tests at wrong time | Level 1 first, Level 2 per-task, Level 3 verify |`

**Step 4: Update Red Flags (lines 284-292)**

Add bullet: `- All integration tests deferred to implementation review`
Add bullet: `- No boundary tests at cross-task seams`

**Step 5: Commit**

```bash
git add skills/test-driven-development/testing-anti-patterns.md
git commit -m "feat: define three-level integration testing vocabulary in anti-patterns"
```

---

### Task 2: Add boundary tests to TDD skill

**Files:**
- Modify: `skills/test-driven-development/SKILL.md:354-363` (after "Debugging Integration", before "Testing Anti-Patterns" section)
- Modify: `skills/test-driven-development/SKILL.md:329-339` (Verification Checklist)

**Verification:** Read the file. New "Boundary Tests" section exists between "Debugging Integration" and "Testing Anti-Patterns". Verification Checklist has boundary test checkbox.

**Done when:** New section explains Level 2 boundary tests with a concrete example. Verification Checklist includes boundary test checkbox.

**Avoid:** Don't rewrite existing sections. Don't add language-specific examples — keep them generic (the skill already uses TypeScript examples but the concept is language-agnostic). Don't duplicate the gate function from testing-anti-patterns.md — reference it instead.

**Step 1: Add "Boundary Tests" section after line 356 (after "Debugging Integration")**

Add a new `## Boundary Tests` section that explains:
- When your task consumes output from a prior task (imports, config, API calls), write a narrow integration test at the boundary
- Use real components, not mocks — this IS your TDD cycle, not a separate phase
- The test follows red-green-refactor: write it RED (boundary fails because integration not wired yet), wire the integration to make it GREEN
- Include a concrete example:

```typescript
// Task 2 imports UserService created by Task 1
// Boundary test: verify the real integration works
test('repository queries return users from real database adapter', () => {
  const repo = new UserRepository(new SqliteAdapter(':memory:'));
  repo.save({ id: '1', name: 'Alice' });

  const result = repo.findById('1');

  expect(result.name).toBe('Alice');
});
```

- Reference: "See @testing-anti-patterns.md Anti-Pattern 5 for the full three-level framework and boundary test gate function."

**Step 2: Update Verification Checklist (lines 329-339)**

Add after the last checkbox (before "Can't check all boxes?"):
```markdown
- [ ] If this task consumes cross-task output, boundary integration tests written with real components
```

**Step 3: Update "Testing Anti-Patterns" reference (lines 357-363)**

Add to the bullet list:
```markdown
- Three-level integration testing (when to write broad vs boundary vs verification tests)
```

**Step 4: Commit**

```bash
git add skills/test-driven-development/SKILL.md
git commit -m "feat: add boundary tests (Level 2) to TDD cycle"
```

---

### Task 3: Add boundary test instruction to implementer prompt

**Files:**
- Modify: `skills/subagent-driven-development/implementer-prompt.md:33-38` (Your Job steps)
- Modify: `skills/subagent-driven-development/implementer-prompt.md:63-68` (Self-Review Testing section)

**Verification:** Read the file. New step exists in "Your Job" section. New bullet exists in self-review "Testing" section.

**Done when:** Implementer prompt explicitly instructs boundary testing when task has cross-task dependencies. Self-review asks about boundary tests.

**Avoid:** Don't restructure the entire prompt template. Keep additions concise — implementer subagents have limited context and long prompts get ignored.

**Step 1: Add boundary test step to "Your Job" (after line 33, between current steps 1 and 2)**

Insert a new step 2 (renumber existing 2-6 to 3-7):
```
2. If this task consumes output from a prior task (imports a module, reads config, calls an API created earlier), write a narrow boundary integration test using real components as part of your TDD cycle
```

**Step 2: Add boundary test self-review bullet (after line 67)**

Add under "Testing:" subsection:
```
- If this task touches cross-task boundaries, did I write boundary integration tests using real components (not mocks)?
```

**Step 3: Commit**

```bash
git add skills/subagent-driven-development/implementer-prompt.md
git commit -m "feat: add boundary test instruction to implementer prompt"
```

---

### Task 4: Add Task 0 convention to writing-plans

**Files:**
- Modify: `skills/writing-plans/SKILL.md:37-71` (Plan Document Header template)
- Modify: `skills/writing-plans/SKILL.md:147-163` (Interface-First Task Ordering)
- Insert: `skills/writing-plans/SKILL.md:164` (new section between Interface-First and Remember)
- Modify: `skills/writing-plans/SKILL.md:175-200` (Task Persistence .tasks.json example)

**Verification:** Read the file. Task 0 appears in: (1) header template checklist, (2) new "Broad Integration Tests" section, (3) interface-first ordering, (4) .tasks.json example. All four are consistent.

**Done when:** Plan template includes Task 0 for broad integration tests. New section explains what Task 0 contains, when to skip it, and how stubs work. Interface-first ordering shows Task 0 before contract definitions. .tasks.json example starts at id 0.

**Avoid:** Don't use "Task 0" numbering for single-task plans or plans with no cross-task interactions. Include skip criteria matching existing implementation-review skip criteria. Don't change the fundamental task structure template (Files/Verification/Done when/Avoid/Steps) — Task 0 uses the same structure.

**Step 1: Update Plan Document Header template (lines 37-71)**

In the phase checklist example, add Task 0 before Task 1:
```markdown
- [ ] Task 0: Write failing broad integration tests
- [ ] Task 1: [Task title]
- [ ] Task 2: [Task title]
```

**Step 2: Add "Broad Integration Tests (Task 0)" section after Interface-First Task Ordering (after line 163)**

New section:

```markdown
## Broad Integration Tests (Task 0)

Every multi-task plan MUST include Task 0: failing broad integration tests that define the feature's acceptance criteria in code.

**What Task 0 contains:**
- End-to-end tests that exercise the feature's complete flow
- They import/reference modules that later tasks will create
- Stub files (empty exports, interface-only) so tests compile/parse
- All tests fail (RED) — they define "done," implementation hasn't started yet

**This is the outer loop of double-loop TDD:** Task 0 tests stay RED throughout implementation. They go GREEN when the last piece lands. If they don't go green, the feature isn't done.

**Task 0 follows normal task structure** (Files, Verification, Done when, Steps). Example:

    ### Task 0: Write failing broad integration tests

    **Files:**
    - Create: `tests/integration/test_feature_e2e.py`
    - Create: `src/module_a.py` (stub — empty exports only)
    - Create: `src/module_b.py` (stub — empty exports only)

    **Verification:** `pytest tests/integration/test_feature_e2e.py -v` — all tests FAIL (expected)

    **Done when:** Integration test file exists with 3+ test cases covering the feature's acceptance criteria. All tests fail because implementations are stubs. Stubs compile/parse without errors.

    **Avoid:** Don't implement any real logic in stubs — just enough for tests to parse and fail on assertions, not on import errors.

**Skip Task 0 when:** Single-module change, no cross-task data flow, or purely additive tasks with no interactions (e.g., adding independent utility functions).
```

**Step 3: Update Interface-First Task Ordering (lines 147-163)**

Update the example ordering to include Task 0:
```
Task 0: Write failing broad integration tests        <- acceptance criteria (stays RED)
Task 1: Define UserService interface and types        <- contract
Task 2: Implement UserService against interface       <- implements contract
Task 3: Implement UserRepository against interface    <- implements contract
Task 4: Wire implementations to consumers             <- Task 0 tests go GREEN
```

**Step 4: Update .tasks.json example (lines 175-200)**

Update to start with id 0:
```json
{
  "planFile": "docs/plans/YYYY-MM-DD-topic/plan-topic.md",
  "createdAt": "ISO-8601 timestamp",
  "tasks": [
    {
      "id": 0,
      "title": "Task 0: Write failing broad integration tests",
      "status": "pending",
      "blockedBy": []
    },
    {
      "id": 1,
      "title": "Task 1: Component Name",
      "status": "pending",
      "blockedBy": [0]
    },
    {
      "id": 2,
      "title": "Task 2: Next Component",
      "status": "pending",
      "blockedBy": [1]
    }
  ]
}
```

**Step 5: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat: add Task 0 broad integration test convention to writing-plans"
```

---

### Task 5: Add Task 0 to subagent-driven-development flow

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:40-85` (process flow dot graph)
- Modify: `skills/subagent-driven-development/SKILL.md:96-173` (Example Workflow)

**Verification:** Read the file. Dot graph shows Task 0 node before per-task loop. Example Workflow includes Task 0 as first task with Level 1 tests.

**Done when:** Process flow visualizes Task 0 as the first executed task. Example workflow shows a concrete Task 0 execution (broad tests written, all RED, committed). A brief note after the example explains the three levels.

**Avoid:** Don't restructure the entire dot graph — add the Task 0 node between "Read plan..." and the existing per-task loop entry. Don't make the example workflow significantly longer — keep Task 0 example concise (5-6 lines max). Don't add a separate "Three Levels" section — a brief inline note suffices since the full definition is in testing-anti-patterns.md.

**Step 1: Update process flow dot graph (lines 40-85)**

Add a node after "Read plan, extract all tasks..." and before "TaskList to find next pending task":
```
"Execute Task 0: Broad integration tests (all RED)" [shape=box];
```
Wire it: "Read plan..." → "Execute Task 0..." → "TaskList to find next pending task"

**Step 2: Update Example Workflow (lines 96-173)**

Insert Task 0 before "Task 1: Hook installation script":
```
Task 0: Broad integration tests

[Dispatch implementer subagent for Task 0]
Implementer: Created test_feature_e2e.py with 4 failing tests.
  Created stub files for modules. All tests RED as expected. Committed.

[Spec + code quality review pass]
[Mark Task 0 complete]
```

After the final task (before the implementation-review section), add a note:
```
[Verify Task 0 broad integration tests now pass (GREEN)]
```

**Step 3: Add brief three-level note after the example**

After the example workflow code block ends, add a brief paragraph:
```markdown
**Integration test levels:** Task 0 provides Level 1 (broad acceptance tests, written first). Each implementer writes Level 2 (boundary tests at cross-task seams, during TDD). Implementation-review provides Level 3 (coverage verification). See @testing-anti-patterns.md Anti-Pattern 5 for details.
```

**Step 4: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: add Task 0 to subagent-driven-development flow"
```

---

### Task 6: Add Task 0 and verify-not-write to subagent-driven-development

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:43-52` (Step 2: Execute Batch)
- Modify: `skills/subagent-driven-development/SKILL.md:65-70` (Step 5: Implementation Review)

**Verification:** Read the file. Step 2 mentions Task 0. Step 5 says "verify" not "write."

**Done when:** Step 2 notes that the first batch should include Task 0. Step 5 clarifies that implementation-review verifies existing integration test coverage rather than writing from scratch.

**Avoid:** Don't restructure the entire file. These are two small targeted additions. Don't duplicate the three-level explanation — reference testing-anti-patterns.md.

**Step 1: Update Step 2 (lines 43-52)**

Add a note after "Default: First 3 tasks":
```markdown
**Note:** If the plan includes Task 0 (broad integration tests), it should be in the first batch. Task 0 establishes failing acceptance criteria that go GREEN as later tasks complete.
```

**Step 2: Update Step 5 (lines 65-70)**

Expand the description:
```markdown
### Step 5: Implementation Review

After all tasks complete and verified:
- Verify Task 0 broad integration tests pass (GREEN) — if they don't, the feature isn't done
- **REQUIRED SUB-SKILL:** Use superpowers:implementation-review
- Implementation-review now **verifies** integration test coverage (Level 1 passing, Level 2 boundary tests exist) rather than writing integration tests from scratch
- Fix any cross-task issues found, re-run until clean
```

**Step 3: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: add Task 0 reference and verify-not-write to subagent-driven-development"
```

---

### Task 7: Shift implementation-review from write to verify

**Files:**
- Modify: `skills/implementation-review/SKILL.md:23-43` (process flow dot graph)
- Modify: `skills/implementation-review/SKILL.md:46-56` (Integration Tests section)
- Modify: `skills/implementation-review/SKILL.md:78-87` (What It Catches table)

**Verification:** Read the file. Dot graph says "Verify" not "Write." Integration Tests section is now "Integration Test Verification" with three-level summary. Table row updated.

**Done when:** Section title is "Integration Test Verification (Before Review)." Section explains the three levels and what to check at each. Dot graph node text updated. "What It Catches" table row says "Missing boundary tests" instead of "Missing integration tests."

**Avoid:** Don't rewrite the entire SKILL.md — focus on the three sections listed above. Don't remove the skip criteria ("Skip when...") — keep them. Don't change the reviewer dispatch process or post-review plan doc updates sections.

**Step 1: Update dot graph (lines 23-43)**

Change the node text AND all edge references from the old text to the new text. In Graphviz dot syntax, edges reference nodes by their label string, so all three occurrences must be updated:

Old node text (appears 3 times — once as node definition, twice in edges):
```
"Write integration tests for cross-boundary interactions"
```
New node text (replace in all 3 occurrences):
```
"Verify integration test coverage (Level 1 pass, Level 2 exist, fill gaps)"
```

Specifically update:
- Line 28: the node definition
- Line 36: the edge from "Get HEAD SHA..." to this node
- Line 37: the edge from this node to "Dispatch reviewer subagent..."

**Step 2: Rewrite Integration Tests section (lines 46-56)**

Replace with:

```markdown
## Integration Test Verification (Before Review)

By this point, integration tests should already exist from the implementation phase:

| Level | Source | Expected State |
|-------|--------|----------------|
| **Level 1: Broad acceptance tests** | Task 0 (written before implementation) | Should now PASS (GREEN) |
| **Level 2: Narrow boundary tests** | Per-task TDD (at cross-task seams) | Should PASS |
| **Level 3: This step** | Orchestrator verification | Fill gaps if any |

Before dispatching the reviewer:

1. **Run Level 1 tests** — Task 0's broad integration tests should all pass. If any fail, the feature isn't done. Fix before proceeding.
2. **Spot-check Level 2 tests** — at each cross-task seam, verify a boundary test exists using real components.
3. **Fill gaps** — if boundary tests are missing at a seam, write them now and commit.

**Skip verification when:** Single-module change, no cross-task data flow, or purely additive tasks with no interactions.

The reviewer will then assess whether coverage is adequate across all three levels and flag remaining gaps.
```

**Step 3: Update "What It Catches" table (lines 78-87)**

Change the "Missing integration tests" row to:
```markdown
| Missing boundary tests | Components interact but no Level 2 boundary test at the seam | Per-task reviewer sees one side |
```

**Step 4: Commit**

```bash
git add skills/implementation-review/SKILL.md
git commit -m "feat: shift implementation-review from write to verify integration tests"
```

---

### Task 8: Update reviewer prompt for three-level assessment

**Files:**
- Modify: `skills/implementation-review/reviewer-prompt.md:85-89` (category 7)
- Modify: `skills/implementation-review/reviewer-prompt.md:110-118` (Integration Test Coverage Assessment output)
- Modify: `skills/implementation-review/reviewer-prompt.md:121-125` (Assessment summary)

**Verification:** Read the file. Category 7 references three levels. Output section structured by level. Assessment summary has per-level gap counts.

**Done when:** Reviewer prompt instructs the reviewer to check all three levels explicitly. Output format guides structured assessment by level.

**Avoid:** Don't make the prompt significantly longer — reviewer subagents have limited context. Keep each level's description to 2-3 lines max. Don't change categories 1-6 or the "Critical Rules" section.

**Step 1: Update category 7 (lines 85-89)**

Replace with:
```
7. **Inadequate integration test coverage (three levels)**
   - **Level 1 (broad acceptance tests):** Do they exist from Task 0? Do they all pass?
   - **Level 2 (boundary tests):** At each cross-task seam, is there a test using real components?
   - **Level 3 (gaps):** Are there cross-boundary interactions not covered by Level 1 or 2?
   - Integration tests that mock away the boundaries they should verify
```

**Step 2: Update Integration Test Coverage Assessment output (lines 110-118)**

Replace with:
```
### Integration Test Coverage Assessment

**Level 1 — Broad Acceptance Tests (from Task 0):**
- Exist? [Yes/No]
- All passing? [Yes/No — list failures if any]

**Level 2 — Boundary Tests (from per-task TDD):**
For each cross-task seam:
- **Seam**: [Component A] → [Component B]
- **Test exists?**: Yes/No
- **Uses real components?**: Yes/No

**Level 3 — Gaps:**
- [List any cross-boundary interactions not covered by Level 1 or 2]

If coverage is adequate across all three levels, write "Integration test coverage is adequate — [brief rationale]."
```

**Step 3: Update Assessment summary (lines 121-125)**

Replace:
```
**Integration test gaps:** [count]
```
with:
```
**Integration test gaps:** Level 1: [count], Level 2: [count], Level 3: [count]
```

**Step 4: Commit**

```bash
git add skills/implementation-review/reviewer-prompt.md
git commit -m "feat: update reviewer prompt for three-level integration test assessment"
```

---

### Task 9: Add Task 0 validation to plan-review

**Files:**
- Modify: `skills/plan-review/reviewer-prompt.md:69-77` (category 5: Test-Implementation Coherence)

**Verification:** Read the file. New bullets exist in category 5 (Test-Implementation Coherence) checking for Task 0 presence.

**Done when:** Plan reviewer checks that multi-task plans include Task 0 (broad integration tests) and that the tests reference modules created by later tasks.

**Avoid:** Don't add a full new category — this fits in category 5 (Test-Implementation Coherence). Keep it to 3 bullets. Don't restructure the reviewer prompt. Note: the reviewer prompt is inside a code fence (template), so additions go inside the fenced block.

**Step 1: Add Task 0 check to category 5 (Test-Implementation Coherence, lines 69-77)**

Add after the existing Flag lines in category 5 (after line 77):
```
    Flag: Multi-task plan has no Task 0 (broad integration tests defining acceptance criteria).
    Flag: Task 0 tests don't reference modules that later tasks create.
    Flag: Task 0 is absent with no skip justification (single-module, no cross-task data flow).
```

**Step 3: Commit**

```bash
git add skills/plan-review/reviewer-prompt.md
git commit -m "feat: add Task 0 validation to plan-review"
```

---

## Dependency Graph

```
Task 1 (anti-patterns: vocabulary)
  ├── Task 2 (TDD: boundary tests) ──── Task 3 (implementer prompt)
  ├── Task 4 (writing-plans: Task 0) ── Task 5 (subagent-driven-dev)
  │                                  └── Task 6 (subagent-driven-development)
  └── Task 7 (impl-review: verify) ──── Task 8 (reviewer prompt)
                                    └── Task 9 (plan-review)
```

**Batching:**
- Batch 1: Task 1
- Batch 2: Tasks 2, 4, 7 (parallel — independent after Task 1)
- Batch 3: Tasks 3, 5, 6, 8, 9 (parallel — each depends only on its parent from Batch 2)

## Verification

After all tasks, run the existing integration test to confirm nothing is broken:
```bash
cd /home/nsitaram/personal/superpowers
bash tests/claude-code/run-skill-tests.sh
```

Then manually verify: open each modified skill file and confirm internal consistency (three-level vocabulary matches across all files, Task 0 references are consistent, no contradictions between skills).

## Completion Report — Phase 1: Three-Level Integration Testing

**Completed:** 2026-03-01

### Summary

Replaced the single-point integration testing approach (all tests written at implementation-review time) with a three-level framework: Level 1 broad acceptance tests written first as Task 0, Level 2 narrow boundary tests written per-task during TDD at cross-task seams, and Level 3 coverage verification at implementation review. Changes span 8 skill files across testing anti-patterns, TDD, implementer prompt, writing-plans, subagent-driven-development, implementation-review, reviewer-prompt, and plan-review.

### Deviations from Plan

None — implemented as planned.
