---
name: design
description: Use when creating features, building components, adding functionality, or modifying behavior - before any creative or implementation work begins
---

# Design: Ideas Into Plans

Turn ideas into validated designs through collaborative dialogue before any code is written.

<HARD-GATE>
Do NOT invoke implementation skills, write code, or scaffold projects until you have presented a design and the user has explicitly approved it. Skipping design validation is the #1 cause of wasted work in AI-assisted sessions. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Anti-Pattern: "Too Simple to Need a Design"

A todo list, a utility function, a config change — all go through this process. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be a few sentences, but you must present it and get approval.

## Checklist

Complete in order:

1. **Explore context** — files, docs, recent commits
2. **Challenge assumptions** — question the framing before accepting it
3. **Ask clarifying questions** — smart batches (see below)
4. **Propose 2-3 approaches** — trade-offs and your recommendation
5. **Present design** — sections scaled to complexity, approval after each
6. **Set up worktree** — branch type depends on phase count (known from step 5 phasing discussion):
   - Multi-phase: `git worktree add -b integrate/<feature> .claude/worktrees/<feature>` — integration branch; phase worktrees created by orchestrate as siblings
   - Single-phase: `git worktree add -b <feature> .claude/worktrees/<feature>` — feature branch; orchestrate works here directly, PRs to main
   1. Bootstrap dependencies per **See:** ./dependency-bootstrap.md
   2. Run tests to establish a clean baseline
7. **Choose workflow extent** — if not already chosen, ask the user:

    AskUserQuestion (header: "Workflow"):
    - **Create PR** (default) — Orchestrate → create-pr (PR created, stops for human review)
    - **Merge PR** — Orchestrate → create-pr → review-pr → merge-pr (PR created, reviewed, and merged)
    - **Plan only** — Stop after the plan is written and reviewed (orchestrate will not run)

    Store the choice for step 12.

8. **Design approval gate** — use AskUserQuestion with options `["Approve design (auto turn on acceptEdits)", "Needs changes"]`. If "Needs changes," return to step 5. On approval, create the sentinel: `mkdir -p <plan-dir> && touch <plan-dir>/.design-approved` — this enables auto-approved edits for the rest of the session via the PermissionRequest hook.
9. **Write design doc** — `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`, commit
10. **Dispatch design-review subagent** — fresh Opus agent validates design before planning (hard gate)
11. **Dispatch draft-plan subagent** — fresh Opus agent with design doc path and worktree path (zero design context)
12. **Route workflow** — Map the step 7 choice to the schema enum value (`Create PR` → `create-pr`, `Merge PR` → `merge-pr`, `Plan only` → `plan-only`), then write: `jq --arg w "<mapped-value>" '.workflow = $w' plan.json > tmp && mv tmp plan.json`

    For **Create PR** or **Merge PR**: invoke orchestrate.
    For **Plan only**: run `scripts/validate-plan --check-workflow plan.json` to verify design-review and plan-review passed. Report the plan file path and stop.

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Review the design doc at docs/plans/<folder>/design-<topic>.md
    using the design-review skill.
    Working directory: .claude/worktrees/<feature>"
)
```

If design-review finds issues, present them to the user, collaboratively fix the design doc, and re-dispatch design-review until clean. Only dispatch draft-plan after design-review passes. After design-review passes, write a review record to `{PLAN_DIR}/reviews.json` (initialize with `[]` if it doesn't exist): `jq --argjson entry '{"type":"design-review","scope":"design","remaining":0,"verdict":"pass","timestamp":"<ISO8601>"}' '. += [$entry]' reviews.json > tmp && mv tmp reviews.json`

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Read the design doc at docs/plans/<folder>/design-<topic>.md and write
    an implementation plan using the draft-plan skill.
    Working directory: .claude/worktrees/<feature>"
)
```

After draft-plan returns, dispatch plan-review with the same review loop protocol:

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Review the plan at docs/plans/<folder>/plan.json
    using the plan-review skill.
    Design doc: docs/plans/<folder>/design-<topic>.md
    Working directory: .claude/worktrees/<feature>"
)
```

Extract the `json review-summary` block from the response. Triage issues (fix plan files or dismiss with reasoning). If >5 actionable issues, fix and re-dispatch reviewer (max 3 iterations, then escalate to user). Write review record to `{PLAN_DIR}/reviews.json` with type:"plan-review", scope:"plan".

**Approval gate format:**

```json
{
  "questions": [{
    "question": "Design approved?",
    "options": [
      { "label": "Approve design (auto turn on acceptEdits)", "description": "Write design doc and proceed to review" },
      { "label": "Needs changes", "description": "Continue iterating on the design" }
    ]
  }]
}
```

On "Approve design (auto turn on acceptEdits)", immediately run: `mkdir -p <plan-dir> && touch <plan-dir>/.design-approved`

## Challenging Assumptions

Before clarifying questions, challenge the framing like a senior PM:

- "What problem does this solve, and for whom?"
- "What would users actually do with this?"
- "Is there a simpler alternative?"

**Example:** User: "All users should have public pages." Challenge: "A public page needs content to show. What would a non-creator put there?" — may surface that the feature isn't needed yet.

## Smart Question Batching

- **Text questions** (word-described choices): batch up to 4 per AskUserQuestion
- **Visual questions** (need ASCII mockups): one at a time, use `markdown` preview
- Text first, visual last
- Each question gets its own options — never "all correct / not correct" toggles
- Ambiguous concepts: explain the difference, offer interpretations as options

## Presenting the Design

- Scale sections to complexity (few sentences to 200-300 words)
- Ask after each section: "Does this look right?"
- Cover: architecture, components, data flow, error handling, testing
- Note shared foundations as **phasing candidates**

**Phasing** (after all sections):
- Simple: "Single phase, no dependency layers. Sound right?"
- Complex: "N dependency layers. Phase 1 — [name], Phase 2 — ... Adjust?"

Use AskUserQuestion with "Looks good" / "Adjust phases" options.

## Design Doc Contents

When writing the design doc (`docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`):
- Sections in order: Problem, Goal, Success Criteria, Architecture, Key Decisions, Non-Goals, Implementation Approach
- **Problem** — what's broken, who's affected, consequences of not solving
- **Success Criteria** — human-verifiable behavioral statements (not "tests pass"); collectively complete (all pass = goal met), individually necessary
- If multi-phase: **Implementation Approach** includes phase rationale
