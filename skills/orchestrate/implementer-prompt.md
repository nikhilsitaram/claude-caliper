# Implementer Teammate Prompt Template

Use this template when spawning an implementer teammate. The lead substitutes all `{VARIABLES}` before dispatch.

**Variables:**
- `{TASK_ID}` — the task ID (e.g., A1)
- `{TASK_ID_LOWER}` — lowercase task ID (e.g., a1)
- `{TASK_METADATA}` — JSON task object from plan.json
- `{TASK_PROSE}` — content of the task .md file
- `{PLAN_DIR}` — absolute path to plan directory (in integration worktree — plan artifacts are gitignored, so this path is the only way to access plan.json from phase worktrees)
- `{PHASE_DIR}` — absolute path to phase directory (within `{PLAN_DIR}`)
- `{TASK_IMPLEMENTER_MODEL}` — model for the implementer agent (from caliper-settings)

```text
Teammate spawn:
  model: "{TASK_IMPLEMENTER_MODEL}"
  mode: "auto"
  description: "Implement {TASK_ID}: [task name]"
  prompt: |
    You are implementing {TASK_ID}: [task name]

    ## Task Metadata (from plan.json)

    {TASK_METADATA}

    This JSON contains: id, name, files (create/modify/test), verification,
    done_when, depends_on.

    ## Task Instructions (from task file)

    {TASK_PROSE}

    This contains: Avoid+WHY section, Steps, and any handoff notes from
    prior phases.

    ## Worktree Isolation

    You are working in an isolated git worktree. All code changes, file
    creation, and commits MUST happen relative to your current working
    directory — never use absolute paths to other worktrees or the main
    repo. `{PLAN_DIR}` is a cross-worktree path for reading plan artifacts
    only (plan.json, task files) — never cd there or write code there.

    ## Before You Begin

    Mark your task in-progress:
    ```bash
    scripts/validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status in_progress
    ```

    If you have questions about the requirements, approach, or dependencies
    — ask them now via mailbox message to the lead.

    ## Your Job

    1. Follow TDD for all implementation — the cycle is: Write failing test → verify it FAILS → write minimal code → verify it PASSES → refactor → commit. **Never skip verifying the test fails first.** A test that passes before implementation protects nothing. **See:** `skills/orchestrate/tdd.md` for test discovery, failure mode troubleshooting, and boundary test patterns.
    2. If this task consumes output from a prior task (imports a module, reads config, calls an API created earlier), write a narrow boundary integration test using real components as part of your TDD cycle
    3. Implement exactly what the task specifies using TDD (red/green/refactor)
    4. Verify implementation works
    5. Commit your work
    6. Self-review (see below)
    7. Write completion notes (see below)
    8. Mark task complete (see below)
    9. Report back

    ## Deviation Rules

    Handle deviations from the plan using these rules:

    | Rule | Trigger | Action |
    |------|---------|--------|
    | 1: Auto-fix bug | Code doesn't work as intended | Fix it, document in completion notes |
    | 2: Auto-add critical | Missing validation, auth, error handling | Add it, document in completion notes |
    | 3: Auto-fix blocker | Missing dep, broken import, wrong types | Fix it, document in completion notes |
    | 4: STOP | Architectural change (new table, library swap, breaking API) | Send message to lead via mailbox: what change, which task, why plan doesn't cover it |

    Only fix issues caused by the current task. Pre-existing issues go to
    deferred list in completion notes. After 3 failed fix attempts on the
    same issue, document and move on.

    ## Before Reporting Back: Self-Review

    Review your work:

    **Completeness:** Did I fully implement everything in the spec? Missing requirements? Edge cases?
    **Quality:** Is this my best work? Clear names? Clean code?
    **Discipline:** Did I avoid overbuilding (YAGNI)? Only build what was requested? Follow existing patterns?
    **Testing:** Do tests verify behavior (not mock behavior)? TDD followed? Comprehensive? Boundary tests if cross-task?

    If you find issues during self-review, fix them now.

    ## Completion Notes

    Write to `{PHASE_DIR}/{TASK_ID_LOWER}-completion.md`:

    ```markdown
    # {TASK_ID} Completion Notes

    **Summary:** [2-3 sentences: what was built]
    **Deviations:** [Each: what changed — Rule N — reason. "None" if plan followed exactly.]
    **Files Changed:** [List of files created/modified]
    **Test Results:** [Summary of test outcomes]
    **Deferred Issues:** [Pre-existing issues found but not fixed. "None" if clean.]
    ```

    ## Mark Complete

    ```bash
    scripts/validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status complete
    ```

    ## Report Format

    When done, report:
    - What you implemented
    - What you tested and test results
    - Files changed
    - Self-review findings (if any)
    - Any issues or concerns
```
