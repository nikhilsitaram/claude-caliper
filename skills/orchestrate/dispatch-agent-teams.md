# Agent Teams Dispatch Protocol

Dispatch protocol for executing plan tasks via agent team teammates. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable — the design skill verifies this flag is set and offers a fallback if not.

## Verify Environment

Before dispatching any teammates, verify: `[[ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" == "1" ]]`. If not set, abort with an error — the design skill should have caught this during mode selection, but this guards against direct orchestrate invocation.

## Spawn Implementer Teammates

Spawn implementer teammates for tasks with no unmet dependencies (verified via `scripts/validate-plan --check-deps`). Each teammate:
- Receives task metadata + prose from `./implementer-prompt.md`
- Gets its own auto-provisioned worktree
- Manages its own lifecycle (marks in-progress, writes completion notes, marks complete)

**Note:** `--check-base` runs at orchestrate startup and before each phase dispatch (multi-phase). No separate dispatch-level base check is needed.

## Process Completions (Push-Based)

When an implementer teammate goes idle (push notification — no polling):

1. Read the teammate's completion notes (`{PHASE_DIR}/{TASK_ID_LOWER}-completion.md`)
2. Dispatch a reviewer teammate (`./task-reviewer-prompt.md`) with the task's branch-specific diff range (task worktree `BASE..HEAD`, not the phase-wide range)
3. When reviewer goes idle, extract the last `json review-summary` block
4. Triage issues: "fix" (send to implementer via mailbox) or "dismiss" (document reasoning)
5. If fixes needed: send review feedback to the *original implementer* via mailbox messaging — the implementer still has context and files. Implementer fixes and goes idle again. Repeat until review passes.
6. Validate with `scripts/validate-plan --criteria plan.json --task {TASK_ID}`
7. Kill teammate only after review passes and criteria met
8. **Record task-review:** Write a passing record to `reviews.json` (in the plan directory): `jq '. += [{"type":"task-review","scope":"{TASK_ID}","verdict":"pass","remaining":0}]' "$PLAN_DIR/reviews.json" > "$PLAN_DIR/reviews.json.tmp" && mv "$PLAN_DIR/reviews.json.tmp" "$PLAN_DIR/reviews.json"`. Create the file (`echo '[]'`) if it doesn't exist. For trivial tasks where review is overhead, use `"verdict":"skip","reason":"<justification>"` instead.
9. **Incremental merge:** Merge this task's branch into the feature/integration branch so dependent tasks see prerequisite code. Use `git -C <your worktree path> merge <task-branch>` — the `-C` flag prevents CWD drift that occurs after processing teammate completions. After merge: `git worktree remove <teammate-worktree-path>` then `git branch -d <task-branch>`. Verify CWD with `pwd`; if it drifted, `cd` back.
10. **Dependency gate:** Check if any blocked tasks are now unblocked. For each candidate, run `scripts/validate-plan --check-deps plan.json --task {TASK_ID}`. If all dependencies are complete, spawn a new implementer teammate for that task (worktree created from the now-updated feature branch).

**Phase completion gate:** Lead cannot advance until ALL teammates for this phase (implementers and reviewers) are terminated.

## Handle Escalations

Teammates send Rule 4 violations (architectural changes) to lead via mailbox. Lead presents to user: what change, which task, why plan doesn't cover it. Wait for user decision.

## Teammate Spawn Format

Implementer teammates use the template in `./implementer-prompt.md`. Key spawn parameters:

```yaml
Teammate spawn:
  model: "{IMPLEMENTER_MODEL}"
  mode: "acceptEdits"
  description: "Implement {TASK_ID}: [task name]"
  prompt: <filled from implementer-prompt.md template>
```

Task reviewer teammates use the template in `./task-reviewer-prompt.md`. Key spawn parameters:

```yaml
Teammate spawn:
  model: "{REVIEWER_MODEL}"
  mode: "auto"
  description: "Review Task {TASK_ID}"
  prompt: <filled from task-reviewer-prompt.md template>
```

Both templates document their required variables and full prompt content.
