# Implementation Review Prompt Template

Dispatch a fresh-eyes reviewer subagent for the entire feature. Only dispatch after all tasks are complete and per-task reviews have passed.

```text
Agent tool (general-purpose):
  model: "opus"
  mode: "bypassPermissions"
  description: "Fresh-eyes implementation review"
  prompt: |
    You are performing a fresh-eyes review of an entire feature implementation.
    Per-task reviews have passed. Your job: find issues that only become visible
    when looking at ALL tasks together.

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

    Read every file in the diff.

    ## Phase Context (inter-phase reviews only)

    {PHASE_CONTEXT}

    If phase context is provided, this is an inter-phase review (not a final review).
    Pay special attention to:
    - Interface contracts that downstream phases depend on
    - Config, types, or APIs that downstream phases will consume
    - Anything that would be expensive to change after the next phase builds on it

    ## Context

    Read the plan at {PLAN_FILE_PATH} for:
    - What was completed (Summary section)
    - What deviated from the plan and why (Deviations section)

    Intentional deviations documented in the completion report are NOT review issues.

    ## Cross-Task Issue Categories

    Hunt for issues that span task boundaries:

    1. **Cross-task inconsistencies** — values that should match but don't (ports, URLs, defaults), naming drift, contradictory behavior assumptions

    2. **Duplicated code or constants** — same logic under different names, same magic number defined independently, utilities that should be extracted

    3. **Dead code from iteration** — conditionals where both branches do the same thing, functions added but never called, unreachable code paths

    4. **Documentation gaps** — features not wired up, README contradicts behavior, missing limitation explanations

    5. **Inconsistent error handling** — same generic error from multiple locations, errors that don't explain what went wrong

    6. **Integration gaps** — config flags never checked, return values never used, interfaces not implemented where needed

    7. **Inadequate integration test coverage** — missing broad acceptance tests (Level 1), missing boundary tests at cross-task seams (Level 2), tests that mock away the boundaries they should verify

    ## Output Format

    ### Cross-Task Issues Found

    For each issue:
    - **Category** (1-7)
    - **Files** (with line references)
    - **Problem**
    - **Suggested fix**

    ### Integration Test Coverage

    | Level | Status | Notes |
    |-------|--------|-------|
    | L1: Broad acceptance tests | Pass/Fail/Missing | |
    | L2: Boundary tests at seams | Pass/Fail/Missing | List seams without tests |
    | L3: Coverage gaps | None/List | |
    | L4: Cross-phase boundary tests | Pass/Fail/Missing | List interface contracts downstream phases depend on that lack tests |

    If adequate: "Integration test coverage is adequate — [brief rationale]."

    ### Assessment

    **Issues found:** [count] | **Severity:** [Critical/Important/Minor]
    **Ready to merge after fixing?** [Yes/No]
    **Ready for next phase?** [Yes/No] (inter-phase reviews only)

    ### Handoff Notes

    For inter-phase reviews, this is primary output. For final reviews, include if future work exists.

    List what the next implementer needs to know:
    - API/interface differences from plan assumptions
    - New dependencies or config needed
    - Scope changes affecting future phases
    - Interface contracts that downstream phases depend on — flag any without boundary tests

    If nothing: "No handoff notes needed."

    ## Rules

    - Focus exclusively on cross-task and integration issues
    - Be specific: file:line references, not vague suggestions
    - If zero issues found, say so — don't invent problems
    - Read-only review — do not modify files
```
