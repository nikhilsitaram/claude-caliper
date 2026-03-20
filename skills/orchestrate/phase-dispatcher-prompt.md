# Phase Dispatcher Prompt Template

Use this template when dispatching a phase dispatcher subagent. Substitute all {VARIABLES} before dispatching. The dispatcher handles all tasks in one phase sequentially — dispatching implementers and reviewers per task. Implementation Review (cross-task holistic) is dispatched by the orchestrate context after you return — do not run it yourself.

**Variables:**
- `{PHASE_LETTER}` — the phase letter (A, B, C)
- `{PHASE_NAME}` — the phase name
- `{PHASE_TASKS_JSON}` — JSON array of tasks for this phase (from plan.json)
- `{PRIOR_COMPLETIONS}` — concatenated completion.md content from phases in the dependency chain (transitive closure of depends_on). Empty for phases with no dependencies.
- `{PLAN_DIR}` — absolute path to plan directory (for validate-plan calls and cross-phase handoff writes)
- `{PHASE_DIR}` — absolute path to current phase directory (for reading task .md files)
- `{CROSS_PHASE_HANDOFF_TARGETS}` — JSON object mapping source task IDs to arrays of target task file paths in later phases (e.g., {"A2": ["phase-b/b1.md", "phase-c/c1.md"]}). Empty object {} if no cross-phase dependencies.
- `{REPO_PATH}` — phase worktree path (e.g., `.claude/worktrees/<feature>-phase-a`)

```text
Task tool (general-purpose):
  model: "sonnet"
  mode: "auto"
  description: "Dispatch Phase {PHASE_LETTER}: {PHASE_NAME}"
  prompt: |
    You are a phase dispatcher, not an implementer. You never write
    application code, tests, or implementation directly. Your only jobs are:
    dispatching subagents, reading their results, updating the plan doc, and writing
    the completion notes.

    Why: each implementer subagent starts with fresh context, preventing quality
    degradation as tasks accumulate. Each reviewer subagent evaluates code cold,
    without having seen the implementation rationale. These isolation properties
    break if you implement or review inline.

    Implementation Review (cross-task holistic) will be dispatched by the orchestrate
    context after you finish — do not run it yourself.

    ## Plan

    Plan directory: {PLAN_DIR}
    Phase directory: {PHASE_DIR}
    Work from: {REPO_PATH}

    ## Prior Phase Context

    {PRIOR_COMPLETIONS}

    Completion notes from phases in the dependency chain — what was built and any deviations.
    Empty for phases with no dependencies.

    ## Phase {PHASE_LETTER} — {PHASE_NAME}

    Tasks for this phase (JSON):

    ```json
    {PHASE_TASKS_JSON}
    ```

    Cross-phase handoff targets for this phase:

    ```json
    {CROSS_PHASE_HANDOFF_TARGETS}
    ```

    ## Your Process

    Work through tasks **sequentially** — parallel dispatches cause git conflicts.

    For each task in {PHASE_TASKS_JSON}:

    1. **Extract task metadata:**
       - {TASK_METADATA} — the JSON object for this task from {PHASE_TASKS_JSON}
       - Extract task `id` field — this is the TASK_ID used in validate-plan commands and handoff steps below

    2. **Mark task in-progress:**
       ```bash
       bash scripts/validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status in_progress
       ```

    3. **Read task prose:**
       - {TASK_PROSE} — content of {PHASE_DIR}/{task_id_lower}.md
       - Example: for task A1, read {PHASE_DIR}/a1.md

    4. **Capture pre-task SHA:** `TASK_BASE_SHA=$(git rev-parse HEAD)` — needed for code-quality reviewer diff

    5. **Dispatch implementer subagent** (see `./implementer-prompt.md`)
       - Pass both {TASK_METADATA} and {TASK_PROSE} to implementer
       - Include: if this task consumes output from a prior task (imports a module, reads
         config, calls an API created earlier), write a boundary integration test using
         real components — not mocks

    5. **After implementer returns: dispatch task reviewer**
       (`./task-reviewer-prompt.md`)
       - Pass both {TASK_METADATA} and {TASK_PROSE} to reviewer
       - Issues found → dispatch new implementer to fix → re-review

    6. **Re-Review Gate:** if reviewer found >5 issues, dispatch fresh reviewer
       after all fixes are applied

    7. **Mark task complete:**
       ```bash
       bash scripts/validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status complete
       ```

    8. **Run task criteria:**
       ```bash
       bash scripts/validate-plan --criteria {PLAN_DIR}/plan.json --task {TASK_ID}
       ```
       If exit 1: criteria failed. Report failure to orchestrate context with the failing criteria output. Do not proceed to the next task.
       If exit 0: criteria passed (or no criteria defined). Continue.

    9. **Safe commands learning loop:**
       - Read `$TMPDIR/claude-safe-cmds-nonmatch.log` (may not exist if all commands were safe)
       - If the file exists and is non-empty:
         a. Read and deduplicate the command names (one per line in the log)
         b. Ask the user via AskUserQuestion with a numbered list:
            "These commands were not in the safe list and were evaluated by auto
            mode during this task. Enter the numbers of any to permanently add
            to the safe list (comma-separated), or 'none' to skip:
            1. brew
            2. cargo
            3. rustc"
         c. If `~/.claude/safe-commands.txt` does not exist yet, copy the bundled
            defaults from `config/safe-commands.txt` first (so the user file starts
            with the full default list, then user additions build on top)
         d. For each command the user approves, append it to
            `~/.claude/safe-commands.txt` (one per line)
         e. Truncate the log: `> $TMPDIR/claude-safe-cmds-nonmatch.log`
       - If the file doesn't exist or is empty, skip silently

    10. **Handle cross-phase handoffs:**
       - Check if this task ID exists as a key in {CROSS_PHASE_HANDOFF_TARGETS}
       - If yes, iterate each target path in the array and write handoff section to {PLAN_DIR}/{target_path}
       - Format: append after the H1 header, before existing content:
         ```markdown
         ## Handoff from {TASK_ID}

         [Actual details: function signatures, file paths, config keys, APIs created]
         ```

    11. **Handle within-phase handoffs:**
        - For each later task in this phase that lists this task ID in its `depends_on`
        - Write handoff section to {PHASE_DIR}/{target_task_id_lower}.md using the same format as step 10 above (## Handoff from {TASK_ID} section after the H1 header)
        - Example: if A2 depends on A1, write to {PHASE_DIR}/a2.md

    ## Deviation Rules

    When a reviewer or implementer surfaces an issue, triage it:

    | Rule | Trigger | Action |
    |------|---------|--------|
    | 1: Auto-fix bug | Code doesn't work as intended | Dispatch implementer to fix, document |
    | 2: Auto-add critical | Missing validation, auth, error handling | Dispatch implementer to fix, document |
    | 3: Auto-fix blocker | Missing dep, broken import, wrong types | Dispatch implementer to fix, document |
    | 4: STOP | Architectural change (new table, library swap, breaking API) | Stop immediately — report to orchestrate context with: what change is needed, which task triggered it, and why the plan doesn't cover it. Orchestrate will ask the user directly. |

    Only fix issues caused by the current task. Pre-existing issues go to the deferred
    list. After 3 failed fix attempts on the same issue, stop and document.

    ## When All Tasks Are Done

    Run phase integration tests (if broad integration tests exist). Tests targeting future
    phases can be xfail (note them). Failures within this phase's scope are real
    issues — fix before continuing.

    Write {PHASE_DIR}/completion.md:

    ```markdown
    # Phase {PHASE_LETTER} Completion Notes

    **Date:** YYYY-MM-DD
    **Summary:** [2-4 sentences: what was built in this phase]
    **Deviations:** [Each: A1 — what changed — Rule N — reason. "None" if plan followed exactly.]
    ```

    ## Report Back

    Return to orchestrate context:
    - Tasks completed: [list with task IDs, e.g., A1, A2, A3]
    - HEAD SHA: `git rev-parse HEAD`
    - Integration test status
    - Deviations (if any)
    - Any concerns for the orchestrate context
```
