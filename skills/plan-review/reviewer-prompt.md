# Plan Review Prompt Template

Dispatch an Opus reviewer subagent to validate a plan before execution.

**Only dispatch after the plan is fully written and saved.**

```yaml
Agent tool (general-purpose):
  model: "opus"
  description: "Plan consistency review"
  prompt: |
    You are reviewing an implementation plan BEFORE any code is written.
    Find every inconsistency, missing dependency, and design mismatch
    that would cause problems during implementation.

    ## Inputs

    **Plan:** {PLAN_PATH}
    **Design doc:** {DESIGN_DOC_PATH} (if "None", skip design checks)
    **Codebase:** {REPO_PATH} (read existing files to verify paths/imports)

    ## 7-Point Checklist

    Work through each systematically. Read ALL tasks and cross-reference.

    ### 1. Dependency Ordering
    For each task, list what it USES (imports, calls, extends) and CREATES
    (files, functions, types). Verify everything USED is CREATED earlier
    or exists in codebase.

    - Flag: A2 uses X, but X created in A3 (later task)
    - Flag: A2 uses X, but nothing creates X and it doesn't exist
    - Flag: B1 consumes output from Phase A but has no handoff placeholder

    ### 2. Artifact Consistency
    Extract every file path, function name, and variable across all tasks.
    Verify the same artifact is referenced consistently everywhere.

    - Flag: Same file with different paths (`utils.ts` vs `helpers.ts`)
    - Flag: Same concept with different names (`UserService` vs `userService`)
    - Flag: Path doesn't match codebase conventions

    ### 3. Design Doc Alignment (skip if no design doc)
    Compare plan scope against design requirements:
    - Every requirement maps to at least one task
    - Architecture matches (REST vs GraphQL, etc.)
    - Tech stack consistent
    - Data models match

    - Flag: Design specifies X but no task implements it
    - Flag: Plan uses approach A but design specifies B

    ### 4. Test-Implementation Coherence
    For each task with test steps:
    - Test imports from correct path?
    - Function signatures match between test and implementation?
    - Return values consistent?
    - TDD 5-step cycle present? (write fail, verify fail, implement, verify pass, commit)

    For multi-task plans with cross-task data flow:
    - First task (e.g., A1) as broad integration tests present?
    - Integration tests reference modules that later tasks create?
    - Skip justification if no broad tests? (single-module, no cross-task flow)

    - Flag: Test expects `fn(a, b)` but implementation defines `fn(a, b, c)`
    - Flag: Multi-task plan with cross-task flow missing broad integration tests

    ### 5. Completeness
    Verify every task (format: `#### A1: [name]`) has all 5 required fields:

    | Field | Check |
    |-------|-------|
    | Files | Exact paths (create/modify/test) — not "the auth files" |
    | Verification | Runnable command <60s — not "check it works" |
    | Done when | Measurable — not "authentication complete" |
    | Avoid + WHY | Pitfall with reasoning — not just "don't use X" |
    | Steps | TDD cycle with actual code — not "add validation" |

    Verify plan structure:
    - Each phase has three subsections: `### Phase X Checklist`, `### Phase X Completion Notes`, `### Phase X Tasks`
    - Completion notes section exists with placeholder comment
    - Task headers use `#### A1: [name]` format (letter+number)
    - Tasks within each phase use correct letter prefix (Phase A → A1, A2; Phase B → B1, B2)

    Also verify:
    - Commands reference correct file paths
    - Commands match project tooling (npm vs yarn vs pnpm)
    - Every "Create" file gets populated
    - Every "Modify" file exists in codebase

    - Flag: Task missing required field
    - Flag: Phase missing Checklist, Completion Notes, or Tasks subsection
    - Flag: Task uses wrong letter prefix for its phase
    - Flag: `pytest tests/path.py` but file at different path
    - Flag: File in "Modify" doesn't exist or wrong line range

    ### 6. Different Claude Test
    For each task: Could a fresh Claude with ZERO conversation history
    execute this task unambiguously?

    Check for:
    - Vague references ("the handler", "the config")
    - Missing file paths or partial paths
    - Context from conversation not written in plan
    - Done criteria that aren't measurable

    - Flag: "modify the auth handler" without specifying file
    - Flag: Done says "auth works" (not measurable)
    - Flag: References conversation context not in plan

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

    ### Phase Checks (multi-phase plans only)
    If plan has multiple phases:
    - Phase boundaries at meaningful verification points?
    - Each phase ends with verification task?
    - Phase rationale sentence present? (format: `**Status:** Not Started | **Rationale:** ...`)
    - Complexity gates: 8+ tasks in single-phase → should have phases
    - Complexity gates: 7+ tasks per phase → examine cut points
    - Interface-first: Contracts defined before implementations?
    - Inline handoff placeholders exist on tasks that consume output from prior phases?
    - Handoff placeholders reference valid task IDs from the producing phase?

    - Flag: 10 tasks with no phases
    - Flag: Phase B task consumes Phase A output but has no `> **Handoff from A2:** [TBD]` placeholder
    - Flag: Handoff placeholder references non-existent task ID
    - Flag: Phase B starts without Phase A verification complete

    ## Output

    ### Issues Found

    For each issue:
    - **Category** (1-7 or Phase)
    - **Tasks** (which tasks involved)
    - **Problem** (specific, quote the plan)
    - **Fix** (what to change)

    ### Assessment

    | Check | Status |
    |-------|--------|
    | Dependency ordering | PASS/FAIL |
    | Artifact consistency | PASS/FAIL |
    | Design doc alignment | PASS/FAIL/SKIP |
    | Test-implementation coherence | PASS/FAIL |
    | Completeness | PASS/FAIL |
    | Different Claude test | PASS/FAIL |
    | Success criteria coverage | PASS/FAIL/SKIP |
    | Phase boundaries | PASS/FAIL/N/A |

    **Issues:** [count]
    **Severity:** Critical (blocks execution) / High (likely causes failure) / Medium (may cause confusion) / Low (cosmetic)
    **Ready for execution?** Yes / Yes after fixes / No, needs rework

    ## Rules

    - This is a CONSISTENCY check, not a code style review
    - Trace dependencies across tasks — this is the primary value
    - Be specific: quote plan text, reference task IDs (A1, B2, etc.)
    - If zero issues, say so — don't invent problems
    - READ-ONLY: Do not modify any files
    - DO check codebase when plan references existing files
```
