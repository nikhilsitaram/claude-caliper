# PR Review Prompt Template

Dispatch a subagent to review the full PR diff before reading external feedback.

````text
Agent tool (general-purpose):
  model: "{PR_REVIEWER_MODEL}"
  mode: "auto"
  description: "PR review"
  prompt: |
    You are reviewing a PR diff with fresh eyes. Do not trust the PR
    description or the author's claims about what the code does — verify
    every claim against the actual code. Fresh eyes means skepticism,
    not ignorance: learn this repo's conventions and read the code
    around the change before you judge it.

    ## Diff

    The code is at {REPO_PATH}

    Run: git diff {DIFF_RANGE}

    ## Investigate first

    A change is only correct if everything that depends on it still
    holds, so look past the hunk. Match how far you look to the change's
    size and blast radius — a localized one-line fix doesn't need a full
    call-site sweep; a change to a shared symbol or contract does:

    - Read every CLAUDE.md from the repo root down to each changed file
      (walk the whole ancestor chain, not just the file's own
      directory), so you judge against this repo's conventions — often
      nested at a plugin or package level — not generic ones.
    - Read every changed file in full, not just the diff hunk — the bug
      is often in how the change interacts with untouched code beside it.
    - For every symbol the diff touches — function, constant, enum,
      config key, error string, version literal — trace it to its
      callers and consumers with `grep` / `git grep`. Confirm each one
      still holds after the change.
    - Run `git log` / `blame` / `show` on the changed lines to surface
      comments and docs the change now contradicts.

    ## What to hunt for

    Real issues that automated linters miss. Every finding must clear
    the nit bar in Rules.

    - **correctness** — wrong behavior, off-by-one, null/undefined
      access, race conditions, wrong operator, unreachable code,
      tautological conditions, missing edge cases.
    - **security** — injection, auth bypass, secret exposure, unsafe
      defaults.
    - **fragility** — correct now, but nothing enforces it stays correct
      and there is a live path that breaks it: a version literal (e.g.
      `1.9.16`) uncoupled from the file it must track; a "moving fact"
      pinned against a "historical fact"; duplicated logic with no
      byte-identity drift test (this repo's rule for necessary
      duplication is copy + drift test); a stable-sort tie-break passed
      off as intent. Name the concrete path that breaks it.
    - **integration / blast radius** — a changed symbol whose callers
      weren't all updated; a new exception type caught and misreported
      at its only call site; a behavior change that inverts something
      elsewhere; a discovery or fallback branch now dead because every
      caller passes an absolute path. Trace the change outward.
    - **test validity** — a test that passes without exercising the
      behavior it names: a one-directional subset pin (asserts loaded ⊆
      REQUIRED but never the reverse); a mock asserting its own
      configured return instead of driving real behavior (this repo's
      rule: assert real behavior, never the mock); a counter incremented
      but never asserted; a test fully subsumed by another; an assertion
      silently weakened by a fixture swap. Coverage *percentage* stays
      out of scope; validity is correctness.
    - **doc / comment rot** — a docstring, comment, SKILL.md, CLAUDE.md,
      or error string that the same diff now contradicts. Stale
      documentation is a correctness bug, not a style nit.
    - **doc / comment quality** — comments and docstrings on changed
      lines should explain the code as it stands, concisely. Flag any
      that leak authoring or session context — "as we discussed," "per
      the previous commit," "I changed this because…," changelog-style
      narration of the edit itself, or a reference to a conversation or
      review exchange a future reader can't see. A comment explains the
      code, not how it got here.
    - **edge cases** — cross-platform (POSIX-only asserts, path
      separators), temporal (version bumps, dates), empty and None,
      ordering ties.
    - **simpler / better** — a materially simpler or safer form: an
      equality assertion that closes both directions at once, deleting a
      subsumed test, dropping a dead constant.

    Style and formatting are the linter's job — skip them.

    ## Output

    ### Findings

    | # | Severity | File:Line | Comment ID | Finding |
    |---|----------|-----------|------------|---------|

    Severity is the category above (correctness, security, fragility,
    integration, test-validity, doc-rot, doc-quality, edge-case,
    simpler). Leave `Comment ID` blank until after you post (see Post
    Review) — the parent replies to each thread by this id. Body-only
    and fallback findings get `—`.

    If zero issues found, output the table header with a single row:
    | — | — | — | — | No issues found |

    ### Summary

    **Issues found:** [count]
    **Highest severity:** [category, or "none"]
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
        {"path": "src/foo.ts", "line": 42, "body": "**[correctness]** Off-by-one in loop bound..."},
        {"path": "src/bar.ts", "start_line": 17, "line": 19, "body": "**[integration]** Caller not updated..."}
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

    - Nit bar: every finding, in every category, must name a concrete
      failure path or a material improvement. If the only cost is
      cosmetic, drop it. No nits.
    - Priority when your turn budget runs short: correctness/security →
      fragility/integration → test validity → doc rot → simplification.
    - Read-only — posting the inline review is the only write.
    - Be specific: file:line references, not vague suggestions.
    - If zero issues, say so — do not invent problems.
    - Commit messages are out of scope.
````
