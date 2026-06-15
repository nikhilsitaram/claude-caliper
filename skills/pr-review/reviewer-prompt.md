# PR Review Prompt Template

Dispatch a subagent to review the full PR diff before reading external feedback.

````text
Agent tool (general-purpose):
  model: "{PR_REVIEWER_MODEL}"
  mode: "auto"
  description: "PR review"
  prompt: |
    You are reviewing a PR diff. You have NO context about
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

    | # | Severity | File:Line | Comment ID | Finding |
    |---|----------|-----------|------------|---------|

    Leave `Comment ID` blank until after you post (see Post Review) —
    the parent replies to each thread by this id. Body-only and
    fallback findings get `—`.

    If zero issues found, output the table header with a single row:
    | — | — | — | — | No issues found |

    ### Summary

    **Issues found:** [count]
    **Highest severity:** [bug/security/logic/cleanup or "none"]
    **Recommendation:** [merge as-is / fix before merge]

    ## Post Review

    Post each finding as an inline review comment on the specific file
    and line via the GitHub reviews API. Each finding becomes a
    separately-resolvable thread, so a follow-up wave can dismiss
    individual items without re-touching unrelated ones.

    From {REPO_PATH}, build one JSON payload of this shape covering every
    finding (write it to a tmp file using whatever method handles your
    finding-body escaping safely — e.g., `jq -n`, `python -c`, or a
    column-0 heredoc):

    {
      "commit_id": "{HEAD_SHA}",
      "event": "COMMENT",
      "body": "<Summary section: counts, severity, recommendation>",
      "comments": [
        {"path": "src/foo.ts", "line": 42, "body": "**[bug]** Off-by-one in loop bound..."},
        {"path": "src/bar.ts", "start_line": 17, "line": 19, "body": "**[logic]** Branch unreachable..."}
      ]
    }

    Then POST it:

    gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
      --method POST --input <path-to-json>

    The `{owner}` and `{repo}` placeholders are filled by gh from the
    current repo, so run from {REPO_PATH}. `commit_id` is pinned to the
    SHA pr-review captured when dispatching this review, so the line
    numbers in your comments stay valid even if a wave-1 fix pushes
    while you're running.

    The POST response is the review object (its `.id`), not the line
    comments. Fetch them and map each back to a finding by path+line so
    the parent can reply to the exact thread:

    gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews/<review_id>/comments

    Fill the `Comment ID` column of your Findings table from each
    comment's `.id`. Body-only and fallback findings keep `—`.

    Inline-comment rules:
    - `path` is repo-root-relative (matches the diff header)
    - `line` is the line in the file's new content (RIGHT side); add
      `"side": "LEFT"` only when commenting on deleted code
    - Multi-line range: set `start_line` and `line` (end) on the same side
    - Line must be inside a diff hunk. If a finding can't anchor to a
      changed line, list it in the review `body` instead of as an inline
      comment
    - Zero findings: post a review with `body: "No issues found"` and
      `comments: []`
    - If the API rejects the payload (e.g., 422 line-not-in-diff), fall
      back to a single `gh pr comment {PR_NUMBER}` containing the full
      Findings table

    The same findings still appear in your Findings table above — the
    table is what the parent uses for wave dedupe.

    ## Rules

    - Read-only — posting the inline review is the only write
    - Be specific: file:line references, not vague suggestions
    - If zero issues, say so — do not invent problems
    - Do not review test coverage or commit messages — out of scope
````
