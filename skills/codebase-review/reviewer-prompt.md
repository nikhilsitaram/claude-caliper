# Codebase Review — Scope Reviewer Prompt Template

Use this template when dispatching parallel Explore subagents for each review unit.

**Purpose:** Review a single directory/module for code quality issues across all 5 categories.

**Dispatch one per review unit** — all run in parallel.

```
Agent tool (Explore):
  description: "Review {SCOPE_PATH} for code quality"
  prompt: |
    You are reviewing the code in {SCOPE_PATH} for quality issues.

    ## Your Scope

    Review ALL files under {SCOPE_PATH}. Read every file.
    Focus on finding concrete issues, not theoretical concerns.

    ## Categories to Check

    Check for issues in each of these categories:

    ### 1. DRY (Don't Repeat Yourself)
    - Duplicated code blocks (same or near-identical logic in multiple places)
    - Repeated constants or magic numbers
    - Copy-pasted logic with minor variations that should be a shared function

    ### 2. YAGNI (You Aren't Gonna Need It)
    - Unused exports, functions, or classes:
      - Only flag as confirmed unused if you can verify no references in the reviewed scope
      - Otherwise flag as **candidate unused** and note that repo-wide verification is needed
    - Dead code paths (unreachable branches, commented-out code)
    - Speculative features or unnecessary config options
    - Over-parameterized functions where only one call pattern is ever used

    ### 3. Simplicity & Efficiency
    - Over-abstracted code (wrapper functions that add no value, unnecessary indirection layers)
    - Verbose implementations that could be significantly simpler
    - Premature generalization (generic framework for a single use case)
    - Redundant operations (read-then-read-again, unnecessary loops)
    - Suboptimal data structures or algorithms where better options are obvious

    ### 4. Refactoring Opportunities
    - Functions doing too much (SRP violations)
    - Deep nesting (3+ levels of conditionals/loops)
    - Long parameter lists (5+ parameters)
    - God objects (classes/modules with too many responsibilities)
    - Missing abstractions that would simplify multiple callers

    ### 5. Consistency
    - Naming drift (camelCase vs snake_case mixed within the scope)
    - Inconsistent error handling patterns
    - Style divergence between files in the same module

    ## Criticality Levels

    Rate each finding:
    - **Critical** — Active bug risk or severe performance issue
    - **High** — Significant maintenance burden or correctness risk
    - **Medium** — Code smell that makes the codebase harder to work with
    - **Low** — Minor style/convention issue

    ## Fix Complexity Classification

    For each finding, classify the fix:
    - **Inline** — fixable in a few lines within this scope, no planning needed
    - **Needs own plan** — multi-file change, architectural decision, or requires its own design/brainstorming cycle

    ## Output Format

    Return findings as a structured list. For each finding:

    **Finding N:**
    - **Category:** [DRY | YAGNI | Simplicity & Efficiency | Refactoring Opportunities | Consistency]
    - **Criticality:** [Critical | High | Medium | Low]
    - **Fix Complexity:** [Inline | Needs own plan]
    - **File(s):** [exact file paths with line numbers]
    - **Description:** [what the issue is, concretely]
    - **Recommended Action:** [specific fix suggestion]

    ## Rules

    - Be concrete — cite file:line, not vague descriptions
    - Only report real issues you can point to in the code
    - Do NOT invent problems to fill the report
    - If you find zero issues in a category, say "No issues found" for that category
    - Do NOT modify any files. Read-only review.
```
