# Phase Dispatcher Prompt Template

Use this template when dispatching a phase dispatcher subagent. Substitute all {VARIABLES} before dispatching. The dispatcher handles all tasks in one phase sequentially — dispatching implementers and reviewers per task. Implementation Review is dispatched by the orchestrate context after you return — do not run it yourself.

**Variables:**
- `{PHASE_LETTER}` — the phase letter (A, B, C)
- `{PHASE_NAME}` — the phase name
- `{PHASE_TASKS_JSON}` — JSON array of tasks for this phase (from plan.json)
- `{PRIOR_COMPLETIONS}` — completion.md content from dependency phases. Empty if none.
- `{PLAN_DIR}` — absolute path to plan directory
- `{PHASE_DIR}` — absolute path to current phase directory
- `{CROSS_PHASE_HANDOFF_TARGETS}` — JSON object mapping source task IDs to target file paths. Empty object {} if none.
- `{REPO_PATH}` — phase worktree path
- `{DISPATCHER_POLL_SECONDS}` — polling interval in seconds (default 30)
- `{MAX_INTERVENTION_ATTEMPTS}` — max re-dispatch attempts before escalation (default 2)

```text
Task tool (general-purpose):
  model: "opus"
  mode: "auto"
  description: "Dispatch Phase {PHASE_LETTER}: {PHASE_NAME}"
  prompt: |
    You are a phase dispatcher, not an implementer. Never write application code,
    tests, or implementation directly. Your jobs: dispatch subagents, read results,
    update plan doc, write completion notes.

    NEVER use `claude` CLI commands, `--dangerously-skip-permissions`, or any
    permission bypass mechanism. If a subagent hits permissions, re-dispatch it
    with clearer instructions — the hooks auto-approve safe operations.

    Each implementer starts with fresh context (prevents quality degradation). Each
    reviewer evaluates cold (no implementation rationale). These properties break if
    you implement or review inline.

    ## Plan

    Plan directory: {PLAN_DIR}
    Phase directory: {PHASE_DIR}
    Work from: {REPO_PATH}

    ## Prior Phase Context

    {PRIOR_COMPLETIONS}

    ## Phase {PHASE_LETTER} — {PHASE_NAME}

    Tasks:
    ```json
    {PHASE_TASKS_JSON}
    ```

    Cross-phase handoff targets:
    ```json
    {CROSS_PHASE_HANDOFF_TARGETS}
    ```

    ## Your Process

    Work through tasks **sequentially** — parallel dispatches cause git conflicts.

    For each task in {PHASE_TASKS_JSON}:

    1. **Extract task metadata:** extract `id` field (TASK_ID) from the task JSON object.

    2. **Mark task in-progress:**
       ```bash
       bash scripts/validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status in_progress
       ```

    3. **Read task prose:** content of {PHASE_DIR}/{task_id_lower}.md (e.g., a1.md for A1).

    4. **Capture pre-task SHA:** `TASK_BASE_SHA=$(git rev-parse HEAD)`

    5. **Dispatch implementer in background:**
       - Agent with run_in_background: true (see ./implementer-prompt.md)
       - Pass {TASK_METADATA} and {TASK_PROSE}; include boundary integration test instruction for tasks consuming prior-task output
       - Capture task_id, init: prev_output_len=0, prev_head_sha=$(git rev-parse HEAD), no_progress_count=0, intervention_count=0

    6. **Supervision loop (every {DISPATCHER_POLL_SECONDS}s):**
       a. Bash("sleep {DISPATCHER_POLL_SECONDS}")
       b. TaskOutput(task_id, block: false, timeout: 1000) -> status + output
       c. status == completed -> break to step 7
       d. new_output = output[prev_output_len:]
       e. Evaluate health (see Detection Logic):
          - Permission prompt detected -> stuck
          - Same error line 3+ consecutive times -> stuck
          - No new commits AND no new output this poll -> no_progress_count += 1; if no_progress_count >= 2 -> stuck
          - Otherwise -> healthy: update prev_output_len, prev_head_sha, reset no_progress_count = 0
       f. If stuck -> Intervention Protocol (see below)

    7. **After implementer completes: run task review loop**
       a. Dispatch task reviewer (`./task-reviewer-prompt.md`) with TASK_BASE_SHA..HEAD
       b. Extract the last `json review-summary` fenced block from the reviewer response
          - Missing or malformed JSON → treat as verdict:fail, dispatch a fresh reviewer
       c. Triage each issue in the `issues` array:
          - "fix" → dispatch implementer to fix
          - "dismiss" → document reasoning
       d. Count actionable (non-dismissed) issues:
          - 0 actionable → proceed to step 8
          - 1-5 actionable → fix all, verify fixes, proceed to step 8
          - >5 actionable → fix all, dispatch fresh reviewer (back to 7a)
          - Max 3 iterations. After 3rd with >5 issues → stop and report to orchestrate for user escalation
       e. Report to orchestrate: issues_found, severity counts, dismissed, fixed count, verdict

    8. **Mark task complete:**
       ```bash
       bash scripts/validate-plan --update-status {PLAN_DIR}/plan.json --task {TASK_ID} --status complete
       ```

    9. **Run task criteria:**
       ```bash
       bash scripts/validate-plan --criteria {PLAN_DIR}/plan.json --task {TASK_ID}
       ```
       Exit 1: criteria failed — report to orchestrate, do not proceed. Exit 0: continue.

    10. **Safe commands learning loop:**
        - Read `$TMPDIR/claude-safe-cmds-nonmatch.log` (may not exist)
        - If non-empty: deduplicate command names, ask user via AskUserQuestion which to add permanently
        - If `~/.claude/safe-commands.txt` missing, copy from `hooks/safe-commands.txt` first
        - Append approved commands to `~/.claude/safe-commands.txt`, truncate log

    11. **Handle cross-phase handoffs:**
        - If this task ID is a key in {CROSS_PHASE_HANDOFF_TARGETS}, write to each target path:
          ```markdown
          ## Handoff from {TASK_ID}
          [function signatures, file paths, config keys, APIs created]
          ```

    12. **Handle within-phase handoffs:**
        - For each later task listing this task ID in `depends_on`, write the same handoff format to {PHASE_DIR}/{target_task_id_lower}.md

    ## Detection Logic

    **Permission blocks:** Pattern containing "Do you want to proceed" followed by numbered options ("1. Yes", "2. Yes, and don't ask again"). Single keywords insufficient.

    **Repeated errors:** Same line matching error:/Error:/failed:/FAILED/Traceback/panic: appearing 3+ consecutive times in new_output.

    **No progress:** Both git HEAD hash AND TaskOutput length unchanged for 2 consecutive polls.

    ## Intervention Protocol

    | Attempt | Action |
    |---------|--------|
    | 1st | TaskStop(task_id) + re-dispatch implementer with diagnosis and guidance appended to prompt |
    | 2nd | TaskStop(task_id) + re-dispatch with full prior output summary as context |
    | After {MAX_INTERVENTION_ATTEMPTS} failures | Write escalation-{task_id}.json to phase worktree root ({REPO_PATH}), mark task skipped, continue to next task |

    After each re-dispatch: update task_id from the new agent, reset prev_output_len=0 and no_progress_count=0, then resume at step 6a.

    Escalation file format:
    {"task_id": "A3", "issue": "...", "attempts": 2, "last_output_snippet": "last 50 lines of agent output", "timestamp": "ISO8601"}

    ## Deviation Rules

    | Rule | Trigger | Action |
    |------|---------|--------|
    | 1: Auto-fix bug | Code doesn't work as intended | Dispatch implementer to fix, document |
    | 2: Auto-add critical | Missing validation, auth, error handling | Dispatch implementer to fix, document |
    | 3: Auto-fix blocker | Missing dep, broken import, wrong types | Dispatch implementer to fix, document |
    | 4: STOP | Architectural change (new table, library swap, breaking API) | Stop — report to orchestrate: what change, which task, why plan doesn't cover it |

    Only fix issues caused by the current task. Pre-existing issues go to deferred list. After 3 failed fix attempts on the same issue, stop and document.

    ## When All Tasks Are Done

    Run phase integration tests (if they exist). Failures within this phase's scope are real — fix before continuing. Tests targeting future phases can be xfail.

    Write {PHASE_DIR}/completion.md:
    ```markdown
    # Phase {PHASE_LETTER} Completion Notes

    **Date:** YYYY-MM-DD
    **Summary:** [2-4 sentences: what was built]
    **Deviations:** [Each: A1 — what changed — Rule N — reason. "None" if plan followed exactly.]
    ```

    ## Report Back

    Return to orchestrate context:
    - Tasks completed (list with IDs)
    - HEAD SHA: `git rev-parse HEAD`
    - Integration test status
    - Deviations (if any)
    - Per-task review summaries (final review-summary JSON + dismissal reasoning)
    - Any escalation files written
    - Concerns for orchestrate context
```
