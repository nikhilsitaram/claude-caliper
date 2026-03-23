# Deterministic Workflow Gates

## Problem

Agents skip workflow steps because enforcement is prose-only. Two distinct failure modes:

**Skipped reviews:** Skills describe review gates in natural language ("dispatch implementation-review", "re-review if >5 issues"), but agents under context pressure skip these entirely or claim they passed without evidence. There's no mechanism to verify a review actually happened, no machine-readable review output, and no script-level gate preventing advancement without completed reviews. Skipped reviews let bugs through that the review would have caught.

**Ignored review findings:** When reviews do run, agents can acknowledge findings but skip fixing them. The review-pr skill offers "Skip fixes, proceed" even in automated workflows. There's no tracking of which findings were fixed vs dismissed, so the audit trail is lost.

**Early stops:** Agents stop at intermediate points instead of reaching the workflow endpoint. A `create-pr` workflow should run through all phases and create the final PR; a `merge-pr` workflow should go all the way through merge. But agents sometimes stop after one phase, after creating a PR but before review, or at other arbitrary points. There's no script-level check that the pipeline actually reached the expected endpoint, so partial completions go undetected.

This affects anyone using the orchestrate/design workflow. The root cause is the same in all cases: the enforcement mechanism is prose instructions that agents can ignore, with no programmatic verification.

## Goal

Make the workflow deterministic: reviews can't be skipped, issue counts are tracked with audit trails, re-review loops are enforced, and agents continue through the full workflow to the specified endpoint — all enforced via script gates, not prose.

## Success Criteria

1. Every review produces a structured, machine-parseable record that the controlling agent verifies before advancing to the next stage
2. When a review finds more than 5 actionable issues, a fresh reviewer re-checks after fixes are applied, up to 3 iterations before escalating to the user
3. A phase cannot be marked complete without a passing implementation review on record
4. The plan cannot be marked complete without passing design-review, plan-review, and implementation reviews for all phases
5. A workflow completeness check verifies the pipeline reached the expected endpoint (PRs created/merged per workflow choice)
6. Dismissed review items include written reasoning, creating an audit trail
7. In automated workflows (merge-pr), all actionable review findings are fixed — there is no option to skip fixes

## Architecture

### Review JSON Contract

Single `reviews.json` file in the plan directory. Each review cycle appends a record:

```json
[
  {
    "type": "design-review",
    "scope": "design",
    "iteration": 1,
    "issues_found": 7,
    "severity": { "critical": 1, "high": 2, "medium": 3, "low": 1 },
    "actionable": 4,
    "dismissed": 3,
    "dismissals": [
      { "issue": "#2", "reason": "Pre-existing pattern, not introduced by this phase" }
    ],
    "fixed": 4,
    "remaining": 0,
    "verdict": "pass",
    "timestamp": "2026-03-23T14:00:00Z"
  }
]
```

Valid `type` values: `design-review`, `plan-review`, `task-review`, `impl-review`. Task-review records are for audit trail only — no gate checks them. Phase and plan gates check impl-review (cross-task) and design/plan-review respectively.
Valid `scope` values: `design`, `plan`, `task-A1` (task ID), `phase-A` (phase letter), `final`.
Verdict is binary: `pass` (zero remaining issues) or `fail` (issues remain or re-review needed).

Only the controlling context writes to `reviews.json`. Reviewer subagents output a JSON summary block in their response (see Reviewer Output Schema below). The controller reads it, triages, fixes, and writes the complete record.

### Reviewer Output Schema

Each reviewer subagent outputs a fenced JSON block labeled `review-summary` at the end of its response. This is the contract between reviewer and controller:

```json
{
  "issues_found": 7,
  "severity": { "critical": 1, "high": 2, "medium": 3, "low": 1 },
  "verdict": "fail",
  "issues": [
    { "id": 1, "severity": "critical", "category": "Cross-task inconsistency", "file": "src/api.ts:42", "problem": "Port mismatch", "fix": "Change to 3000" }
  ]
}
```

The controller extracts this block from the subagent response. Convention: the JSON appears in a fenced code block with the info string `json review-summary`. The controller searches for this marker and parses the block. If multiple blocks appear (e.g., reviewer included an example before the real one), the controller uses the last one. If the block is missing or malformed, the controller treats the review as failed (verdict: "fail") and dispatches a fresh reviewer — this prevents silent skipping.

### Review Loop Protocol

Every dispatcher (orchestrate, phase-dispatcher) runs the same deterministic loop. **Exception:** design-review retains its current user-collaborative model — the user approved the design, so changes require their involvement. The design skill presents design-review findings to the user, collaboratively fixes them, and re-dispatches until clean. Plan-review follows the autonomous loop since the plan is a derivative artifact.

Autonomous loop protocol:

```text
MAX_ITERATIONS = 3
iteration = 0

LOOP:
  iteration += 1
  dispatch reviewer → reviewer outputs review-summary JSON block
  controller extracts and parses review-summary
  controller triages: each issue → "fix" or "dismiss" (with reasoning)
  actionable_count = issues categorized as "fix"

  if actionable_count == 0:
    write record with verdict: "pass" → advance
  elif actionable_count <= 5:
    fix all actionable issues, verify fixes
    write record with verdict: "pass" → advance
  elif actionable_count > 5:
    fix all actionable issues
    write record with verdict: "fail"
    if iteration >= MAX_ITERATIONS:
      → escalate to user (AskUserQuestion)
    else:
      → LOOP (dispatch fresh reviewer)
```

### PR Verification

`--check-workflow` verifies PRs by querying GitHub directly via `gh pr list`, not by reading an agent-maintained array. This avoids the same prose-enforcement problem the design is solving — if PR tracking depended on agents writing to plan.json, agents could skip that step too.

The script queries: `gh pr list --base <target-branch> --head <source-branch> --state <state> --json number`. For multi-phase plans, it checks phase PRs targeting `integrate/<feature>` and the final PR targeting main. For single-phase, it checks the single PR targeting main.

### validate-plan Enforcement

**Gated `--update-status`:**

Phase completion (`--update-status --phase A --status "Complete (...)"`) checks:
- `reviews.json` has a record with `type: "impl-review"`, `scope: "phase-A"`, `verdict: "pass"`

Plan completion (`--update-status --plan --status Complete`) checks:
- All phases have "Complete" status
- Passing `type: "design-review"` in reviews.json
- Passing `type: "plan-review"` in reviews.json
- Passing `type: "impl-review"` for each phase in reviews.json
- Passing `type: "impl-review"`, `scope: "final"` if multi-phase

**New `--check-review` flag:**

```bash
validate-plan --check-review plan.json --type impl-review --scope phase-A
```

Reads reviews.json, finds latest record matching both `type` and `scope`, checks `verdict == "pass"` and `remaining == 0`. Exit 0 = passed, exit 1 = failed or missing.

**New `--check-workflow` flag:**

```bash
validate-plan --check-workflow plan.json
```

Checks based on `workflow` field:

| Workflow | Gates |
|----------|-------|
| `plan-only` | design-review passed, plan-review passed |
| `create-pr` | plan status Complete, all review gates passed, PRs exist (via `gh pr list`) |
| `merge-pr` | everything above + final PR merged (via `gh pr list --state merged`) |

For `plan-only`, the design skill calls `--check-workflow` as its final action. For `create-pr` and `merge-pr`, orchestrate calls it.

### Centralized Review Dispatch

**Principle:** The dispatcher owns the loop. Whoever dispatches work also dispatches review, reads results, and decides whether to proceed.

**Before (plan-review buried in sub-sub-agent):**

```text
design → design-review (sub) → draft-plan (sub) → plan-review (sub-sub)
```

**After (all reviews at controlling level):**

```text
design → design-review (sub) → draft-plan (sub) → plan-review (sub)
orchestrate → phase-dispatcher (sub) → impl-review (sub) → create-pr
```

Task-review stays in phase-dispatcher — it's tightly coupled to per-task implementation and the dispatcher is explicitly a dispatch-only agent.

### Workflow Continuity

Script-enforced via `--check-workflow`. The controlling context calls this as its final action. If gates are unsatisfied, the script exits 1 with the specific missing gates listed to stderr.

Additionally, `--update-status` refuses to advance status if prerequisite reviews haven't passed. This creates two enforcement layers: the status gate prevents marking things done without reviews, and the workflow gate verifies the pipeline reached the endpoint.

## Alternatives Considered

**Stronger prose instructions only:** The simplest approach — rewrite SKILL.md files with more emphatic enforcement language. Rejected because this is what we have today and agents still skip steps. Prose enforcement fails under context pressure regardless of wording strength.

**Extend existing success_criteria pattern:** `validate-plan --criteria` already does script-level gating with run commands and expected outputs. Reviews could be added as success_criteria entries in plan.json (e.g., `{"run": "validate-plan --check-review ... --type impl-review --scope phase-A", "expect_exit": 0}`). This would reuse existing enforcement without new flags. However, criteria are defined at plan creation time and can't account for dynamic review state. Reviews produce runtime artifacts (reviews.json) that don't exist when the plan is written. A dedicated `--check-review` flag is cleaner because it queries runtime state directly rather than trying to encode it in static plan metadata.

**Hook-based enforcement:** A PreToolUse hook could intercept `--update-status` calls and check for review records before allowing them. This would enforce at the runtime level rather than in the script. Rejected because hooks are a blunt instrument — they can approve or block but can't provide detailed error messages about which specific review is missing. Gating inside the script itself provides better diagnostics.

## Key Decisions

**Single reviews.json vs per-review files:** Single file is simpler to manage and audit. No concurrency issue because orchestrate processes phase completions serially. Trade-off: slightly more complex jq append vs simple file creation.

**Controller writes, reviewer outputs:** Controller writes to reviews.json, not the reviewer. This ensures only one agent writes to the file and the controller can add triage/resolution fields. The reviewer outputs a `json review-summary` fenced block that the controller extracts. If the block is missing or malformed, the review is treated as failed — this converts a soft convention into a hard gate because a missing summary means re-review, not silent pass.

**Re-review threshold on actionable count (post-triage) vs total count:** Actionable count is fairer — if a reviewer produces many false positives, the re-review penalty applies only to real issues. Trade-off: agent could over-dismiss to stay under threshold, but dismissals are tracked in reviews.json for audit.

**Gating --update-status vs separate gate check:** Gating the existing command is more deterministic — the agent already calls --update-status to advance, so the gate is on the natural advancement path. A separate check could be skipped. Trade-off: makes --update-status slower (reads reviews.json).

**GitHub query for PR verification vs agent-maintained prs array:** Using `gh pr list` as ground truth avoids the circular problem of prose-enforcing the enforcement mechanism. The agent can't fake a PR's existence on GitHub. Trade-off: requires `gh` CLI and network access, but both are already required by the workflow.

## Non-Goals

- Validating review quality via script (inherently subjective — script only checks that review happened and passed)
- Full state machine in plan.json (workflow field + reviews.json + gh queries are sufficient)
- Changing the >5 threshold (it's about fresh reviewer quality, not a skip mechanism)
- Changing task-review dispatch location (stays in phase-dispatcher)

## Implementation Approach

Single phase — changes are interconnected.

### File Changes

| File | Action | Change |
|------|--------|--------|
| `scripts/validate-plan` | Modify | Add `--check-review`, `--check-workflow` flags; gate `--update-status` on review records |
| `skills/design/SKILL.md` | Modify | Add plan-review dispatch after draft-plan returns; add review loop protocol for design-review and plan-review; call `--check-workflow` for plan-only |
| `skills/draft-plan/SKILL.md` | Modify | Remove plan-review dispatch (step 9 and Plan Review Gate section) |
| `skills/orchestrate/SKILL.md` | Modify | Add review loop protocol; add `--check-review` calls before create-pr; call `--check-workflow` as final action |
| `skills/orchestrate/phase-dispatcher-prompt.md` | Modify | Add review loop protocol for task reviews; parse reviewer JSON output |
| `skills/design-review/reviewer-prompt.md` | Modify | Add `review-summary` JSON output block |
| `skills/plan-review/reviewer-prompt.md` | Modify | Add `review-summary` JSON output block |
| `skills/implementation-review/reviewer-prompt.md` | Modify | Add `review-summary` JSON output block |
| `skills/orchestrate/task-reviewer-prompt.md` | Modify | Add `review-summary` JSON output block |
| `skills/review-pr/SKILL.md` | Modify | Remove "Skip fixes, proceed" option when invoked from automated merge-pr workflow |

### Task Order

1. Add `--check-review` flag to validate-plan (reads reviews.json, checks type+scope+verdict)
2. Gate `--update-status` on review completion (phase requires impl-review pass; plan requires all reviews pass)
3. Add `--check-workflow` flag (queries review records + `gh pr list` for PR verification)
4. Update all 5 reviewer prompts to output `review-summary` JSON block
5. Add review loop protocol to orchestrate and phase-dispatcher-prompt
6. Remove plan-review dispatch from draft-plan; add plan-review dispatch to design after draft-plan returns
7. Add `--check-workflow` call to design (plan-only) and orchestrate (create-pr/merge-pr) as final action
8. Remove "Skip fixes, proceed" from review-pr when invoked from automated workflow

**Interaction with recent changes:** The phase-pr-review-gate feature (merged in PR #109) added external review polling (steps 15-16) and conditional merge strategy to orchestrate. These changes are complementary — deterministic-workflow adds review record enforcement and the review loop protocol, while phase-pr-review-gate added the external review polling mechanism. No conflicts expected since they modify different aspects of the phase completion flow.
