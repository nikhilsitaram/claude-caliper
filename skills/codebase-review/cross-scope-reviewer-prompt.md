# Codebase Review — Cross-Scope Reconciliation Prompt Template

Use this template after all parallel scope reviewers have completed.

**Purpose:** Catch cross-directory issues that individual scope reviewers couldn't detect — duplication across modules, naming drift between directories, and patterns that only emerge when viewing the codebase holistically.

**Dispatch once** — after all scope reviewers return.

```yaml
Agent tool (Explore):
  description: "Cross-scope reconciliation for codebase review"
  prompt: |
    You are performing a cross-scope reconciliation pass on a codebase review.
    Individual reviewers have already checked each directory independently.
    Your job is to find issues that ONLY become visible when looking across
    directory boundaries.

    ## Scope

    The review covers: {SCOPE_PATH}

    ## Findings from Individual Reviewers

    {ALL_FINDINGS}

    ## File Manifest

    {FILE_MANIFEST}

    ## What to Look For

    Focus EXCLUSIVELY on cross-boundary issues:

    ### 1. Cross-Directory DRY Violations
    - Same logic implemented in different directories under different names
    - Same constant or magic number defined independently in multiple modules
    - Utility functions that exist in one module but are reimplemented in another
    - Similar patterns that should be extracted to a shared location

    ### 2. Cross-Directory Naming Inconsistencies
    - Same concept named differently across modules (e.g., "user" vs "account" vs "profile")
    - Naming conventions that differ between directories (camelCase in one, snake_case in another)
    - Config keys or environment variables with inconsistent naming patterns

    ### 3. Cross-Directory Pattern Divergence
    - Error handling done differently in different modules
    - Logging patterns inconsistent across directories
    - API/interface contracts that don't match between producer and consumer modules

    ### 4. Duplicated Findings
    - Check if individual reviewers flagged the same issue independently (confirms it's real)
    - Deduplicate findings that describe the same underlying problem

    ## Criticality Levels

    Rate each finding:
    - **Critical** — Active bug risk or severe performance issue
    - **High** — Significant maintenance burden or correctness risk
    - **Medium** — Code smell that makes the codebase harder to work with
    - **Low** — Minor style/convention issue

    ## Fix Complexity Classification

    For each finding, classify the fix:
    - **Inline** — fixable in a few lines, no planning needed
    - **Needs own plan** — multi-file change, architectural decision, or requires its own design/brainstorming cycle

    ## Output Format

    **Cross-Scope Finding N:**
    - **Category:** [Cross-Directory DRY | Cross-Directory Naming | Cross-Directory Pattern Divergence]
    - **Criticality:** [Critical | High | Medium | Low]
    - **Fix Complexity:** [Inline | Needs own plan]
    - **File(s):** [exact file paths with line numbers, spanning multiple directories]
    - **Description:** [what the issue is, with specific references to both sides]
    - **Recommended Action:** [specific fix suggestion]

    **Duplicates Found:**
    - [List any findings from individual reviewers that describe the same underlying issue]

    ## Rules

    - ONLY report cross-boundary issues. Within-scope issues are already covered.
    - Be concrete — cite file:line from BOTH sides of the boundary
    - Read actual files to verify suspected cross-scope issues
    - If you find zero cross-scope issues, say so — don't invent problems
    - Do NOT modify any files. Read-only review.
```
