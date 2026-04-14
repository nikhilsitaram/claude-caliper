# Agent Teams Dispatch Protocol

Dispatch protocol for executing plan tasks via agent team teammates. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable — the design skill verifies this flag is set and offers a fallback if not.

## Verify Environment

Before dispatching any teammates, verify: `[[ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" == "1" ]]`. If not set, abort with an error — the design skill should have caught this during mode selection, but this guards against direct orchestrate invocation.

## Create Team

Before spawning any teammates, create the team: `TeamCreate({team_name: "{PLAN_NAME}"})` where `{PLAN_NAME}` is derived from the plan (e.g., branch name or plan title, kebab-cased). Store as `TEAM_NAME`.

## Spawn Implementer Teammates

For each task in the phase, check deps: `validate-plan --check-deps "$PLAN_JSON" --task {TASK_ID}`. Collect all tasks that pass. For each ready task, extract metadata (strip `status` — orchestrator state not needed by implementer):

```bash
TASK_METADATA=$(jq -c --arg id "{TASK_ID}" '[.phases[].tasks[] | select(.id == $id)][0] | del(.status)' "$PLAN_JSON")
TASK_COMPLEXITY=$(echo "$TASK_METADATA" | jq -r '.complexity')
REVIEWER_NEEDED=$(echo "$TASK_METADATA" | jq -r '.reviewer_needed')
case "$TASK_COMPLEXITY" in
  low)    COMPLEXITY_GUIDANCE="Be efficient -- minimal implementation, avoid over-engineering." ;;
  medium) COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
  high)   COMPLEXITY_GUIDANCE="Think carefully -- consider edge cases, failure modes, and long-term maintainability." ;;
  *)      COMPLEXITY_GUIDANCE="Standard thoroughness -- test the happy path and key edge cases." ;;
esac
```

`TASK_COMPLEXITY` and `COMPLEXITY_GUIDANCE` are passed to both implementer and reviewer prompts. `REVIEWER_NEEDED` gates reviewer dispatch (see Process Completions step 2).

Spawn **all ready implementer teammates in a single message** — one Agent call per task, all in the same turn. Splitting spawns across turns breaks parallelism. Each teammate:
- Uses `claude-caliper:task-implementer` agent with dynamic context from `./implementer-prompt.md`
- Gets its own auto-provisioned worktree
- Manages its own lifecycle (marks in-progress, writes completion notes, marks complete)

**Note:** `--check-base` runs at orchestrate startup and before each phase dispatch (multi-phase). No separate dispatch-level base check is needed.

## Process Completions (Push-Based)

When an implementer teammate goes idle (push notification — no polling):

1. Read the teammate's completion notes (`{PHASE_DIR}/{TASK_ID_LOWER}-completion.md`)
2. If `REVIEWER_NEEDED` is `"false"`: record a skip in `reviews.json` (`"verdict":"skip","reason":"reviewer_needed: false"`) and jump to step 6 — skip steps 3–5 and step 8 (verdict already recorded). If `REVIEWER_NEEDED` is `"true"`: dispatch a `claude-caliper:task-reviewer` teammate with dynamic context from `./task-reviewer-prompt.md`, using the task's branch-specific diff range (task worktree `BASE..HEAD`, not the phase-wide range)
3. When reviewer goes idle, extract the last `json review-summary` block. Shut down the reviewer: `SendMessage({to: "review-{TASK_ID_LOWER}", message: {type: "shutdown_request"}})` and wait for the idle notification confirming shutdown before proceeding — if step 5 re-dispatches a reviewer with the same name, the previous instance must be fully terminated to avoid name collisions.
4. Triage issues: "fix" (send to implementer via mailbox) or "dismiss" (document reasoning)
5. If fixes needed: send review feedback to the *original implementer* via mailbox messaging — the implementer still has context and files. Implementer fixes and goes idle again. Dispatch a new reviewer teammate, repeat until review passes.
6. Validate with `validate-plan --criteria plan.json --task {TASK_ID}`
7. Shut down implementer after review passes and criteria met: `SendMessage({to: "impl-{TASK_ID_LOWER}", message: {type: "shutdown_request"}})`. Wait for the teammate's idle notification confirming shutdown before proceeding — the teammate must fully terminate before its worktree can be removed.
8. **Record task-review** (skip if `REVIEWER_NEEDED` was `"false"` — verdict already recorded as skip in step 2): Write a passing record to `reviews.json` (in the plan directory): `jq '. += [{"type":"task-review","scope":"{TASK_ID}","verdict":"pass","remaining":0}]' "$PLAN_DIR/reviews.json" > "$PLAN_DIR/reviews.json.tmp" && mv "$PLAN_DIR/reviews.json.tmp" "$PLAN_DIR/reviews.json"`. Create the file (`echo '[]'`) if it doesn't exist.
9. **Incremental merge:** Merge this task's branch into the feature/integration branch so dependent tasks see prerequisite code. Use `git -C <your worktree path> merge <task-branch>` — the `-C` flag prevents CWD drift that occurs after processing teammate completions. After merge: `git worktree remove <teammate-worktree-path>` then `git branch -d <task-branch>`. Verify CWD with `pwd`; if it drifted, `cd` back.
10. **Dependency gate:** Check if any blocked tasks are now unblocked. For each candidate, run `validate-plan --check-deps plan.json --task {TASK_ID}`. If all dependencies are complete, spawn a new implementer teammate for that task (worktree created from the now-updated feature branch).

**Phase completion gate:** Lead cannot advance until ALL teammates for this phase (implementers and reviewers) are terminated. After the final phase completes (not each phase), call `TeamDelete()` to clean up team resources — the team persists across phases so dependent tasks in later phases can be dispatched to new teammates without recreating the team.

## Handle Escalations

Teammates send Rule 4 violations (architectural changes) to lead via mailbox. Lead presents to user: what change, which task, why plan doesn't cover it. Wait for user decision.

## Teammate Spawn Format

Spawn teammates using the Agent tool with explicit `team_name`, `mode`, and `subagent_type` parameters. These parameters must appear directly in the Agent tool call — YAML descriptions are not sufficient.

Implementer teammates use the template in `./implementer-prompt.md`:

```text
Agent({
  team_name: "{TEAM_NAME}",
  name: "impl-{TASK_ID_LOWER}",
  subagent_type: "claude-caliper:task-implementer",
  model: "{TASK_IMPLEMENTER_MODEL}",
  mode: "acceptEdits",
  description: "Implement {TASK_ID}: [task name]",
  prompt: <filled from implementer-prompt.md template, substituting {TASK_COMPLEXITY}, {COMPLEXITY_GUIDANCE}, and other variables; omit {WORKTREE_PATH} — the teammate uses its auto-provisioned CWD>
})
```

Task reviewer teammates use the template in `./task-reviewer-prompt.md`:

```text
Agent({
  team_name: "{TEAM_NAME}",
  name: "review-{TASK_ID_LOWER}",
  subagent_type: "claude-caliper:task-reviewer",
  model: "{TASK_REVIEWER_MODEL}",
  mode: "auto",
  description: "Review Task {TASK_ID}",
  prompt: <filled from task-reviewer-prompt.md template, substituting {TASK_COMPLEXITY}, {COMPLEXITY_GUIDANCE}, and other variables>
})
```

`mode: "acceptEdits"` is critical for implementers — without it, every Edit/Write call prompts the lead for approval, blocking parallel execution. Both templates document their required variables and full prompt content.
