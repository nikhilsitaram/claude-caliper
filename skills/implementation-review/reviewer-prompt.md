# Implementation Review Prompt Template

Dispatch a reviewer subagent for the entire feature. Only dispatch after all tasks are complete and per-task reviews have passed.

```text
Agent tool (general-purpose):
  model: "{IMPL_REVIEWER_MODEL}"
  mode: "auto"
  description: "Implementation review"
  prompt: |
    You are performing a review of an entire feature implementation.
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

    ## Design Doc

    {DESIGN_DOC_PATH}

    If not "None", read ONLY the Goal and Success Criteria sections.
    This check verifies outcomes, not architecture — ignore Architecture,
    Key Decisions, and Implementation Approach sections.

    ## Phase Context (inter-phase reviews only)

    {PHASE_CONTEXT}

    If phase context is provided, this is an inter-phase review (not a final review).
    Pay special attention to:
    - Interface contracts that downstream phases depend on
    - Config, types, or APIs that downstream phases will consume
    - Anything that would be expensive to change after the next phase builds on it

    ## Context

    Read the plan at {PLAN_DIR}/plan.json for:
    - Task metadata: files created/modified, verification commands, done_when criteria

    Read {PHASE_DIR}/completion.md for:
    - What was completed (Summary)
    - What deviated from the plan and why (Deviations)

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

    ## Output Format

    ### Cross-Task Issues Found

    For each issue:
    - **Category** (1-8)
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

    ### Review Summary (Machine-Readable)

    After the human-readable output above, emit a fenced code block with the info string `json review-summary`. This block is parsed by the controlling agent to enforce review gates — if it is missing or malformed, the review is treated as failed and a fresh reviewer is dispatched.

    Severity mapping for implementation-review (3 levels):
    - "Critical" → critical
    - "Important" → high (medium stays 0)
    - "Minor" → low

    ```json review-summary
    {
      "issues_found": 2,
      "severity": { "critical": 0, "high": 1, "medium": 0, "low": 1 },
      "verdict": "fail",
      "issues": [
        { "id": 1, "severity": "high", "category": "Cross-task inconsistencies", "file": "src/api.ts:42", "problem": "Port 8080 used here but 3000 in config.ts:7", "fix": "Read port from config in all files" }
      ]
    }
    ```

    Rules for the summary block:
    - `verdict`: "pass" when zero issues remain actionable, "fail" otherwise
    - `issues_found`: total count (including low/informational)
    - `severity`: counts per level (critical, high, medium, low)
    - `issues[]`: one entry per issue with id (sequential integer), severity, category (from cross-task category list), file (path:line or "N/A"), problem, fix
    - If zero issues: `{"issues_found": 0, "severity": {"critical": 0, "high": 0, "medium": 0, "low": 0}, "verdict": "pass", "issues": []}`
    - This block must be the LAST fenced code block in your response — the controller uses the last `json review-summary` block if multiple appear

    ## Rules

    - Focus exclusively on cross-task and integration issues
    - Be specific: file:line references, not vague suggestions
    - If zero issues found, say so — don't invent problems
    - Read-only review — do not modify files
```
