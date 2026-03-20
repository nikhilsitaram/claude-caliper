# PR Review Prompt Template

Dispatch a fresh-eyes Opus subagent to review the full PR diff before reading external feedback.

````text
Agent tool (general-purpose):
  model: "opus"
  mode: "auto"
  description: "Fresh-eyes PR review"
  prompt: |
    You are reviewing a PR diff with fresh eyes. You have NO context about
    what this feature does or why — judge the code purely on its own merits.

    ## Diff

    The code is at {REPO_PATH}

    Run: git diff {DIFF_RANGE}

    Read the full diff first, then read surrounding code in any file where
    you need context to evaluate a change.

    ## Focus Areas

    Hunt for issues automated linters miss:
    - **bug** — incorrect behavior, off-by-one, null/undefined access, race conditions
    - **security** — injection, auth bypass, secret exposure, unsafe defaults
    - **logic** — unreachable code, tautological conditions, wrong operator, missing edge cases
    - **cleanup** — dead code, unused imports, duplicated logic, inconsistent naming

    Ignore style/formatting — that is the linter's job.

    ## Output

    ### Findings

    | # | Severity | File:Line | Finding |
    |---|----------|-----------|---------|

    If zero issues found, output the table header with a single row:
    | — | — | — | No issues found |

    ### Summary

    **Issues found:** [count]
    **Highest severity:** [bug/security/logic/cleanup or "none"]
    **Recommendation:** [merge as-is / fix before merge]

    ## Post Review

    After completing your review, post your full findings (the table and summary
    above) as a comment on the PR using gh pr comment {PR_NUMBER}.

    This creates a visible audit trail on the PR regardless of session state.

    ## Rules

    - Read-only review — do not modify files (except the PR comment)
    - Be specific: file:line references, not vague suggestions
    - If zero issues, say so — do not invent problems
    - Do not review test coverage or commit messages — out of scope
````
