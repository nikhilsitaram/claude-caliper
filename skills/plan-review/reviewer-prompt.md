# Plan Review Prompt Template

Use this template when dispatching an Opus reviewer subagent to validate a plan before execution.

**Purpose:** Catch internal inconsistencies, design doc mismatches, and missing dependencies before any code gets written.

**Only dispatch after the plan is fully written and saved.**

```
Task tool (general-purpose):
  model: "opus"
  description: "Plan consistency review"
  prompt: |
    You are reviewing an implementation plan BEFORE any code is written.
    Your job: find every inconsistency, missing dependency, and design
    mismatch that would cause problems during implementation.

    ## Plan File

    Read the full plan at: {PLAN_PATH}

    ## Design Doc

    {DESIGN_DOC_PATH}
    (If "None": skip design doc checks, focus on internal consistency only)

    ## Codebase

    The plan targets the codebase at: {REPO_PATH}
    Read existing files as needed to verify paths, imports, and assumptions.

    ## Review Checklist

    Work through each category systematically. For each, read ALL tasks
    in the plan and cross-reference.

    ### 1. Dependency Ordering
    For each task, list what it USES (imports, calls, extends) and what
    it CREATES (files, functions, classes, types). Verify that everything
    a task USES is CREATED by a prior task or already exists in the codebase.

    Flag: Task N uses X, but X is created in Task M where M > N.
    Flag: Task N uses X, but no task creates X and it doesn't exist in the codebase.

    ### 2. File Path Consistency
    Extract every file path mentioned across all tasks. Group by intended
    file. Verify the same file is referenced with the same path everywhere.

    Flag: Same logical file referenced with different paths across tasks.
    Flag: File path in plan doesn't match existing codebase conventions.

    ### 3. Design Doc Alignment (skip if no design doc)
    Compare the plan's scope against the design doc's requirements:
    - Every design doc requirement should map to at least one task
    - Plan's architecture should match design doc's architecture
    - Tech stack should be consistent
    - Data models / schemas should match

    Flag: Design doc specifies X but no task implements it.
    Flag: Plan uses approach A but design doc specifies approach B.

    ### 4. Naming Consistency
    Track every named entity (functions, classes, variables, config keys,
    API endpoints) across all tasks. Verify consistent naming.

    Flag: Same concept with different names in different tasks.
    Flag: Name in test doesn't match name in implementation step.

    ### 5. Test-Implementation Coherence
    For each task that has test steps and implementation steps:
    - Does the test import from the correct path?
    - Does the test call functions with the correct signature?
    - Does the test expect return values consistent with the implementation?
    - Would the test actually fail before implementation (as TDD requires)?

    Flag: Test expects function(a, b) but implementation defines function(a, b, c).
    Flag: Test asserts return value X but implementation returns Y.
    Flag: Multi-task plan has no Task 0 (broad integration tests defining acceptance criteria).
    Flag: Task 0 tests don't reference modules that later tasks create.
    Flag: Task 0 is absent with no skip justification (single-module, no cross-task data flow).

    ### 6. Completeness
    - Does every "Create" file get populated by some task's implementation step?
    - Does every "Modify" file actually exist (check codebase)?
    - Are there tasks that create files but no task ever imports/uses them?
    - Does the plan cover error handling, edge cases, or config that the
      design doc specifies?

    Flag: File listed in "Create" but never populated with code.
    Flag: "Modify: path/to/file.py:123-145" but file doesn't exist or has fewer lines.

    ### 7. Command Correctness
    - Do test commands reference the correct test file paths?
    - Do commit commands stage the right files?
    - Are build/run commands consistent with the project's tooling?

    Flag: `pytest tests/path/test.py` but test file is at different path.
    Flag: `npm test` but project uses `yarn` or `pnpm`.

    ### 8. "Different Claude" Test
    For each task, evaluate: could a fresh Claude instance with ZERO
    conversation history execute this task unambiguously?

    Check each task for:
    - Missing mandatory fields (Files, Verification, Done criteria, Avoid)
    - Implied context not written down ("the function we discussed")
    - Vague references ("update the config", "fix the handler")
    - Missing file paths or partial paths
    - Done criteria that aren't measurable

    Flag: Task N says "modify the auth handler" but doesn't specify which file.
    Flag: Task N has no verification command.
    Flag: Task N's done criteria is "auth works" (not measurable).
    Flag: Task N references context from conversation, not from the plan itself.

    ## Output Format

    ### Issues Found

    For each issue:
    - **Category** (1-7 from above)
    - **Tasks involved** (Task N, Task M)
    - **What's wrong** (specific, with quotes from the plan)
    - **Suggested fix**

    ### Consistency Matrix (summary)

    | Check | Status | Notes |
    |-------|--------|-------|
    | Dependency ordering | PASS/FAIL | |
    | File path consistency | PASS/FAIL | |
    | Design doc alignment | PASS/FAIL/SKIPPED | |
    | Naming consistency | PASS/FAIL | |
    | Test-implementation coherence | PASS/FAIL | |
    | Completeness | PASS/FAIL | |
    | Command correctness | PASS/FAIL | |
    | "Different Claude" test | PASS/FAIL | |

    ### Assessment

    **Issues found:** [count]
    **Severity:** [Critical / Important / Minor for each]
    **Ready for execution?** [Yes / Yes after fixes / No, needs rework]

    ## Critical Rules

    - DO NOT review code style or testing philosophy — this is a consistency check
    - DO trace dependencies across tasks — this is the primary value
    - Be specific: quote the plan, reference task numbers
    - If you find zero issues, say so — don't invent problems
    - DO NOT modify any files. Read-only review.
    - DO check existing codebase files when the plan references them
```
