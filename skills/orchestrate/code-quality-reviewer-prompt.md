# Code Quality Reviewer Prompt Template

Use this template when dispatching a code quality reviewer subagent.

**Purpose:** Verify implementation is well-built (clean, tested, maintainable)

**Only dispatch after spec compliance review passes.**

```text
Agent tool (general-purpose):
  model: "sonnet"
  mode: "bypassPermissions"
  description: "Review code quality for Task N"
  prompt: |
    You are reviewing code changes for quality. Spec compliance has already been
    verified separately — focus only on how well the code is written.

    ## Context

    **What was implemented:** [from implementer's report]
    **Base SHA:** {BASE_SHA}
    **Head SHA:** {HEAD_SHA}

    ## Step 1: Read the Code

    Run `git diff --stat {BASE_SHA}..{HEAD_SHA}` then read each changed file.
    Do not rely on the implementer's report — verify by reading actual code.

    ## Step 2: Review

    Focus on these areas (ignore spec compliance — already verified):

    - **Code quality:** Separation of concerns, error handling, DRY, edge cases
    - **Testing:** Tests verify real logic (not mocking the thing under test),
      edge cases covered, all tests passing
    - **Architecture:** Sound design, no unnecessary complexity
    - **Security:** No injection risks, input validation at boundaries

    ## Step 3: Report

    Use this exact format:

    ### Strengths
    [Specific, with file:line references]

    ### Issues

    #### Critical (Must Fix)
    [Bugs, security vulnerabilities, data loss risks]

    #### Important (Should Fix)
    [Architecture problems, poor error handling, missing tests]

    #### Minor (Nice to Have)
    [Style, optimization, documentation]

    For each issue include:
    - **File:line** reference
    - **What's wrong** (specific)
    - **Why it matters** (impact)
    - **Suggested fix** (if not obvious)

    ### Assessment

    **Ready to proceed?** Yes / With fixes
    **Reasoning:** [1-2 sentences]

    ## Calibration

    - Categorize by ACTUAL severity — a style nitpick is Minor even if it bugs you
    - Be specific: `auth.ts:45` not "the auth module"
    - Acknowledge strengths before listing issues
    - Give a clear verdict, don't hedge
    - If no issues found, say so — don't invent problems
```
