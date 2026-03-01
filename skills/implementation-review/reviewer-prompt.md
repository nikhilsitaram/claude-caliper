# Implementation Review Prompt Template

Use this template when dispatching a fresh-eyes reviewer subagent for the entire feature.

**Purpose:** Catch cross-task issues that per-task reviews miss — inconsistencies, duplication, dead code, documentation gaps.

**Only dispatch after all tasks are complete and their individual reviews have passed.**

```
Task tool (general-purpose):
  model: "opus"
  description: "Fresh-eyes implementation review"
  prompt: |
    You are performing a fresh-eyes review of an entire feature implementation.
    Per-task spec and code quality reviews have already passed. Your job is different:
    find issues that only become visible when looking at ALL tasks together.

    ## Feature Summary

    {FEATURE_SUMMARY}

    ## Tasks Implemented

    {TASK_LIST}

    ## Git Range

    The code is at {REPO_PATH}

    ```bash
    git diff --stat {BASE_SHA}..{HEAD_SHA}
    git diff {BASE_SHA}..{HEAD_SHA}
    ```

    Review ALL files in the diff. Read every file that was changed.

    ## Completion Report

    The orchestrator has written a completion report for this phase in the plan document.
    Read the plan file at {PLAN_FILE_PATH} to understand:
    - What was completed (Summary section)
    - What deviated from the plan and why (Deviations section)

    Use this context to distinguish intentional deviations from accidental inconsistencies.
    An intentional deviation documented in the completion report is NOT a review issue.

    ## Your Focus: Cross-Task Issues

    Per-task reviewers already checked code quality, test coverage, and spec compliance
    for each task individually. You are looking for what they CANNOT see — issues that
    span task boundaries.

    **Actively hunt for these categories:**

    1. **Cross-task inconsistencies**
       - Values that should match but don't (ports, URLs, defaults, config keys)
       - Naming conventions that drift between tasks
       - Behavior assumptions that contradict across modules

    2. **Duplicated code or constants**
       - Same logic implemented in multiple files under different names
       - Same magic number or constant defined independently
       - Shared utilities that should be extracted

    3. **Dead code from incremental development**
       - Conditionals where both branches do the same thing
       - Functions that were added early but never called
       - Code paths made unreachable by later tasks

    4. **Documentation gaps**
       - Features supported in one module but not wired up in another
       - README/docs that contradict actual behavior
       - Missing explanation of intentional limitations

    5. **Inconsistent error handling**
       - Same generic error message from multiple locations
       - Error messages that don't explain what the user did wrong
       - Missing error context (status codes, input values, expected formats)

    6. **Integration gaps**
       - Config flags defined but never checked
       - Return values computed but never used by callers
       - Interfaces defined in one task but not implemented where needed

    7. **Inadequate integration test coverage**
       - Cross-boundary interactions that the integration tests don't cover
       - Integration tests that mock away the very boundaries they should verify
       - Data flows through multiple modules where the integration test only checks part of the path
       - Configuration consumed by multiple modules with no test that validates the full path

    ## How to Review

    1. Read the full diff to understand the feature as a whole
    2. For each file, note what it exports and what other files consume
    3. Cross-reference: do producers and consumers agree on types, values, behavior?
    4. Look for patterns that repeat across files (duplication signal)
    5. Check documentation against actual implementation

    ## Output Format

    ### Cross-Task Issues Found

    For each issue:
    - **Category** (from the 7 above)
    - **Files involved** (with line references)
    - **What's wrong**
    - **Why per-task review missed it**
    - **Suggested fix**

    ### Integration Test Coverage Assessment

    Review the integration tests that were written before this review.
    For each cross-boundary interaction in the feature:
    - **Interaction**: Which components/modules connect
    - **Covered?**: Yes/No — is there an integration test for this?
    - **If gap**: What's missing and why it matters

    If integration test coverage is adequate, write "Integration test coverage is adequate — [brief rationale]."

    ### Assessment

    **Issues found:** [count]
    **Integration test gaps:** [count]
    **Severity:** [Critical / Important / Minor for each]
    **Ready to merge after fixing these?** [Yes/No]

    ### Handoff Notes for Next Phase (if multi-phase)

    If this is a multi-phase plan and there are future phases, list anything
    the next phase's implementer needs to know:
    - API/interface shapes that differ from what the plan assumed
    - New dependencies or config that future phases will need
    - Scope changes that affect future phase planning

    If nothing to hand off, write "No handoff notes needed."

    ## Critical Rules

    - DO NOT re-review per-task concerns (code style, individual test coverage)
    - DO focus exclusively on cross-task and integration issues
    - Be specific: file:line references, not vague suggestions
    - If you find zero cross-task issues, say so — don't invent problems
    - DO NOT modify any files. Read-only review.
```
