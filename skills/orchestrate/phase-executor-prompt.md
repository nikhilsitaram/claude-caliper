# Phase Executor Prompt Template

Use this template when dispatching a phase executor subagent. Substitute all {VARIABLES} before dispatching. The executor handles all tasks in one phase sequentially — per-task reviews included. Implementation Review (cross-task holistic) is dispatched by the orchestrate context after you return — do not run it yourself.

```text
Task tool (general-purpose):
  model: "sonnet"
  mode: "bypassPermissions"
  description: "Execute Phase {PHASE_NUMBER}: {PHASE_NAME}"
  prompt: |
    You are a phase executor. Your job: implement all tasks for Phase {PHASE_NUMBER}
    using TDD, pass per-task reviews, and write the completion report.

    Implementation Review (cross-task holistic) will be dispatched by the orchestrate
    context after you finish — do not run it yourself.

    ## Plan

    Plan file: {PLAN_FILE_PATH}
    Work from: {REPO_PATH}

    ## Phase {PHASE_NUMBER} — {PHASE_NAME}

    {TASK_LIST}

    [Paste full text of each task in this phase — do not make executor read the file]

    ## Prior Phase Context

    {PHASE_CONTEXT}

    What prior phases built and what this phase is expected to produce for downstream
    phases. Empty for Phase 1.

    ## Your Process

    Work through tasks **sequentially** — parallel writes cause git conflicts.

    For each task:
    1. Dispatch implementer subagent (see `./implementer-prompt.md`)
    2. After implementer returns: dispatch spec compliance reviewer
       (`./spec-reviewer-prompt.md`)
       - Issues found → dispatch implementer fix → re-review spec
    3. After spec passes: dispatch code quality reviewer
       (`./code-quality-reviewer-prompt.md`)
       - Issues found → dispatch implementer fix → re-review quality
    4. Re-Review Gate: if reviewer found >5 issues, dispatch fresh same-scope reviewer
       after all fixes are applied
    5. Update plan doc: `- [ ] Task N` → `- [x] Task N`

    When a task consumes output from a prior task (imports a module, reads config, calls
    an API created earlier), write a boundary integration test using real components — not
    mocks.

    ## Deviation Rules

    | Rule | Trigger | Action |
    |------|---------|--------|
    | 1: Auto-fix bug | Code doesn't work as intended | Fix inline, document |
    | 2: Auto-add critical | Missing validation, auth, error handling | Fix inline, document |
    | 3: Auto-fix blocker | Missing dep, broken import, wrong types | Fix inline, document |
    | 4: STOP | Architectural change (new table, library swap, breaking API) | Stop immediately — report to orchestrate context with: what change is needed, which task triggered it, and why the plan doesn't cover it |

    Only fix issues caused by the current task. Pre-existing issues go to the deferred
    list. After 3 failed fix attempts, stop and document.

    ## When All Tasks Are Done

    Run Task 0 integration tests. Tests targeting future phases can be xfail (note them).
    Failures within this phase's scope are real issues — fix before continuing.

    Write the completion report into the plan doc:

    ---
    ## Completion Report — Phase {PHASE_NUMBER}

    **Date:** YYYY-MM-DD
    **Status:** Phase {PHASE_NUMBER} Complete

    ### Summary
    [2-4 sentences: what was built in this phase]

    ### Deviations
    [Each: Task N — what changed — Rule N applied — reason. "None" if plan followed exactly.]
    ---

    ## Report Back

    Return to orchestrate context:
    - Tasks completed: [list]
    - HEAD SHA: `git rev-parse HEAD`
    - Task 0 integration test status
    - Deviations (if any)
    - Any concerns for the orchestrate context
```
