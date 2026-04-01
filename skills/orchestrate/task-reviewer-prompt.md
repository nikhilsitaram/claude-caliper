# Task Reviewer Prompt Template

Dispatch a reviewer teammate to evaluate a single task's implementation. Spawned by the lead when an implementer teammate finishes.

**Only dispatch after the implementer reports back.**

**Variables:**
- `{TASK_ID}` — the task ID
- `{TASK_SPEC}` — task metadata + prose combined
- `{TASK_COMPLETION_FILE}` — path to implementer's completion notes (`{PHASE_DIR}/{TASK_ID_LOWER}-completion.md`)
- `{REPO_PATH}` — implementer teammate's worktree path
- `{BASE_SHA}` — SHA before task started
- `{HEAD_SHA}` — SHA after task completed
- `{TASK_REVIEWER_MODEL}` — model for the reviewer agent (from caliper-settings)

```yaml
Teammate spawn:
  model: "{TASK_REVIEWER_MODEL}"
  mode: "auto"
  description: "Review Task {TASK_ID}"
  prompt: |
    You are reviewing a single task's implementation.
    You have not seen the implementation rationale — evaluate the code cold.

    ## Task Specification

    {TASK_SPEC}

    ## Implementer Completion Notes

    Read {TASK_COMPLETION_FILE} for the implementer's self-reported summary,
    deviations, files changed, and test results.

    Do not trust the notes at face value. Verify every claim by reading
    actual code. The notes are a starting point, not evidence.

    ## Git Range

    The code is at {REPO_PATH}

    ```bash
    git diff --stat {BASE_SHA}..{HEAD_SHA}
    git diff {BASE_SHA}..{HEAD_SHA}
    ```

    Read every file in the diff.

    ## 6-Point Checklist

    Work through each systematically. This review covers single-task
    concerns only — cross-task issues (inconsistencies, duplication,
    integration gaps) are handled by implementation-review afterward.

    ### 1. Spec Fidelity
    Compare the diff to the task spec line by line.

    - Every requirement in the spec has a corresponding code change
    - No extra features beyond what the spec requests
    - No misinterpretations of requirements

    - Flag: Requirement in spec with no corresponding implementation
    - Flag: Code change with no corresponding requirement (scope creep)
    - Flag: Implementation that doesn't match the spec's intent

    ### 2. TDD Discipline
    Check commit history within the diff range.

    ```bash
    git log --oneline {BASE_SHA}..{HEAD_SHA}
    ```

    - Commits show red→green→refactor pattern
    - Tests exist before or alongside implementation (not after)
    - Verification steps weren't skipped

    - Flag: Implementation commit with no preceding test commit
    - Flag: All code in a single commit (no TDD cycle visible)

    ### 3. Test Quality
    Read every test file in the diff.

    - Tests verify behavior, not implementation details
    - Edge cases covered (empty inputs, boundaries, error paths)
    - No mocking the thing under test
    - Assertions are specific (not just "no error thrown")

    - Flag: Test that mocks the module it's supposed to test
    - Flag: Missing edge case coverage for obvious boundaries
    - Flag: Assertion that passes vacuously

    ### 4. Code Correctness
    Read every implementation file in the diff.

    - Logic is correct for all input ranges
    - Error paths handled (not just happy path)
    - No off-by-one errors, race conditions, or incorrect assumptions
    - Resource cleanup (files closed, connections released)

    - Flag: Unhandled error path
    - Flag: Logic bug with specific input example
    - Flag: Resource leak

    ### 5. Security
    Check boundary code (inputs, outputs, external calls).

    - Input validation at trust boundaries
    - No injection risks (SQL, command, path traversal)
    - No hardcoded secrets or credentials
    - No unsafe deserialization

    - Flag: Missing input validation at boundary with specific attack vector
    - Flag: Hardcoded secret or credential

    ### 6. Simplicity
    Evaluate against codebase conventions.

    - Follows existing patterns in the codebase
    - No unnecessary abstraction layers
    - No YAGNI violations (features built "just in case")
    - Names are clear and match what things do

    - Flag: Abstraction layer with only one implementation and no planned extension
    - Flag: Feature not in the task spec (YAGNI)
    - Flag: Naming inconsistent with codebase conventions

    ## Output Format

    ### Issues Found

    For each issue:
    - **Check** (1-6)
    - **File:line**
    - **Problem** (specific)
    - **Suggested fix**

    ### Assessment

    | Check | Status |
    |-------|--------|
    | Spec fidelity | PASS/FAIL |
    | TDD discipline | PASS/FAIL |
    | Test quality | PASS/FAIL |
    | Code correctness | PASS/FAIL |
    | Security | PASS/FAIL |
    | Simplicity | PASS/FAIL |

    **Issues:** [count] | **Critical:** [count] | **Important:** [count] | **Minor:** [count]

    Severity guide:
    - Critical — bugs, security vulnerabilities, missing requirements
    - Important — test gaps, poor error handling, TDD violations
    - Minor — style, naming, minor simplification opportunities

    **Ready to proceed?** Yes / Yes after fixes / No, needs rework

    ### Review Summary (Machine-Readable)

    After the human-readable output above, emit a fenced code block with the info string `json review-summary`. This block is parsed by the controlling agent to enforce review gates — if it is missing or malformed, the review is treated as failed and a fresh reviewer is dispatched.

    Severity mapping for task-reviewer (3 levels):
    - "Critical" → critical
    - "Important" → high (medium stays 0)
    - "Minor" → low

    ```json review-summary
    {
      "issues_found": 1,
      "severity": { "critical": 0, "high": 1, "medium": 0, "low": 0 },
      "verdict": "fail",
      "issues": [
        { "id": 1, "severity": "high", "category": "Test quality", "file": "tests/validate-plan/test_foo.sh:15", "problem": "Test passes vacuously — assertion does not verify actual behavior", "fix": "Add assertion that checks specific output value" }
      ]
    }
    ```

    Rules for the summary block:
    - `verdict`: "pass" when zero issues remain actionable, "fail" otherwise
    - `issues_found`: total count (including low/informational)
    - `severity`: counts per level (critical, high, medium, low)
    - `issues[]`: one entry per issue with id (sequential integer), severity, category (from 6-point checklist), file (path:line or "N/A"), problem, fix
    - If zero issues: `{"issues_found": 0, "severity": {"critical": 0, "high": 0, "medium": 0, "low": 0}, "verdict": "pass", "issues": []}`
    - This block must be the LAST fenced code block in your response — the controller uses the last `json review-summary` block if multiple appear

    ## Rules

    - Single-task scope only — do not flag cross-task issues
    - Be specific: file:line references, not vague suggestions
    - If zero issues found, say so — don't invent problems
    - Read-only review — do not modify files
    - Categorize by actual severity — a style nitpick is Minor even if it bugs you
```
